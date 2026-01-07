#!/bin/bash

# copy and run this script to the root of the repository directory containing files
# this script attempts to exclude uploading itself explicitly so the script name is important
# Get command line params
while getopts ":r:u:p:e:" opt; do
        case $opt in
                r) REPO_URL="$OPTARG"
                ;;
                u) USERNAME="$OPTARG"
                ;;
                p) PASSWORD="$OPTARG"
                ;;
                e) REPO_Release="$OPTARG"
                ;;
        esac
done

#echo ${REPO_URL} ${USERNAME} ${PASSWORD} ${REPO_Release}
find . -type f -not -path './yumimport\.sh*' -not -path '*/\.*' -not -path './repodata*' | sed "s|^\./||" | xargs -I '{}' curl -u "$USERNAME:$PASSWORD" -X PUT -v -T {} ${REPO_URL}/qingteng-${REPO_Release}/{} ;

