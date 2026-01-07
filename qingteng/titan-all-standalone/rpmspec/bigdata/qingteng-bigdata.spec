Name:	          qingteng-bigdata	
Version:          %{upstream_version}
Release:	  %{upstream_release}
Summary:	  qingteng-bigdata

Vendor:           qingteng, Inc.
Packager:         jiang.wu <jiang.wu@qingteng.cn>
Group:		  bigdata
License:	  qingteng
URL:		  https://github.com/antirez/redis/archive/3.0.7.tar.gz
Source0:          %{name}-%{version}.tar.gz	
Source1:          qingteng-consumer
Source2:          qingteng-viewer
BuildRoot:	  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:	  gcc gcc-c++
Requires(pre):    shadow-utils, bigdata-python, nginx, librdkafka-devel
Requires(post):   chkconfig
Requires(preun):  chkconfig, initscripts
Requires(postun): initscripts

%description
qingteng-bigdata

%prep
#%%setup -q


%build
#make %{?_smp_mflags}


%install
rm -rf %{buildroot}
%{__install} -p -d -m 0755  %{buildroot}/data/titan-logs/bigdata/qt_consumer/
%{__install} -p -d -m 0755  %{buildroot}/data/titan-logs/bigdata/qt_viewer/
%{__install} -p -d -m 0755  %{buildroot}/data/consumer
%{__install} -p -d -m 0755  %{buildroot}/data/consumer/tmp
%{__install} -p -d -m 0755  %{buildroot}/data/consumer/work
%{__install} -p -d -m 0755  %{buildroot}/data/consumer/failed_data
%{__install} -p -d -m 0755  %{buildroot}/usr/local/qingteng/
%{__install} -p -d -m 0755  %{buildroot}/var/log/bigdata
%{__install} -p -d -m 0755  %{buildroot}/var/run/bigdata
/bin/cp -rfp $RPM_BUILD_DIR/* %{buildroot}/usr/local/qingteng/

%{__install} -p -D -m 0755  %{SOURCE1} %{buildroot}/etc/init.d/qingteng-consumer 
%{__install} -p -D -m 0755  %{SOURCE2} %{buildroot}/etc/init.d/qingteng-viewer


%clean
rm -rf %{buildroot}

%pre
if [ $1 == 1 ]; then
   id bigdata &>/dev/null
   if [ $? -ne 0 ];then
      useradd -r -M bigdata -s /sbin/nologin -c "bigdata Server"
   fi
fi

%post
if [ $1 == 1 ]; then
   bash /usr/local/qingteng/bigdata/bin/create_template.sh
   bash /usr/local/qingteng/bigdata/bin/create_ilm.sh
   if [ -z `grep -o 'vm.max_map_count=655360' /etc/sysctl.conf` ];then
    sed -i '$a\vm.max_map_count=655360' /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
   fi

   ln -sv /lib64/libpcre.so.0 /lib64/libpcre.so.1 >/dev/null 2>&1
   sed -i '/^*/d' /etc/security/limits.d/*.conf
   if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 7 ];then
     sed -i '38,57d' /etc/nginx/nginx.conf
   fi
   /bin/cp -rfp /usr/local/qingteng/bigdata/other/99-qingteng.conf   /etc/security/limits.d/99-qingteng.conf
   /bin/cp -rfp /usr/local/qingteng/bigdata/other/default.conf /etc/nginx/conf.d/default.conf 
   /bin/cp -rfp  /usr/local/qingteng/bigdata/other/root /var/spool/cron/root 
   if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 6 ];then
     service crond restart
   else
     systemctl restart crond
   fi
   /sbin/chkconfig --add qingteng-consumer >/dev/null 2>&1
   /sbin/chkconfig --add qingteng-viewer >/dev/null 2>&1
   /sbin/chkconfig qingteng-consumer off  >/dev/null 2>&1
   /sbin/chkconfig qingteng-viewer off  >/dev/null 2>&1
fi
if [ $1 == 2 ]; then
   bash /usr/local/qingteng/bigdata/bin/create_template.sh
   bash /usr/local/qingteng/bigdata/bin/create_ilm.sh
   /bin/cp -rfp  /usr/local/qingteng/bigdata/other/root /var/spool/cron/root
   if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 6 ];then
     service crond restart
   else
     systemctl restart crond
   fi
fi


%preun
if [ $1 == 0 ]; then 
   /sbin/service qingteng-consumer  stop >/dev/null 2>&1
   /sbin/service qingteng-viewer stop >/dev/null 2>&1
   /sbin/chkconfig --del qingteng-consumer >/dev/null 2>&1
   /sbin/chkconfig --del qingteng-viewer  >/dev/null 2>&1
fi


%files
%defattr(-,bigdata,bigdata,-)
/data/consumer
/data/titan-logs/bigdata
/usr/local/qingteng/*
/var/log/bigdata
/var/run/bigdata
%attr(0744,root,root) /etc/init.d/qingteng-consumer
%attr(0744,root,root) /etc/init.d/qingteng-viewer

%changelog
* Fri Mar 30 2018 qingteng.cn <jiang.wu@qingteng.cn> - 1.0.1-1
- Initial version
