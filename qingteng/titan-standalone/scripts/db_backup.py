#! /usr/bin/python

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

DEFAULT_SSH_USER = "root"
DEFAULT_SSH_PORT = 22

mongoip = "127.0.0.1"
msmongoip = "127.0.0.1"
mysqlip = "127.0.0.1"
MONGO_PWD = "9pbsoq6hoNhhTzl"
MSMONGO_PWD = "9pbsoq6hoNhhTzl"
MYSQL_PWD = "9pbsoq6hoNhhTzl"

MongoAuth = ''' -u {user} -p {passwd} --authenticationDatabase=admin '''.format(user="qingteng", passwd=MONGO_PWD)
MSMongoAuth = ''' -u {user} -p {passwd} --authenticationDatabase=admin '''.format(user="qingteng", passwd=MSMONGO_PWD)
MysqlAuth = ''' -u{user} -p{passwd} '''.format(user="root", passwd=MYSQL_PWD)

ScriptPath = os.path.split(os.path.realpath(sys.argv[0]))[0]

MONGOBACKUP_REQUIRE_SPACE = 10
MSMONGOBACKUP_REQUIRE_SPACE = 10
MYSQLBACKUP_REQUIRE_SPACE = 8

export_cmd_queue = Queue()
console_lock = Semaphore(value=1)

def log_error(msg):
    print('\033[31m' + "ERROR:" + str(msg) + '\033[0m')
    sys.exit(1)

def log_warn(msg):
    console_lock.acquire()
    print('\033[35m' + "WARN:" + str(msg) + '\033[0m')
    console_lock.release()

def log_info(msg):
    console_lock.acquire()
    print('\033[32m' + "INFO:" +str(msg) + "\033[0m")
    console_lock.release()

def log_debug(msg):
    console_lock.acquire()
    print("DEBUG:" +str(msg))
    console_lock.release()

def get_input(default_value, prompt=""):
    v = raw_input(prompt)
    if v == "" or v.strip() == "":
        return default_value
    else:
        return v.strip()

def log_warn_and_confirm(msg):
    print('\033[32m' + str(msg) + "\033[0m")
    v = get_input("Y","Are you sure to continue, default is Y, Enter [Y/N]: ")
    if v == "n" or v == "no" or v == "N" or v == "NO" or v == "No":
        print("Abort, exit." + "\n")
        exit(0)

#refer to https://unix.stackexchange.com/questions/4770/quoting-in-ssh-host-foo-and-ssh-host-sudo-su-user-c-foo-type-constructs
# use single quote, avoid escape.  single quote for Bourne shell evaluation
# Change ' to '\'' and wrap in single quotes.
# If original starts/ends with a single quote, creates useless
# (but harmless) '' at beginning/end of result.
def single_quote(cmd):
    return "'" + cmd.replace("'","'\\''") + "'" 

def ssh_qt_cmd(ip_addr, cmd, force=True):
    # if user is not root, need sudo
    if DEFAULT_SSH_USER != 'root':
        cmd = '''sudo bash -c ''' + single_quote(cmd)
    if ip_addr in ['127.0.0.1', '']:
        return cmd
    
    if force:
        return '''ssh -q -t -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o LogLevel=Error -p {port} {user}@{ip_addr} {cmd} '''.format(port=DEFAULT_SSH_PORT,user=DEFAULT_SSH_USER,ip_addr=ip_addr,cmd=single_quote(cmd))
    else:
        return '''ssh -q -T -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o LogLevel=Error -p {port} {user}@{ip_addr} {cmd} '''.format(port=DEFAULT_SSH_PORT,user=DEFAULT_SSH_USER,ip_addr=ip_addr,cmd=single_quote(cmd))

def exec_ssh_subprocess(ip_addr, cmd, verbose=False, realtimeoutput=False):
    cmd = ssh_qt_cmd(ip_addr, cmd)
    if verbose:
        log_debug("exec_ssh_subprocess:" + cmd )

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
        # remove Pseudo-terminal will not be allocated because stdin is not a terminal.
        if output.startswith("Pseudo-terminal will"):
            return re.sub("^Pseudo-terminal will.*\.", "", output).strip()
        else:
            return output.strip()

