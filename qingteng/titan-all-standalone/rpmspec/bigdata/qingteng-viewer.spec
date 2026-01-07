Name:	          qingteng-viewer	
Version:          %{upstream_version}
Release:	  %{upstream_release}
Summary:	  qingteng-viewer

Vendor:           qingteng, Inc.
Packager:         jiang.wu <jiang.wu@qingteng.cn>
Group:		  bigdata
License:	  qingteng
URL:		  https://github.com/antirez/redis/archive/3.0.7.tar.gz
Source0:          %{name}-%{version}.tar.gz	
Source1:          qingteng-viewer
BuildRoot:	  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:	  gcc gcc-c++
Requires(pre):    shadow-utils, bigdata-python, nginx
Requires(post):   chkconfig
Requires(preun):  chkconfig, initscripts
Requires(postun): initscripts

%description
qingteng-viewer

%prep
#%%setup -q


%build
#make %{?_smp_mflags}


%install
rm -rf %{buildroot}
%{__install} -p -d -m 0755  %{buildroot}/data/titan-logs/bigdata/qt_viewer/
%{__install} -p -d -m 0755  %{buildroot}/usr/local/qingteng/bigdata
/bin/cp -rfp $RPM_BUILD_DIR/* %{buildroot}/usr/local/qingteng/bigdata


%{__install} -p -D -m 0755  %{SOURCE1} %{buildroot}/etc/init.d/qingteng-viewer


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
   if [ -z `grep -o 'vm.max_map_count=655360' /etc/sysctl.conf` ];then
    sed -i '$a\vm.max_map_count=655360' /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
   fi

   ln -sv /lib64/libpcre.so.0 /lib64/libpcre.so.1 >/dev/null 2>&1
   sed -i '/^*/d' /etc/security/limits.d/*.conf
   if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 7 ];then
     if [ "`cat /etc/nginx/nginx.conf |wc -l`" != "70" ];then 
        sed -i '38,57d' /etc/nginx/nginx.conf
     fi
   fi
   /bin/cp -rfp /usr/local/qingteng/bigdata/other/99-qingteng.conf   /etc/security/limits.d/99-qingteng.conf
   /bin/cp -rfp /usr/local/qingteng/bigdata/other/default.conf /etc/nginx/conf.d/default.conf 
   /bin/cp -rfp  /usr/local/qingteng/bigdata/other/root /var/spool/cron/root 
   if [ `cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'` == 6 ];then
     service crond restart
   else
     systemctl restart crond
   fi
   /sbin/chkconfig --add qingteng-viewer >/dev/null 2>&1
   /sbin/chkconfig qingteng-viewer on  >/dev/null 2>&1
fi


%preun
if [ $1 == 0 ]; then 
   /sbin/service qingteng-viewer stop >/dev/null 2>&1
   /sbin/chkconfig --del qingteng-viewer  >/dev/null 2>&1
fi


%files
%defattr(-,bigdata,bigdata,-)
/data/titan-logs/bigdata
/usr/local/qingteng/*
%attr(0744,root,root) /etc/init.d/qingteng-viewer

%changelog
* Fri Mar 30 2018 qingteng.cn <jiang.wu@qingteng.cn> - 1.0.1-1
- Initial version
