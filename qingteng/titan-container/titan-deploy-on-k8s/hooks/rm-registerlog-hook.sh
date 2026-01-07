#!/usr/bin/env bash

if [[ $1 == "--config" ]] ; then
  cat <<EOF
configVersion: v1
schedule:
- name: deleteRegisterLog
  crontab: "0 */15 * * * *"
  allowFailure: true
EOF
else
  expire_registerlog=`find /logs -mtime +0.5 -name register.log`
  if [[ $expire_registerlog =~ "/logs/register.log" ]]; then
    rm -rf /logs/register.log
  fi
fi