def check_outdir_space(ip, outdir, min_space):
    
    _cmd = '''df -Pk {outdir} | tail -n 1 | awk '{print $4}' '''.replace("{outdir}", outdir)

    free_space = exec_ssh_subprocess(ip, _cmd)
    free_space_G = int(free_space)/1024/1024
    if free_space_G < min_space:
        log_error("free_space of {outdir} is not enough, exit".format(outdir=outdir))
    
    log_warn_and_confirm("free_space of {outdir} is {free} G".format(outdir=outdir,free=str(free_space_G)))

    return free_space_G

def read_export_conf():
    export_config = json.load(file(ScriptPath + "/export_config.json"))

    return export_config

def get_db_coll_stats(database,outdir,mongoip,Auth):
    _cmd = '''/usr/local/sbin/mongo --quiet $database $authStr --eval 'db.getCollectionNames().map(function(coll) {stats = db.getCollection(coll).stats(); return { "name":coll,"size":stats.size.valueOf().toString(), "totalSize": (stats.storageSize + stats.totalIndexSize)/1024/1024, "count": stats.count,"avgObjSize": stats.avgObjSize?stats.avgObjSize:-1,"storageSize": stats.storageSize/1024/1024 ,"totalIndexSize": stats.totalIndexSize/1024/1024  }}).sort(function(e1, e2) {return e1.size - e2.size})' '''.replace("$database",database).replace("$authStr",Auth).replace("$outdir",outdir)
    # | tee $outdir/mongo_$database_stat.json

    coll_stats = []

    result = exec_ssh_subprocess(mongoip, _cmd)
    if not result:
        return coll_stats
    
    index = result.find("[")
    coll_stats = json.loads(result[index:])

    return coll_stats

def do_mongo_backup(outdir,MongoIp,MongoName):
    if MongoName == "mongo":
        Mongo_Auth = MongoAuth
        REQUIRE_SPACE = MONGOBACKUP_REQUIRE_SPACE
    else:
        Mongo_Auth = MSMongoAuth
        REQUIRE_SPACE = MSMONGOBACKUP_REQUIRE_SPACE
    
    exec_ssh_subprocess(MongoIp, "mkdir -p {outdir} && rm -rf {outdir}/mongodump && rm -rf {outdir}/mongoexport && mkdir -p {outdir}/mongodump && mkdir -p {outdir}/mongoexport".format(outdir=outdir))
    free_space_G = check_outdir_space(MongoIp, outdir, REQUIRE_SPACE)

    all_export_config = read_export_conf()
    export_config = all_export_config[MongoName]
    common_config = export_config["_COMMON_"]
    databases = export_config["databases"]
    db_coll_stats = {}

    # get version
    version = exec_ssh_subprocess(MongoIp,'''/usr/local/sbin/mongo --version | head -n 1 |cut -d ' ' -f 4 > $outdir/mongoversion '''.replace("$outdir",outdir))

    # prepare command
    for db in databases:
        coll_stats = get_db_coll_stats(db, outdir, MongoIp, Mongo_Auth)
        #log_debug(coll_stats)
        db_exclude_colls = export_config.get(db, {}).get("_EXCLUDE_", [])
        db_coll_stats[db] = [stat for stat in coll_stats if stat['name'] not in db_exclude_colls]

    warn_limits = {}
    warn_exportsize = {}
    export_threshold = 1 * 1024 * 1024 * 1024
    totalExportSize = 0
    for db,coll_stats in db_coll_stats.items(): 
        db_common_config = export_config.get(db, {}).get("_COMMON_", common_config)   
        for stats in coll_stats:
            coll = stats["name"]
            _cmd = Mongo_Auth + " --db={db} --collection={coll}".format(db=db, coll=coll)
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
    
    if MongoIp == "127.0.0.1":
        os.system("cp /tmp/mongostats.json {outdir}".format(outdir=outdir))
    else:
        scp_cmd = "scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -P {0} {1} {2}@{3}:{4}".format(DEFAULT_SSH_PORT, "/tmp/mongostats.json", DEFAULT_SSH_USER, MongoIp, outdir)
        os.system(scp_cmd)

    # print warn, some collections will be discard
    exec_ssh_subprocess(MongoIp,"echo {totalExportSize} > {outdir}/mongo_warn.log".format(outdir=outdir,totalExportSize=totalExportSize))
    if len(warn_limits) > 0:
        for db_coll, limit_info in warn_limits.items():
            count,limit = limit_info
            warn_msg = "{db_coll:<56} count: {count:<10} export: {limit}".format( db_coll=db_coll, count=count, limit=limit)
            log_warn(warn_msg)
            exec_ssh_subprocess(MongoIp,"echo '{warn_msg}' >> {outdir}/mongo_warn.log".format(outdir=outdir,warn_msg=warn_msg))
    
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
            _cmd = Mongo_Auth + " --db={db} --collection={coll}".format(db=db, coll=coll)
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
            
            _cmd = '/usr/local/sbin/' + method + " " + _cmd  
            # _cmd like: mongodump -u qingteng -p yp1riWdR6C9cIiAx --authenticationDatabase=admin  --db=wisteria_assets --collection=kb_info
            if method == "mongodump":
                if real_limit is not None:
                    mongo_find = '''db.$coll.find($query, {"_id":1}).sort({_id:-1}).skip($skip).limit(1) '''.replace('$query', query).replace("$skip", real_limit).replace("$coll",coll)

                    get_limit_cmd = '''/usr/local/sbin/mongo {db} {authStr} --eval='{mongo_cmd}' |grep "_id" '''.format(db=db,authStr=Mongo_Auth,mongo_cmd=mongo_find)

                    limit_id = None
                    limit_id_result = exec_ssh_subprocess(MongoIp, get_limit_cmd)
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

            print(_cmd.strip())
            export_cmd_queue.put(_cmd)

    # run export command
    time1 = int(time.time())
    export_thread_num = 8
    for i in range (export_thread_num):
        ti = Thread(target=export_consumer, args=(export_cmd_queue, str(i), MongoIp,))
        ti.setDaemon(True)
        ti.start()

    for i in range (export_thread_num):
        export_cmd_queue.put("__END__")

    export_cmd_queue.join()

    time2 = int(time.time())
    print("mongo export cost:" + str(time2-time1) + "s")

    print("now wait to tar backup file")
    exec_ssh_subprocess(MongoIp, "cd {outdir} && tar -czvf {MongoName}backup.tar.gz mongodump mongoexport mongoversion mongostats.json mongo_warn.log --remove-files".format(outdir=outdir,MongoName=MongoName), realtimeoutput=True)

