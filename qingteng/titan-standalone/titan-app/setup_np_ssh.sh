#!/bin/bash

SCRIPT="`basename \"$0\"`"

if [ ! $1 ]; then
    echo "usage: $SCRIPT User@RemoteHost | port"
    exit 1
fi

# Default ssh port
PORT=22

if [ $2 ]; then
    PORT=$2
fi

echo "ssh to: $1 $PORT"

# Upload id_rsa.pub to the specified host, wrapped for readability
if [ ! -r $HOME/.ssh/id_rsa.pub ]; then
    ssh-keygen -b 2048 -t rsa
fi

# Make sure auth file exists and chmod to 600
# Copy id_rsa.pub to the remote host
RSA_DATA=$(cat $HOME/.ssh/id_rsa.pub)
ssh $1 -p $PORT "mkdir -p ~/.ssh; \
chmod 755 ~/;\
chmod 700 ~/.ssh;\
touch ~/.ssh/authorized_keys;\
chmod u+rw ~/.ssh/authorized_keys;\
chmod 600 ~/.ssh/authorized_keys;\
if [ \$(cat ~/.ssh/authorized_keys|grep \"$RSA_DATA\" |wc -l) == 0 ];then echo $RSA_DATA | cat - >> ~/.ssh/authorized_keys;fi" 2> /dev/null

# brew install ssh-copy-id for mac os
if [ -f /etc/redhat-release ];then
  if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 7 ];then
  ssh-copy-id -i $HOME/.ssh/id_rsa.pub $1 -p $PORT
  else
  ssh-copy-id -i $HOME/.ssh/id_rsa.pub "$1 -p $PORT"
  fi
else
# if redhat-release not exist use the default ssh-copy-id
ssh-copy-id -i $HOME/.ssh/id_rsa.pub "$1 -p $PORT"
fi

if [ $? -eq 0 ]; then
    echo "Success!"
else
    echo "Faild!"
fi
