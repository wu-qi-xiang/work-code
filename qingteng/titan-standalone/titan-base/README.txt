
1 Titan-Base

    Titan-base let you install the basic libs conveniently and quickly,
    which provides basic environments that the QINGTENG Server needed.

2 Roles based
    base            ---------  installed on all server
    java            ---------  installed on Java server
    php             ---------  installed on PHP server
    erlang          ---------  installed on Erlang Server
    mysql_master    ---------  installed on Mysql Server
    mysql_slave     ---------  installed with MondoDB_erlang, redis_erlang
    redis_java      ---------  installed on Redis Server that using port 6381
    redis_php       ---------  installed on Redis Server that using port 6380
    redis_erlang    ---------  installed on Redis Server that using port 6379
    mongo_erlang    ---------  installed on MongoDB Server specified for Erlang
    mongo_java      ---------  installed on MongoDB Server specified for Java

3 service_ip.conf

    Basic libs installed according to this configuration file, the configuration
    content includes 2 columns separated by space, the first column using the role
    that specified at (2 Roles based), the second column corresponding to the IP
    Address that the Role will be installed on.

  - Samples (以下正式部署配置样例， 单台测试部署不用安装 mysql_slave)

    2.0 & Lite).

        erlang        127.0.0.1
        php           127.0.0.2
        mysql_master  127.0.0.3
        mysql_slave   127.0.0.4 (可选)
        redis_php     127.0.0.4
        redis_erlang  127.0.0.4
        mongo_erlang  127.0.0.4


    3.0).

        erlang        127.0.0.1
        php           127.0.0.2
        mysql_master  127.0.0.3
        mysql_slave   127.0.0.4 (可选)
        mongo_erlang  127.0.0.4
        redis_php     127.0.0.4
        redis_erlang  127.0.0.4
        java          127.0.0.5
        zookeeper     127.0.0.5
        kafka         127.0.0.5
        redis_java    127.0.0.6
        mongo_java    127.0.0.6

- titan-base.sh

    titan-base.sh help