def export_consumer(export_queue, num, mongoip):
    log_info("export consumer " + num + " start")
    while True:
        export_cmd = export_queue.get()
        if export_cmd == "__END__":
            log_info("export consumer " + num + "  end")
            export_queue.task_done()
            return

        log_info("export consumer " + num + " process:" + export_cmd)
        exec_ssh_subprocess(mongoip, export_cmd, realtimeoutput=True)
        export_queue.task_done()

# MYSQL
def do_mysql_backup(outdir):
    exec_ssh_subprocess(mysqlip, "mkdir -p {outdir} && rm -rf {outdir}/mysqldump && mkdir -p {outdir}/mysqldump ".format(outdir=outdir))
    check_outdir_space(mysqlip, outdir, MYSQLBACKUP_REQUIRE_SPACE)

    all_export_config = read_export_conf()
    export_config = all_export_config["mysql"]
    databases = export_config["databases"]

    socket_str = exec_ssh_subprocess(mysqlip, '''cat /etc/my.cnf | grep ^socket | head -n 1 | tr -d ' ' ''')

    dbs_cmd = '''/usr/local/sbin/mysql -s {authStr} --{socket_str} -e "show databases" | grep -v Database '''.format(authStr=MysqlAuth,socket_str=socket_str)
    all_dbs = exec_ssh_subprocess(mysqlip, dbs_cmd)

    _dump_cmd =  '''mysqldump {authStr} -h {mysqlip} --skip_add_locks --skip-lock-tables --quick --max-allowed-packet=524288000 --databases {db} {ext} {ignore} > {outdir}/mysqldump/{db}.sql '''.replace("{authStr}", MysqlAuth).replace("{mysqlip}",mysqlip)

    _ignore_cmd =  '''mysqldump {authStr}  -h {mysqlip} --skip_add_locks --skip-lock-tables --quick --databases {db} --no-data --tables {tables} > {outdir}/mysqldump/{db}_ignore-tables.sql '''.replace("{authStr}", MysqlAuth).replace("{mysqlip}",mysqlip)

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

        exec_ssh_subprocess(mysqlip, dump_cmd) 

        if len(ignore_tables) > 0:
            tables = " ".join(ignore_tables)
            ignore_cmd = _ignore_cmd.format(db=db,outdir=outdir,tables=tables)
            log_info(ignore_cmd)
            exec_ssh_subprocess(mysqlip, ignore_cmd)
    
    time2 = int(time.time())
    print("mysql export cost:" + str(time2-time1) + "s")

    print("now wait to tar backup file")
    exec_ssh_subprocess(mysqlip, "cd {outdir} && tar -czvf mysqlbackup.tar.gz mysqldump --remove-files".format(outdir=outdir), realtimeoutput=True)

