#!/bin/bash
liunx_machine=$(uname -m)
REGISTRY_IP=$1
export CAROOT=/data/registry/certs
if [ $liunx_machine == "aarch64" ];then
    chmod +x mkcert-v1.4.3-linux-arm64 && ./mkcert-v1.4.3-linux-arm64 -cert-file $CAROOT/registry.pem -key-file $CAROOT/registry.key localhost 127.0.0.1 ${REGISTRY_IP}
elif [ $liunx_machine == "x86_64" ];then
    chmod +x mkcert-v1.4.3-linux-amd64 && ./mkcert-v1.4.3-linux-amd64 -cert-file $CAROOT/registry.pem -key-file $CAROOT/registry.key localhost 127.0.0.1 ${REGISTRY_IP}
else
    echo "Machine architecture does not match"
    exit 1
fi
