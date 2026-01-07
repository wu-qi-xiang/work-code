FROM registry.qingteng.cn/titan-container/titan-ansible:2.12.1-20220322

RUN apt-get update && apt install -y --no-install-recommends util-linux bsdmainutils openssh-client sshpass rsync unzip && apt clean && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then \
    	wget "https://dl.k8s.io/release/v1.21.2/bin/linux/arm64/kubectl" -P /usr/bin/ && chmod +x /usr/bin/kubectl; \
        wget "https://jenkins.qingteng.cn/titan-container/base-package/mkcert-v1.4.3-linux-arm64" -O /usr/bin/mkcert && chmod +x /usr/bin/mkcert; \
    else \
		wget "https://dl.k8s.io/release/v1.21.2/bin/linux/amd64/kubectl" -P /usr/bin/ && chmod +x /usr/bin/kubectl; \
        wget "https://jenkins.qingteng.cn/titan-container/base-package/mkcert-v1.4.3-linux-amd64" -O /usr/bin/mkcert && chmod +x /usr/bin/mkcert; \
    fi
RUN pip3 install kubernetes jmespath -i https://mirrors.aliyun.com/pypi/simple/


RUN apt-get update && apt install -y --no-install-recommends jq tini && apt clean && rm -rf /var/lib/apt/lists/*

COPY --from=registry.qingteng.cn/titan-container/shell-operator:v1.0.8 /shell-operator /shell-operator
COPY --from=registry.qingteng.cn/titan-container/shell-operator:v1.0.8 /frameworks/shell /frameworks/shell
COPY --from=registry.qingteng.cn/titan-container/shell-operator:v1.0.8 /shell_lib.sh /
ENV SHELL_OPERATOR_HOOKS_DIR /data/hooks
ENV LOG_TYPE text

WORKDIR /data
COPY ./requirements.yml /data/
RUN ansible-galaxy collection install -r requirements.yml
COPY ./ /data/
RUN rm -rf /data/deploy Dockerfile* live.yml tail_live.yml build.sh 
ENV PATH /data/scripts:$PATH 
CMD /bin/bash