def do_mongo_restore(mongo_bakfile,MongoIp,MongoName):
    if MongoName == "mongo":
        Mongo_Auth = MongoAuth
    else:
        Mongo_Auth = MSMongoAuth
    
    abs_path = os.path.abspath(mongo_bakfile)
    bakdir = os.path.dirname(abs_path)
    filename = os.path.basename(abs_path)
    print(bakdir)

    tar_cmd = "cd {dir} && tar -zxvf {filename}".format(dir=bakdir,filename=filename)
    exec_ssh_subprocess(MongoIp, tar_cmd, realtimeoutput=True)

    bak_version = exec_ssh_subprocess(MongoIp, "cat {dir}/mongoversion".format(dir=bakdir))
    now_version = exec_ssh_subprocess(MongoIp, '''/usr/local/sbin/mongo --version | head -n 1 |cut -d ' ' -f 4 ''')

    if now_version != 'v4.2.3':
        log_warn_and_confirm("qingteng v3.4.0 system's mongo should be v4.2.3 !!!!")

    restore_cmd = '''/usr/local/sbin/mongorestore {authStr} --dir={dir}/mongodump --drop --convertLegacyIndexes '''.format(authStr=Mongo_Auth,dir=bakdir)
    print(restore_cmd)
    exec_ssh_subprocess(MongoIp, restore_cmd, realtimeoutput=True)

    import_cmd = '''mongoimport --stopOnError --drop {authStr} '''.format(authStr=Mongo_Auth)
    if bak_version < 'v4.2.3':
        import_cmd = import_cmd + " --legacy "
    import_cmd = import_cmd + '--db {db} --collection {coll} --file {coll_file} '
    
    import_colls_str = exec_ssh_subprocess(MongoIp, "ls {dir}/mongoexport/*.json || echo none_export".format(dir=bakdir))
    if import_colls_str and not 'none_export' in import_colls_str:
        import_coll_files = get_files_from_lscmd(import_colls_str)
        print(import_coll_files)

        for coll_file in import_coll_files:
            filename = os.path.basename(coll_file)
            #print(filename)
            file_no_suffix = os.path.splitext(filename)[0]
            db, coll=file_no_suffix.split(".")[0], file_no_suffix.split(".")[1]
            _import_cmd = import_cmd.format(db=db,coll=coll,dir=bakdir,coll_file=coll_file)
            print(_import_cmd)
            exec_ssh_subprocess(MongoIp, _import_cmd, realtimeoutput=True)

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
    bak_dir = os.path.dirname(abs_path)
    filename = os.path.basename(abs_path)
    print(bak_dir)

    tar_cmd = "cd {dir} && tar -zxvf {filename}".format(dir=bak_dir,filename=filename)
    exec_ssh_subprocess(mysqlip, tar_cmd, realtimeoutput=True)

    sql_files_str = exec_ssh_subprocess(mysqlip, "ls {dir}/mysqldump/*.sql".format(dir=bak_dir))
    sql_files = get_files_from_lscmd(sql_files_str)
    print(sql_files)

    socket_str = exec_ssh_subprocess(mysqlip, '''cat /etc/my.cnf | grep ^socket | head -n 1 | tr -d ' ' ''')

    _restore_cmd = '''/usr/local/sbin/mysql {authAtr} --{socket_str} '''.format(authAtr=MysqlAuth,socket_str=socket_str)
    restore_cmd = _restore_cmd + "< {sqlfile}"
    restore_ignore_cmd = _restore_cmd + "{db} < {sqlfile}"

    ignore_sql_files = []
    for sql_file in sql_files:
        if "_ignore-tables" in sql_file:
            ignore_sql_files.append(sql_file)
            continue
        else:
            _cmd = restore_cmd.format(sqlfile=sql_file)
        print(_cmd)
        exec_ssh_subprocess(mysqlip, _cmd, verbose=True)

    for sql_file in ignore_sql_files:
        print(sql_file)
        db = os.path.basename(sql_file).split("_ignore-tables")[0]
        _cmd = restore_ignore_cmd.format(db=db, sqlfile=sql_file)
        print(_cmd)
        exec_ssh_subprocess(mysqlip, _cmd, verbose=True)

