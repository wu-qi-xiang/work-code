#! /usr/bin/python
# -*- coding: utf-8 -*-

import json
import os
import sys
import getopt
import re
import time
import datetime
from Queue import Queue
from threading import *
import subprocess
from encryptUtils import * 

mongos_password = "password"
mysql_password = "password"
mongoshost = "mongo"
# mongoshost = "mongos-0.mongos-hs"  # for k8s
mysqlhost = "mysql"
# mysqlhost = "mysql-0.mysql-hs"  # for k8s

mongo_outdir = "/data/titan-backup/mongo"
mysql_outdir = "/data/titan-backup/mysql"
done_file_path = mongo_outdir + "/done_colls"

MongoAuth = ''' --host {mongoshost} -u qingteng -p {passwd} --authenticationDatabase=admin '''.format(mongoshost=mongoshost,passwd=mongos_password)
MysqlAuth = ''' --host {mysqlhost} -uroot -p{passwd} '''.format(mysqlhost=mysqlhost,passwd=mysql_password)

def load_config_from_envconfig(envconfig_json):
    if os.path.exists(envconfig_json):
        global config_file
        global mongoshost
        global mysqlhost
        global mongos_password
        global mysql_password
        global mongo_outdir
        global mysql_outdir
        global MongoAuth
        global MysqlAuth
        envconfig = json.load(file(envconfig_json))
        config_file = envconfig['BACKUP_CONFIG']
        mongoshost = envconfig['MONGOS_HOST']
        mysqlhost = envconfig['MYSQL_HOST']
        mysql_port = envconfig.get("MYSQL_PORT","3306")

        mongo_outdir = envconfig.get("mongo_outdir","/data/titan-backup/mongo")
        mysql_outdir = envconfig.get("mysql_outdir","/data/titan-backup/mysql")

        pbeConfig = getPbeConfig(envconfig.get("pbe_path","/run/secrets/pbeconfig"))
        mongos_password = getPlainSecret(pbeConfig, envconfig.get("mongos_password_file","/run/secrets/mongo_password"))
        mysql_password = getPlainSecret(pbeConfig, envconfig.get("mysql_password_file","/run/secrets/mysql_password"))

        MongoAuth = ''' --host {mongoshost} -u qingteng -p {passwd} --authenticationDatabase=admin '''.format(mongoshost=mongoshost,passwd=mongos_password)
        MysqlAuth = ''' --host {mysqlhost} -uroot -p{passwd} --port={mysql_port} '''.format(mysqlhost=mysqlhost,mysql_port=mysql_port,passwd=mysql_password)

    else:
        print("no config file,exit")
        exit(1)


MONGOBACKUP_REQUIRE_SPACE = 5
MYSQLBACKUP_REQUIRE_SPACE = 8

manually=True

export_cmd_queue = Queue()
restore_cmd_queue = Queue()

console_lock = Semaphore(value=1)

def setAuto():
   global manually
   manually=False

def hidden_passwd(msg):
    result = str(msg)
    if mongos_password:
        result = result.replace(mongos_password,'******')
    if mysql_password:
        result = result.replace(mysql_password,'******')
    return result

def log_error(msg):
    print('\033[31m' + "ERROR:" + hidden_passwd(msg) + '\033[0m')
    sys.exit(1)

def log_warn(msg):
    console_lock.acquire()
    print('\033[35m' + "WARN:" + hidden_passwd(msg) + '\033[0m')
    console_lock.release()

def log_info(msg):
    console_lock.acquire()
    print('\033[32m' + "INFO:" + hidden_passwd(msg) + "\033[0m")
    console_lock.release()

def log_debug(msg):
    console_lock.acquire()
    print("DEBUG:" + hidden_passwd(msg))
    console_lock.release()

def get_input(default_value, prompt=""):
    v = raw_input(prompt)
    if v == "" or v.strip() == "":
        return default_value
    else:
        return v.strip()

def log_warn_and_confirm(msg):
    
    print('\033[32m' + str(msg) + "\033[0m")
    if not manually:
        return
    v = get_input("Y","Are you sure to continue, default is Y, Enter [Y/N]: ")
    if v == "n" or v == "no" or v == "N" or v == "NO" or v == "No":
        print("Abort, exit." + "\n")
        exit(0)

