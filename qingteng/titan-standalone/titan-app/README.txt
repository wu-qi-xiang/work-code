1 Titan-App

    Titan-app let you install the QINGTENG applications conveniently and quickly,

2. Usage

    - Configuration

        python ip-config.py -n {num}   ------------ set ip
            {num}
                1        -------------------  1 server  (test deploy)
                4        -------------------  4 servers (3.0-lite)
                6        -------------------  6 servers (3.0)
                others   -------------------  customized

    - Install

        titan-app.sh install (v3|v2)   ------------ install app

    - Upgrade (in-version)

        titan-app.sh upgrade (v3|v2)   ------------ upgrade app

    - Upgrade (cross-version)

        titan-app.sh upgrade_v2_to_v3  ------------ upgrade app from 2.x to 3.x

3. Help

    python ip-config.py -h

    titan-app.sh help


Note:

    ip_template.json ------------   configuration files

    ip-config.py     ------------   python script to fill ip_template.json

    titan-app.sh     ------------   tool to install or upgrade

    upgrade-conf.sh  ------------   update basic components' config when upgrade server

    set_np_ssh.sh    ------------   exchange authorized keys

    utils.sh         ------------   utils functions