def set_mongo_info(ip,passwd):
    global mongoip, MONGO_PWD, MongoAuth
    mongoip = ip
    MONGO_PWD = passwd
    MongoAuth = ''' -u {user} -p {passwd} --authenticationDatabase=admin '''.format(user="qingteng", passwd=MONGO_PWD)

def set_mysql_info(ip,passwd):
    global mysqlip, MYSQL_PWD, MysqlAuth
    mysqlip = ip
    MYSQL_PWD = passwd
    MysqlAuth = ''' -u{user} -p{passwd} '''.format(user="root", passwd=MYSQL_PWD)

def show_help():
    print "=========== Usage Info ============="
    print "python db_backup.py [out] [mongo_out] [mysql_out] [mongo_bakfile] [mysql_bakfile] [bakdir] "

def main(argv):

    mongo_outdir = None
    msmongo_outdir = None
    mysql_outdir = None
    mongo_bakfile = None 
    msmongo_bakfile = None
    mysql_bakfile = None

    backup = None
    restore = None  

    opts = None
    try:
        opts, args = getopt.getopt(argv, "", 
                                ["help","out=","mongo_out=","msmongo_out=",
                                "mysql_out=","mongo_bakfile=","msmongo_bakfile=","mysql_bakfile=",
                                "bakdir="])
    except getopt.GetoptError:
        print("ERROR")
        show_help()
        sys.exit()

    if len(opts) == 0:
        show_help()
        sys.exit() 

    print(opts)

    for opt, arg in opts:
        if opt == "--out":
            mongo_outdir = arg
            mysql_outdir = arg
            msmongo_outdir = arg
            backup = True
        elif opt == "--mongo_out":
            mongo_outdir = arg
            backup = True
        elif opt == "--msmongo_out":
            msmongo_outdir = arg
            backup = True
        elif opt == "--mysql_out":
            mysql_outdir = arg
            backup = True
        elif opt == "--mongo_bakfile":
            mongo_bakfile = arg
            restore = True
        elif opt == "--msmongo_bakfile":
            msmongo_bakfile = arg
            restore = True
        elif opt == "--mysql_bakfile":
            mysql_bakfile = arg
            restore = True
        elif opt == "--bakdir":
            mongo_bakfile = arg + "/mongobackup.tar.gz"
            mysql_bakfile = arg + "/mysqlbackup.tar.gz"
            msmongo_bakfile = arg + "/msmongobackup.tar.gz"
            restore = True
        elif opt == "--help":
            show_help()
            sys.exit(1)
        else:
            show_help()
            sys.exit(1)

    # global MongoAuth,MysqlAuth,MSMongoAuth
    # MongoAuth = MongoAuth.format(user="qingteng", passwd=MONGO_PWD)
    # MSMongoAuth = MongoAuth.format(user="qingteng", passwd=MSMONGO_PWD)
    # MysqlAuth = MysqlAuth.format(user="root", passwd=MYSQL_PWD)

    if backup:
        if mongo_outdir:
            do_mongo_backup(mongo_outdir,mongoip,"mongo")
        
        if msmongo_outdir:
            do_mongo_backup(msmongo_outdir,msmongoip,"msmongo")
        
        if mysql_outdir:
            do_mysql_backup(mysql_outdir)

    elif restore:
        if mongo_bakfile:
            do_mongo_restore(mongo_bakfile,mongoip,"mongo")
            
        if msmongo_bakfile:
            do_mongo_restore(msmongo_bakfile,msmongoip,"msmongo")
        
        if mysql_bakfile:
            do_mysql_restore(mysql_bakfile)
        

if __name__ == '__main__':

    main(sys.argv[1:])