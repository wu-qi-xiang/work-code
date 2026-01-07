#! /usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import absolute_import

import sys
sys.path.insert(0, './site-packages/')

import os
import schedule
import time
import datetime
from db_tool import *

def dbbackup_job():
    setAuto()
    print('dbbackup_job:每天4:00执行一次')
    print('dbbackup_job-startTime:%s' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
    today = datetime.datetime.now()
    offset = datetime.timedelta(days=-7)
    old_date_str = (today + offset).strftime('%Y%m%d')
    today_str = today.strftime('%Y%m%d')

    do_mongo_backup("/data/titan-backup/mongo")
    do_mysql_backup("/data/titan-backup/mysql")

    mongoresult=exec_subprocess('''ls -l /data/titan-backup/mongo/mongobackup-{today_str}*.tar.gz || echo -n mongofailed '''.format(today_str=today_str))
    if "mongofailed" in mongoresult:
        print("{today_str} mongo backup failed".format(today_str=today_str))
        return

    mysqlresult=exec_subprocess('''ls -l /data/titan-backup/mysql/mysqlbackup-{today_str}*.tar.gz || echo -n mysqlfailed  '''.format(today_str=today_str))
    if "mysqlfailed" in mongoresult:
        print("{today_str} mysql backup failed".format(today_str=today_str))
        return

    archive_dir=os.getenv("ARCHIVE_DIR", "/data/titan-backup")
    exec_subprocess('''mkdir -p {archive_dir}/{today_str} && mv /data/titan-backup/mongo/mongobackup-{today_str}*.tar.gz {archive_dir}/{today_str}/ && mv /data/titan-backup/mysql/mysqlbackup-{today_str}*.tar.gz {archive_dir}/{today_str}/ '''.format(archive_dir=archive_dir,today_str=today_str))

    clean_old_bakdir(archive_dir,old_date_str)

    # for k8s, can backup file to glusterfs
    dfs_archive_dir=os.getenv("DFS_ARCHIVE_DIR", "")
    if dfs_archive_dir != "":
        exec_subprocess("cp -rf {archive_dir}/{today_str}/ {dfs_archive_dir}/".format(archive_dir=archive_dir,today_str=today_str,dfs_archive_dir=dfs_archive_dir))
        clean_old_bakdir(dfs_archive_dir,old_date_str)

    print('dbbackup_job-endTime:%s' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
    print('------------------------------------------------------------------------')

def clean_old_bakdir(old_archive_dir, old_date_str):
    oldbackdirs = exec_subprocess('''ls -d {archive_dir}/20[0-9]* '''.format(archive_dir=old_archive_dir))
    if len(oldbackdirs.split()) < 7:
        print(old_archive_dir + " backup dirs < 7, will not clean ")
        return

    for dirpath in oldbackdirs.split():
        print(dirpath)
        if not dirpath.startswith(old_archive_dir):
            continue

        datestr= dirpath.split("/")[-1]
        if not datestr.startswith("20"):
            continue

        if datestr <= old_date_str:
            print("rm -rf " + dirpath)
            exec_subprocess("rm -rf " + dirpath)

def log_clean_job():
    print('log_clean_job:每天4:30执行一次')
    print('log_clean_job-startTime:%s' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
    result = exec_subprocess('''bash -c '\
clean_files=`find /data/titan-logs -mtime +$log_max_age -type f -name *[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].log`; \
echo "will clean files are:"; \
echo ${clean_files[*]}; \
for file in ${clean_files[*]}; do rm -f $file; done ' '''.replace("$log_max_age","30"))
    print(result)
    print('log_clean_job-endTime:%s' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
    print('------------------------------------------------------------------------')


def db_clean_job():
    print('db_clean_job:每天5:04执行一次')
    print('db_clean_job-startTime:%s' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
    clean_agent_monitor_db()
    print('db_clean_job-endTime:%s' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
    print('------------------------------------------------------------------------')


if __name__ == '__main__':
    # 解密数据库密码
    load_config_from_envconfig("/envconfig.json")

    dbbackup_time = os.getenv('dbbackup_time',"04:04")
    logclean_time = os.getenv('logclean_time',"04:30")
    dbclean_time = os.getenv('dbclean_time',"05:04")

    dbbackup_enable = os.getenv('DBBACKUP_ENBALE',"true")
    dbclean_enable = os.getenv('DBCLEAN_ENBALE',"true")
    logclean_enable = os.getenv('LOGCLEAN_ENBALE',"true")

    # 每天4点备份数据库
    if dbbackup_enable == "true":
        schedule.every().day.at(dbbackup_time).do(dbbackup_job)
    # 每天4:30点 清理 日志
    if logclean_enable == "true":
        schedule.every().day.at(logclean_time).do(log_clean_job)
    # 每天5：04点 清理 agent_monitor_db
    if dbclean_enable == "true":
        schedule.every().day.at(dbclean_time).do(db_clean_job)

    while True:
        schedule.run_pending()
        time.sleep(60)