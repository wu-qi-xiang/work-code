FROM registry.qingteng.cn/titan-container/titan-mongo:4.4.6-20220318

RUN apt-get update; \
	apt-get install -y --no-install-recommends tzdata curl wget mysql-client python2.7 && apt clean \
	&& rm -f /usr/bin/myisam_ftdump /usr/bin/mysqlcheck /usr/bin/mysqlshow /usr/bin/mysqlslap \
    && wget https://jenkins.qingteng.cn/titan-container/base-package/get-pip.py && python2.7 get-pip.py --no-cache-dir && rm get-pip.py \
    && ln -s /usr/bin/python2.7 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/* \
    && pip --version;\
	  find /usr/lib/python2.7 -depth \( -type f -name '*.pyc' -o -name '*.pyo' \) -exec rm -rf '{}' +; \
	  find /usr/local/lib -depth \( -type f -name '*.pyc' -o -name '*.pyo' \) -exec rm -rf '{}' +; 

RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" >  /etc/timezone
COPY ./* /

CMD ["python","/schedule.py"]