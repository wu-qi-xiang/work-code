#!/bin/bash
# ------------------------------------------------------------------------------
# @author:  Jitang Hu
# @copyright jitang.hu@qingteng.cn
# @doc:     Auto rsync_agent version for test
#-------------------------------------------------------------------------------

AGENT_BUILD_SSH_URL=qingteng@172.16.6.187
shell_audit_path="dev_1.5.9_20211125"

ssh -p 22 -t $AGENT_BUILD_SSH_URL -oStrictHostKeyChecking=no "[ -d /data/app/www/agent-update/publish/release/linux/x86_64/$2 ]"
if [ $? = 0 ]; then
    ver=$(echo $2 | sed -E "s/(v.*)\/.*/\1/g")

    rsync -rv $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/publish/release/linux/x86_64/$2/* agent_files/www/agent-update/$ver
    # remove unused files
    rm -f agent_files/www/agent-update/$ver/App_Linux_All*.tar.gz
    rm -f agent_files/www/agent-update/$ver/App_Linux*.zip
    rm -f agent_files/www/agent-update/$ver/titan-agent-*.tar.gz

else
    echo "Not found linux version: $2 !!!"
    exit 1
fi

ssh -p 22 -t $AGENT_BUILD_SSH_URL -oStrictHostKeyChecking=no "[ -d /data/app/www/agent-update/publish/release/windows/x86_64/$3 ]"
if [ $? = 0 ]; then
    ver=$(echo $3 | sed -E "s/(v.*)\/.*/\1/g")
    rsync -rv $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/publish/release/windows/x86_64/$3/* agent_files/www/agent-update/$ver-win64
    # remove unused files
    rm -f agent_files/www/agent-update/$3/titan-agent-*.tar.gz
else
    echo "Not found windows version: $3 !!!"
    exit 1
fi

if [[ -n "$4" ]]; then
    if [[ -n $7 ]];then
        ssh -p 22 -t $AGENT_BUILD_SSH_URL -oStrictHostKeyChecking=no "[ -d /data/app/www/agent-update/publish/release/aix/ppc64/$4 ]"
        if [ $? = 0 ]; then
            ver=$(echo $4 | sed -E "s/(v.*)\/.*/\1/g")
            rsync -rv $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/publish/release/aix/ppc64/$4/* agent_files/www/agent-update/$ver-aix
        else
            echo "Not found aix version: $4 !!!"
            exit 1
        fi    
    else
        ssh -p 22 -t $AGENT_BUILD_SSH_URL -oStrictHostKeyChecking=no "[ -d /data/app/www/agent-update/publish/release/linux/$4 ]"
        if [ $? = 0 ]; then
            ver=$(echo $4 | sed -E "s/aarch64\/(v.*)\/.*/\1/g")
            rsync -rv $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/publish/release/linux/$4/* agent_files/www/agent-update/$ver-aarch64
        else
            echo "Not found arm aarch64 version: $4 !!!"
            exit 1
        fi
    fi
fi

if [[ -n "$5" ]]; then
    ssh -p 22 -t $AGENT_BUILD_SSH_URL -oStrictHostKeyChecking=no "[ -d /data/app/www/agent-update/publish/release/solaris/x86_64/$5 ]"
    if [ $? = 0 ]; then
        ver=$(echo $5 | sed -E "s/(v.*)\/.*/\1/g")
        rsync -rv $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/publish/release/solaris/x86_64/$5/* agent_files/www/agent-update/$ver-solaris-x86

        if [[ -n "$6" ]]; then
            ssh -p 22 -t $AGENT_BUILD_SSH_URL -oStrictHostKeyChecking=no "[ -d /data/app/www/agent-update/publish/release/solaris/sparc64/$6 ]"
            if [ $? = 0 ]; then
                ver=$(echo $6 | sed -E "s/(v.*)\/.*/\1/g")
                rsync -rv $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/publish/release/solaris/sparc64/$6/* agent_files/www/agent-update/$ver-solaris-x86
            else
                echo "Not found solaris sparc  version: $6 !!!"
                exit 1
            fi
        fi
    else
        echo "Not found solaris  x86  version: $5 !!!"
        exit 1
    fi
fi

if [[ -n "$7" ]]; then
    ssh -p 22 -t $AGENT_BUILD_SSH_URL -oStrictHostKeyChecking=no "[ -d /data/app/www/agent-update/publish/release/linux/$7 ]"
    if [ $? = 0 ]; then
        ver=$(echo $7 | sed -E "s/aarch64\/(v.*)\/.*/\1/g")
        rsync -rv $AGENT_BUILD_SSH_URL:/data/app/www/agent-update/publish/release/linux/$7/* agent_files/www/agent-update/$ver-aarch64
    else
        echo "Not found arm aarch64 version: $7 !!!"
        exit 1
    fi
fi
