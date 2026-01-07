FROM centos:centos7

MAINTAINER liangyong

LABEL architecture="x86_64" \
      name="gluster/glusterfs-client" \
      version="6.0"

ENV container docker

RUN yum -y install wget nfs-utils attr iputils iproute &&\
    yum install -y glusterfs-fuse &&\
    yum clean all

# Directory for coredumps. Note,kernel.core_pattern must be configured as such
RUN mkdir -p /var/log/core

CMD ["/bin/bash"]