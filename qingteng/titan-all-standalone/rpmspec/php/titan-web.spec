Name:      titan-web
Version:   %{upstream_version}
Release:   %{upstream_release}
Summary:   The %{name} rpm package

Group:     application/webserver
License:   qingteng
URL:       www.qingteng.cn
Prefix:    %{_prefix}

%define    install_path /data/app/www
%define    script_name supervisor

#BuildRequires:
#Requires:
AutoReqProv: no

%description
The %{name} is php webserver to qingteng.

%prep

%build

%install
#install -p -D -m 0755 $RPM_SOURCE_DIR/%script_name $RPM_BUILD_ROOT%{_initrddir}/%{script_name}
install -d $RPM_BUILD_ROOT%{install_path}
cp -Rf $RPM_BUILD_DIR/* $RPM_BUILD_ROOT%{install_path}

%pre
# delete /data/app/www/titan-web/change/
if [ -d /data/app/www/titan-web/change ]; then
    rm -rf /data/app/www/titan-web/change
fi

%post
#chkconfig --add %script_name
#chkconfig %script_name on

cd /data/app/www/titan-web && mkdir -p logs/log
if ! cat /etc/group|grep -Eq nginx; then
    groupadd nginx
fi
if ! cat /etc/passwd |awk -F \: '{print $1}'|grep -Eq nginx; then
    useradd -g nginx nginx
fi
chown -R nginx:nginx /data/app/www/titan-web/logs/log

[ -d "/data/titan-logs/php/log" ] || mkdir -p /data/titan-logs/php/log
chown -R nginx:nginx /data/titan-logs/php

echo "You must execute script: /data/app/www/titan-web/config_scripts/config.py, finish configure all servers !!!"

%preun

%postun
rm -rf %{install_path}/titan-web 2> /dev/null || :

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,nginx,nginx,-)
%{install_path}/*
#%{_initrddir}/%{script_name}

%changelog
* Sat Feb 18 2017 huaqiao.long@qingteng.cn 2.3.6.1
- New Upstream Release
