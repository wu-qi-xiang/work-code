# Build a Kubernetes cluster using k3s via Ansible

Author: <leilei.qingteng.cn>

## K3s Ansible Playbook

Build a Kubernetes cluster using Ansible with k3s. The goal is easily install a Kubernetes cluster on machines running:

- [X] Debian
- [X] Ubuntu
- [X] CentOS

on processor architecture:

- [X] x64
- [X] arm64

## System requirements

Deployment environment must have Ansible 2.4.0+
Master and nodes must have passwordless SSH access

## 使用Ansible部署

## Usage

```bash

cd titan-install-docker

```
##修改hosts.ini文件
参考如下
```bash
[master]
192.16.35.12

[node]
192.16.35.[10:11]

[k3s_cluster:children]
master
node
```

Use ansible container to deploy k3s

```bash
bash init_docker.sh all
```

## Kubeconfig

To get access to your **Kubernetes** cluster just

```bash
scp debian@master_ip:~/.kube/config ~/.kube/config
```

## cmd and CLI
```bash
#进入delpoy容器

docker-ansible-cli

#执行命令

docker-ansible-cmd echo ok
```