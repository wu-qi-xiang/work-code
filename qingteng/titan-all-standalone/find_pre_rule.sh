#!/bin/bash

if [[ $# -lt 3 ]]; then
    echo "Usage $0 <pre_rule dir> <company> <version>"
fi

dir=$1
company=$2
version=$3

ls -r ${dir} | grep qingteng-rules-${company}-${version} | head -n 1