def exec_subprocess(cmd, verbose=False, realtimeoutput=False):
    if verbose:
        log_debug("exec_subprocess:" + cmd )

    cmd_p = subprocess.Popen(cmd, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if realtimeoutput:
        while True:
            output = cmd_p.stdout.readline()
            if output == '' and cmd_p.poll() is not None:
                break
            if output:
                print(output.strip())
    else:
        output, unused_err = cmd_p.communicate()

    status = cmd_p.returncode
    if status != 0 :
        log_warn("Error code: {status} Failed to execute command: {cmd}".format(status=status,cmd=cmd))
        log_warn(output if output else "-")
    else:
        if verbose:
            log_debug(output)
        
        return output.strip()

def check_outdir_space(outdir, min_space):
    
    _cmd = '''df -Pk {outdir} | tail -n 1 | awk '{print $4}' '''.replace("{outdir}", outdir)

    free_space = exec_subprocess(_cmd)
    free_space_G = int(free_space)/1024/1024
    if free_space_G < min_space:
        log_error("free_space of {outdir} is not enough, exit".format(outdir=outdir))
    
    log_warn_and_confirm("free_space of {outdir} is {free} G".format(outdir=outdir,free=str(free_space_G)))

    return free_space_G

def read_export_conf():
    return json.load(file(config_file))

def testMongoConnection():
    _cmd = '''mongo --quiet $authStr --eval 'print("test connection success")' '''.replace("$authStr",MongoAuth)
    result = exec_subprocess(_cmd)
    if "test connection success" in result:
        log_info("connect mongo success")
    else:
        log_error("connect mongo failed")

def get_db_coll_stats(database,outdir):
    _cmd = '''mongo --quiet $authStr $database --eval 'db.getCollectionNames().map(function(coll) {stats = db.getCollection(coll).stats(); return { "name":coll,"size":stats.size.valueOf().toString(), "totalSize": (stats.storageSize + stats.totalIndexSize)/1024/1024, "count": stats.count,"avgObjSize": stats.avgObjSize?stats.avgObjSize:-1,"storageSize": stats.storageSize/1024/1024 ,"totalIndexSize": stats.totalIndexSize/1024/1024  }}).sort(function(e1, e2) {return e1.size - e2.size})' '''.replace("$database",database).replace("$authStr",MongoAuth).replace("$outdir",outdir)
    # | tee $outdir/mongo_$database_stat.json

    coll_stats = []

    result = exec_subprocess(_cmd)
    if not result:
        return coll_stats
    
    index = result.find("[")
    coll_stats = json.loads(result[index:])

    return coll_stats

def do_mongo_backup(outdir):
    
    exec_subprocess("mkdir -p {outdir} && rm -rf {outdir}/mongodump && rm -rf {outdir}/mongoexport && mkdir -p {outdir}/mongodump && mkdir -p {outdir}/mongoexport".format(outdir=outdir))
    free_space_G = check_outdir_space(outdir, MONGOBACKUP_REQUIRE_SPACE)

    all_export_config = read_export_conf()
    export_config = all_export_config["mongo"]
    common_config = export_config["_COMMON_"]
    databases = export_config["databases"]
    db_coll_stats = {}

    # get version
    version = exec_subprocess('''mongo --version | head -n 1 |cut -d ' ' -f 4 > $outdir/mongoversion '''.replace("$outdir",outdir))

    # prepare command
    for db in databases:
        coll_stats = get_db_coll_stats(db, outdir)
        #log_debug(coll_stats)
        db_exclude_colls = export_config.get(db, {}).get("_EXCLUDE_", [])
        specific_colls = export_config.get(db, {}).keys()
        if common_config.get('mode',0) == 0:
            db_coll_stats[db] = [stat for stat in coll_stats if stat['name'] in specific_colls]
        else:
            db_coll_stats[db] = [stat for stat in coll_stats if stat['name'] not in db_exclude_colls]
        

    warn_limits = {}
    warn_exportsize = {}
    export_threshold = 1 * 1024 * 1024 * 1024
    totalExportSize = 0
    for db,coll_stats in db_coll_stats.items(): 
        db_common_config = export_config.get(db, {}).get("_COMMON_", common_config)   
        for stats in coll_stats:
            coll = stats["name"]
            _cmd = MongoAuth + " --db={db} --collection={coll}".format(db=db, coll=coll)
            _conf = export_config.get(db, {}).get(coll, db_common_config.copy())

            if not _conf.has_key("limit"):
                _conf["limit"] = db_common_config["limit"]
    
            limit = _conf["limit"]

            if limit == "all":
                stats["exportSize"] = int(stats["size"])
            else:
                if int(stats["count"]) > int(limit):
                    warn_limits[db+"."+coll] = (stats["count"], limit)
                    stats["exportSize"] = stats["avgObjSize"] * int(limit)
                else:
                    stats["exportSize"] = int(stats["size"])
            
            totalExportSize = totalExportSize + stats["exportSize"]
            if stats["exportSize"] > export_threshold :
                warn_exportsize[db+"."+coll] = stats["exportSize"]


    print(json.dumps(db_coll_stats,indent = 4, sort_keys = True))
    with open("/tmp/mongostats.json", 'w') as f:
        json.dump(db_coll_stats, f, indent = 4, sort_keys = True)
    
    os.system("cp /tmp/mongostats.json {outdir}".format(outdir=outdir))

    # print warn, some collections will be discard
    exec_subprocess("echo {totalExportSize} > {outdir}/mongo_warn.log".format(outdir=outdir,totalExportSize=totalExportSize))
    if len(warn_limits) > 0:
        for db_coll, limit_info in warn_limits.items():
            count,limit = limit_info
            warn_msg = "{db_coll:<56} count: {count:<10} export: {limit}".format( db_coll=db_coll, count=count, limit=limit)
            log_warn(warn_msg)
            exec_subprocess("echo '{warn_msg}' >> {outdir}/mongo_warn.log".format(outdir=outdir,warn_msg=warn_msg))
    
        log_warn_and_confirm("")

    if len(warn_exportsize) > 0:
        log_warn("some collection too big")
        for db_coll, exportSize in warn_exportsize.items():
            log_warn("{db_coll:<56} exportSize: {exportSize} M".format( db_coll=db_coll, exportSize=int(exportSize/1024/1024)))
    
        log_warn_and_confirm("")

    log_info("all dump file will use about {size} M disk space".format(size=int(totalExportSize/1024/1024)+2))
    log_info("because will targz dump file,so totally need about {size} M disk space".format(size=int(1.2*(totalExportSize/1024/1024 + 2))))
    if free_space_G * 1024 < (1.2*totalExportSize/1024/1024) + 3000:
        log_error("free space is {free_space_G}G, not enough".format(free_space_G=free_space_G))
    log_warn_and_confirm("")

    # prepare all command 
    global export_cmd_queue
    for db, coll_stats in db_coll_stats.items(): 
        db_common_config = export_config.get(db, {}).get("_COMMON_", common_config)   
        for stats in coll_stats:
            coll = stats["name"]
            _cmd = MongoAuth + " --db={db} --collection={coll}".format(db=db, coll=coll)
            _conf = export_config.get(db, {}).get(coll, db_common_config.copy())

            if not _conf.has_key("method"):
                _conf["method"] = db_common_config["method"]
            
            method = _conf["method"]
            query = _conf.get("query","{}")

            # process limit, from limit get min _id
            real_limit = None
            limit_info = warn_limits.get(db+"."+coll, None)
            if limit_info is not None:
                real_limit = limit_info[1]
            
            _cmd = method + " " + _cmd  
            # _cmd like: mongodump -u qingteng -p yp1riWdR6C9cIiAx --authenticationDatabase=admin  --db=wisteria_assets --collection=kb_info
            if method == "mongodump":
                if real_limit is not None:
                    mongo_find = '''db.$coll.find($query, {"_id":1}).sort({_id:-1}).skip($skip).limit(1) '''.replace('$query', query).replace("$skip", real_limit).replace("$coll",coll)

                    get_limit_cmd = '''mongo {authStr} {db} --eval='{mongo_cmd}' |grep "_id" '''.format(db=db,authStr=MongoAuth,mongo_cmd=mongo_find)

                    limit_id = None
                    limit_id_result = exec_subprocess(get_limit_cmd)
                    log_info(limit_id_result)
                    if limit_id_result:
                        matchObj = re.search(r'ObjectId\("(.*)"\)', limit_id_result)
                        if matchObj:
                            limit_id = matchObj.group(1)

                    if limit_id is not None:
                        # add _id to query
                        querystr = query[:-1]
                        if querystr == '{':
                            query =  querystr + '''"_id": {"$gt": {"$oid": "$min_id"}}} '''.replace("$min_id",limit_id)
                        else:
                            query = querystr + "," + '''"_id": {"$gt": {"$oid": "$min_id"}}} '''.replace("$min_id",limit_id)

                if query != "{}":    
                    _cmd = _cmd + ''' --query='{query}' '''.format(query=query)
                _cmd = _cmd + ''' --out={outdir}/mongodump/ '''.format(outdir=outdir)
            else:
                if query != "{}":
                    _cmd = _cmd + ''' --query='{query}' '''.format(query=query)
                if real_limit is not None:
                    _cmd = _cmd + ''' --limit={limit} '''.format(limit=real_limit)
                _cmd = _cmd + ''' --out={outdir}/mongoexport/{db}.{coll}.json '''.format(outdir=outdir,db=db,coll=coll)

            log_debug(_cmd.strip())
            export_cmd_queue.put(_cmd)

    # run export command
    time1 = int(time.time())
    export_thread_num = 8
    for i in range (export_thread_num):
        ti = Thread(target=export_consumer, args=(export_cmd_queue, str(i),))
        ti.setDaemon(True)
        ti.start()

    for i in range (export_thread_num):
        export_cmd_queue.put("__END__")

    export_cmd_queue.join()

    time2 = int(time.time())
    print("mongo export cost:" + str(time2-time1) + "s")

    print("now wait to tar backup file")
    nowstr = time.strftime('%Y%m%d%H%M%S',time.localtime(time.time()))
    exec_subprocess("cd {outdir} && tar -czvf mongobackup-{nowstr}.tar.gz mongodump mongoexport mongoversion mongostats.json mongo_warn.log --remove-files".format(nowstr=nowstr,outdir=outdir), realtimeoutput=True)

def export_consumer(export_queue, num):
    log_info("export consumer " + num + " start")
    while True:
        export_cmd = export_queue.get()
        if export_cmd == "__END__":
            log_info("export consumer " + num + "  end")
            export_queue.task_done()
            return

        log_info("export consumer " + num + " process:" + export_cmd)
        exec_subprocess(export_cmd, realtimeoutput=True)
        export_queue.task_done()

def testMysqlConnection():
    _cmd = '''mysql -s {authStr} -e 'select "test connection success" as status' '''.format(authStr=MysqlAuth)
    result = exec_subprocess(_cmd)
    if "test connection success" in result:
        log_info("connect mysql success")
    else:
        log_error("connect mysql failed")
# MYSQL
def do_mysql_backup(outdir):
    exec_subprocess("mkdir -p {outdir} && rm -rf {outdir}/mysqldump && mkdir -p {outdir}/mysqldump ".format(outdir=outdir))
    check_outdir_space(outdir, MYSQLBACKUP_REQUIRE_SPACE)

    all_export_config = read_export_conf()
    export_config = all_export_config["mysql"]
    common_config = export_config.get("_COMMON_",{})
    databases = export_config["databases"]

    dbs_cmd = '''mysql -s {authStr} -e "show databases" | grep -v Database '''.format(authStr=MysqlAuth)
    all_dbs = exec_subprocess(dbs_cmd)

    _dump_cmd =  '''mysqldump {authStr} --skip_add_locks --skip-lock-tables --column-statistics=0 --verbose --quick --max-allowed-packet=524288000 --databases {db} {ext} {ignore} > {outdir}/mysqldump/{db}.sql '''.replace("{authStr}", MysqlAuth)

    _ignore_cmd =  '''mysqldump {authStr} --skip_add_locks --skip-lock-tables --column-statistics=0 --verbose --quick --databases {db} --no-data --tables {tables} > {outdir}/mysqldump/{db}_ignore-tables.sql '''.replace("{authStr}", MysqlAuth)

    time1 = int(time.time())

    for db in databases:
        db_config = export_config.get(db,{})
        if all_dbs and db not in all_dbs:
            log_warn(db + " not exist, will skip")
        
        ext = db_config.get("ext","")
        ignore_tables = db_config.get("ignore-tables", [])

        ignore = ""
        for _table in ignore_tables:
            ignore = ignore + "--ignore-table={db}.{table} ".format(db=db,table=_table)

        dump_cmd = _dump_cmd.format(db=db,outdir=outdir,ext=ext,ignore=ignore)
        log_info(dump_cmd)

        exec_subprocess(dump_cmd, realtimeoutput=True) 

        if common_config.get('mode', 0) == 1 and len(ignore_tables) > 0:
            tables = " ".join(ignore_tables)
            ignore_cmd = _ignore_cmd.format(db=db,outdir=outdir,tables=tables)
            log_info(ignore_cmd)
            exec_subprocess(ignore_cmd)
    
    time2 = int(time.time())
    print("mysql export cost:" + str(time2-time1) + "s")

    print("now wait to tar backup file")
    nowstr = time.strftime('%Y%m%d%H%M%S',time.localtime(time.time()))
    exec_subprocess("cd {outdir} && tar -czvf mysqlbackup-{nowstr}.tar.gz mysqldump --remove-files".format(nowstr=nowstr,outdir=outdir), realtimeoutput=True)

def do_mongo_restore(mongo_bakfile):
    


    abs_path = os.path.abspath(mongo_bakfile)
    bakdir = os.path.dirname(abs_path)
    filename = os.path.basename(abs_path)
    print(bakdir)

    global done_file_path
    done_file_path = bakdir + "/done_colls"

    tar_cmd = "cd {dir} && tar -zxvf {filename}".format(dir=bakdir,filename=filename)
    exec_subprocess(tar_cmd, realtimeoutput=True)

    bak_version = exec_subprocess("cat {dir}/mongoversion".format(dir=bakdir))

    done_colls = set()
    if os.path.exists(done_file_path):
        done_file = open(done_file_path, "r+")
        done_lines = done_file.readlines()
        for line in done_lines:
            done_colls.add(line.strip())
        print(done_colls)

    all_dbs = ['basic_data','wisteria_assets','wisteria_detect','wisteria_notif','wisteria_scan','wisteria_upload','wisteria_file']
    dbs_str = exec_subprocess("ls {dir}/mongodump/".format(dir=bakdir))
    lsdbs = get_files_from_lscmd(dbs_str)
    dbs = [db for db in lsdbs if db in all_dbs]

    _cmd = 'mongorestore {authStr} --db={db} --drop --convertLegacyIndexes {bsonfile}'.replace('{authStr}',MongoAuth)
    for db in dbs:
        dbdir = bakdir + "/mongodump/" + db
        files = os.listdir(dbdir)
        for bsonfile in files:
            bsonpath = os.path.join(dbdir, bsonfile)
            #print(bsonpath)
            if bsonfile.endswith('metadata.json'):
                continue

            db_coll = db + "." + bsonfile
            if db_coll in done_colls:
                print(db_coll + " already restored, will skip")
                continue

            cur_cmd = _cmd.format(db=db,bsonfile=bsonpath)
            log_debug(cur_cmd)
            restore_cmd_queue.put((db_coll,cur_cmd,))

    # run restore command
    time1 = int(time.time())
    restore_thread_num = 2
    for i in range (restore_thread_num):
        ti = Thread(target=restore_consumer, args=(restore_cmd_queue, str(i),))
        ti.setDaemon(True)
        ti.start()

    for i in range (restore_thread_num):
        restore_cmd_queue.put(("__END__","__END__"))

    restore_cmd_queue.join()

    time2 = int(time.time())
    os.system("echo 'timecost:{cost_time}' >> {done_file}".format(cost_time=str(time2-time1),done_file=done_file_path) )
    print("mongo restore cost:" + str(time2-time1) + "s")


def restore_consumer(restore_queue, num):
    log_info("restore consumer " + num + " start")
    while True:
        db_coll, restore_cmd = restore_queue.get()
        if restore_cmd == "__END__":
            log_info("restore consumer " + num + "  end")
            restore_queue.task_done()
            return

        log_info("restore consumer " + num + " process:" + restore_cmd)
        exec_subprocess(restore_cmd, realtimeoutput=True)
        os.system("echo '{db_coll}' >> {done_file}".format(db_coll=db_coll,done_file=done_file_path) )
        restore_queue.task_done()

def get_files_from_lscmd(ls_result):
    ls_files = []
    for line in ls_result.splitlines():
        tmp_files = line.split()
        for filename in tmp_files:
            if filename and filename != '':
                ls_files.append(filename)
    
    return ls_files

def do_mysql_restore(mysql_bakfile):

    abs_path = os.path.abspath(mysql_bakfile)
    bakdir = os.path.dirname(abs_path)
    filename = os.path.basename(abs_path)
    print(bakdir)

    tar_cmd = "cd {dir} && tar -zxvf {filename}".format(dir=bakdir,filename=filename)
    exec_subprocess(tar_cmd, realtimeoutput=True)

    sql_files_str = exec_subprocess("ls {dir}/mysqldump/*.sql".format(dir=bakdir))
    sql_files = get_files_from_lscmd(sql_files_str)
    print(sql_files)

    _restore_cmd = '''mysql {authAtr} '''.format(authAtr=MysqlAuth)
    restore_cmd = _restore_cmd + "< {sqlfile}"
    restore_ignore_cmd = _restore_cmd + "{db} < {sqlfile}"

    ignore_sql_files = []
    for sql_file in sql_files:
        if "_ignore-tables" in sql_file:
            ignore_sql_files.append(sql_file)
            continue
        else:
            _cmd = restore_cmd.format(sqlfile=sql_file)
        log_debug(_cmd)
        exec_subprocess(_cmd, verbose=True, realtimeoutput=True)

    for sql_file in ignore_sql_files:
        print(sql_file)
        db = os.path.basename(sql_file).split("_ignore-tables")[0]
        _cmd = restore_ignore_cmd.format(db=db, sqlfile=sql_file)
        log_debug(_cmd)
        exec_subprocess(_cmd, verbose=True, realtimeoutput=True)


def clean_agent_monitor_db():
    today = datetime.datetime.now()
    # 计算偏移量
    offset = datetime.timedelta(days=-30)
    # 获取想要的日期的时间
    old_date = (today + offset).strftime('%Y_%m_%d')
    print("old_date:" + old_date)
    agent_monitor_tables = exec_subprocess('''mysql -s {authStr} -D agent_monitor_db -N -e "show tables" '''.format(authStr=MysqlAuth))

    for table in agent_monitor_tables.splitlines():
        print(table)
        if not table.startswith("agent_monitor_"):
            continue

        table_date = table[14:]
        print(table_date)
        if table_date <= old_date:
            log_info("will drop table :" + table)
            exec_subprocess('''mysql -s {authStr} -D agent_monitor_db -N -e "drop table {table}" '''.format(authStr=MysqlAuth,table=table))

def show_help():
    print "=========== Usage Info ============="
    print "python db_backup.py [mongo_backup] [mysql_backup] [mongo_restore] [mysql_restore] [auto] [test_mongo_connection] [test_mysql_connection] [env_config]"

def main():

    

    opts = None
    mongobackup,mysqlbackup,mongorestore,mysqlrestore=False,False,False,False
    envconfig_json = "/envconfig.json"

    test_mongo, test_mysql = False, False

    try:
        opts, args = getopt.getopt(sys.argv[1:], "", 
                                ["help","auto","mongo_backup","mysql_backup","mongo_restore","mysql_restore",
                                "test_mongo_connection","test_mysql_connection","env_config="])
    except getopt.GetoptError:
        print("getopt ERROR")
        show_help()
        sys.exit()

    if len(opts) == 0:
        show_help()
        sys.exit() 

    #print(opts)

    for opt, arg in opts:
        if opt == "--mongo_backup":
            mongobackup = True
        elif opt == "--mysql_backup":
            mysqlbackup = True
        elif opt == "--mongo_restore":
            mongorestore = True
        elif opt == "--mysql_restore":
            mysqlrestore = True
        elif opt == "--env_config":
            envconfig_json = arg
        elif opt == "--help":
            show_help()
            sys.exit(0)
        elif opt == "--test_mongo_connection":
            test_mongo = True
        elif opt == "--test_mysql_connection":
            test_mysql = True
        elif opt == "--auto":
            global manually
            manually=False
            print("auto")
        else:
            show_help()
            sys.exit(1)

    load_config_from_envconfig(envconfig_json)

    if test_mongo:
        testMongoConnection()
        sys.exit(0)
    if test_mysql:
        testMysqlConnection()
        sys.exit(0)

    if mongobackup:
        do_mongo_backup(mongo_outdir)
    if mysqlbackup:
        do_mysql_backup(mysql_outdir)
    if mongorestore:
        mongo_bakfile = exec_subprocess("ls {mongo_outdir}/mongobackup-20*.tar.gz | tail -n 1".format(mongo_outdir=mongo_outdir))
        if not mongo_bakfile.startswith('{mongo_outdir}/mongobackup-'.format(mongo_outdir=mongo_outdir)):
            log_error("can not find mongobackup file to restore") 
        do_mongo_restore(mongo_bakfile)
    if mysqlrestore:
        mysql_bakfile = exec_subprocess("ls {mysql_outdir}/mysqlbackup-20*.tar.gz | tail -n 1".format(mysql_outdir=mysql_outdir))
        if not mysql_bakfile.startswith('{mysql_outdir}/mysqlbackup-'.format(mysql_outdir=mysql_outdir)):
            log_error("can not find mysqlbackup file to restore") 
        do_mysql_restore(mysql_bakfile)

if __name__ == '__main__':

    main()