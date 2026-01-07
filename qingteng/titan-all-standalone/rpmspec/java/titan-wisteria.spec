Name:      titan-wisteria
Version:   %{upstream_version}
Release:   %{upstream_release}
Summary:   The %{name} rpm package

Group:     application/webserver
License:   qingteng
URL:       www.qingteng.cn
Prefix:    %{_prefix}
AutoReqProv: no

%package -n titan-patrol-srv
Summary:        titan-patrol-srv server


%package -n titan-scan-srv
Summary:        titan-scan-srv server

%package -n titan-connect-dh
Summary:        titan-connect-dh server
%package -n titan-connect-sh
Summary:        titan-connect-sh server
%package -n titan-connect-agent
Summary:        titan-connect-agent server
%package -n titan-connect-selector
Summary:        titan-connect-selector server
%package -n titan-java-lib
Summary:        third party libraries for all java service

#BuildRequires:
#Requires:

%define app_name wisteria
%define titan_patrol_srv_app_name patrol-srv
%define titan_scan_srv_app_name scan-srv
%define titan_connect_dh_app_name connect-dh
%define titan_connect_sh_app_name connect-sh
%define titan_connect_agent_app_name connect-agent
%define titan_connect_selector_app_name connect-selector

%define dist_pkg_name titan-wisteria
%define services titan-wisteria titan-gateway titan-user-srv titan-upload-srv titan-detect-srv titan-job-srv
%define install_base /data/app
%define startup_script wisteria-all.sh
%define initd_symlink %{_initrddir}/%{app_name}
%define rc2d_symlink %{_sysconfdir}/rc2.d/S99%{app_name}
%define rc3d_symlink %{_sysconfdir}/rc3.d/S99%{app_name}
%define rc5d_symlink %{_sysconfdir}/rc5.d/S99%{app_name}

%define patrol_srv_initd_symlink %{_initrddir}/%{titan_patrol_srv_app_name}
%define patrol_srv_rc2d_symlink %{_sysconfdir}/rc2.d/S99%{titan_patrol_srv_app_name}
%define patrol_srv_rc3d_symlink %{_sysconfdir}/rc3.d/S99%{titan_patrol_srv_app_name}
%define patrol_srv_rc5d_symlink %{_sysconfdir}/rc5.d/S99%{titan_patrol_srv_app_name}

%define scan_srv_initd_symlink %{_initrddir}/%{titan_scan_srv_app_name}
%define scan_srv_rc2d_symlink %{_sysconfdir}/rc2.d/S99%{titan_scan_srv_app_name}
%define scan_srv_rc3d_symlink %{_sysconfdir}/rc3.d/S99%{titan_scan_srv_app_name}
%define scan_srv_rc5d_symlink %{_sysconfdir}/rc5.d/S99%{titan_scan_srv_app_name}

%define connect_dh_initd_symlink %{_initrddir}/%{titan_connect_dh_app_name}
%define connect_dh_rc2d_symlink %{_sysconfdir}/rc2.d/S99%{titan_connect_dh_app_name}
%define connect_dh_rc3d_symlink %{_sysconfdir}/rc3.d/S99%{titan_connect_dh_app_name}
%define connect_dh_rc5d_symlink %{_sysconfdir}/rc5.d/S99%{titan_connect_dh_app_name}

%define connect_sh_initd_symlink %{_initrddir}/%{titan_connect_sh_app_name}
%define connect_sh_rc2d_symlink %{_sysconfdir}/rc2.d/S99%{titan_connect_sh_app_name}
%define connect_sh_rc3d_symlink %{_sysconfdir}/rc3.d/S99%{titan_connect_sh_app_name}
%define connect_sh_rc5d_symlink %{_sysconfdir}/rc5.d/S99%{titan_connect_sh_app_name}

%define connect_agent_initd_symlink %{_initrddir}/%{titan_connect_agent_app_name}
%define connect_agent_rc2d_symlink %{_sysconfdir}/rc2.d/S99%{titan_connect_agent_app_name}
%define connect_agent_rc3d_symlink %{_sysconfdir}/rc3.d/S99%{titan_connect_agent_app_name}
%define connect_agent_rc5d_symlink %{_sysconfdir}/rc5.d/S99%{titan_connect_agent_app_name}

%define connect_selector_initd_symlink %{_initrddir}/%{titan_connect_selector_app_name}
%define connect_selector_rc2d_symlink %{_sysconfdir}/rc2.d/S99%{titan_connect_selector_app_name}
%define connect_selector_rc3d_symlink %{_sysconfdir}/rc3.d/S99%{titan_connect_selector_app_name}
%define connect_selector_rc5d_symlink %{_sysconfdir}/rc5.d/S99%{titan_connect_selector_app_name}

%define titan_user titan
%define titan_group titan
%define titan_home /home/titan/

%define log_base /data/titan-logs/java

%define __os_install_post %{nil}

%description
The %{name} is java server to qingteng

%description -n titan-patrol-srv
The titan-patrol-srv is java server to qingteng

%description -n titan-scan-srv
The titan-scan-srv is java server to qingteng

%description -n titan-connect-sh
The titan-connect-sh is java server to qingteng
%description -n titan-connect-dh
The titan-connect-dh is java server to qingteng
%description -n titan-connect-agent
The titan-connect-agent is java server to qingteng
%description -n titan-connect-selector
The titan-connect-selector is java server to qingteng
%description -n titan-java-lib
The titan-java-lib contains all the third party libraries for java server


%prep

%pre -n %{name}
getent group %{titan_group} >/dev/null || groupadd -g 2020 -r %{titan_group}
getent passwd %{titan_user} >/dev/null || useradd -u 2020 -r -g %{titan_group} -s /sbin/nologin -d %{titan_home} -m -c "titan user"  %{titan_user}
exit 0

%pre -n titan-scan-srv
getent group %{titan_group} >/dev/null || groupadd -g 2020 -r %{titan_group}
getent passwd %{titan_user} >/dev/null || useradd -u 2020 -r -g %{titan_group} -s /sbin/nologin -d %{titan_home} -m -c "titan user"  %{titan_user}
exit 0

%pre -n titan-connect-sh
getent group %{titan_group} >/dev/null || groupadd -g 2020 -r %{titan_group}
getent passwd %{titan_user} >/dev/null || useradd -u 2020 -r -g %{titan_group} -s /sbin/nologin -d %{titan_home} -m -c "titan user"  %{titan_user}
exit 0

%pre -n titan-connect-dh
getent group %{titan_group} >/dev/null || groupadd -g 2020 -r %{titan_group}
getent passwd %{titan_user} >/dev/null || useradd -u 2020 -r -g %{titan_group} -s /sbin/nologin -d %{titan_home} -m -c "titan user"  %{titan_user}
exit 0

%pre -n titan-connect-agent
getent group %{titan_group} >/dev/null || groupadd -g 2020 -r %{titan_group}
getent passwd %{titan_user} >/dev/null || useradd -u 2020 -r -g %{titan_group} -s /sbin/nologin -d %{titan_home} -m -c "titan user"  %{titan_user}
exit 0

%pre -n titan-connect-selector
getent group %{titan_group} >/dev/null || groupadd -g 2020 -r %{titan_group}
getent passwd %{titan_user} >/dev/null || useradd -u 2020 -r -g %{titan_group} -s /sbin/nologin -d %{titan_home} -m -c "titan user"  %{titan_user}
exit 0

%pre -n titan-java-lib
getent group %{titan_group} >/dev/null || groupadd -g 2020 -r %{titan_group}
getent passwd %{titan_user} >/dev/null || useradd -u 2020 -r -g %{titan_group} -s /sbin/nologin -d %{titan_home} -m -c "titan user"  %{titan_user}
exit 0


%pre -n titan-patrol-srv
if [ -f "%{install_base}/titan-patrol-srv/db.sqlite" ]; then
    echo "backup patrol_user start..."
    sqlite3 %{install_base}/titan-patrol-srv/db.sqlite ".dump patrol_user" > %{install_base}/titan-patrol-srv/patrol_user.sql
    echo "backup patrol_user done"
fi


%build

%install
rm -rf %{_builddir}/%{dist_pkg_name}
unzip %{_builddir}/%{dist_pkg_name}.zip -d %{_builddir}/%{dist_pkg_name}

mkdir -p %{buildroot}%{install_base}
cp -r %{_builddir}/%{dist_pkg_name}/* %{buildroot}%{install_base}

mkdir -p %{buildroot}%{_initrddir}
ln -s %{install_base}/%{startup_script} %{buildroot}%{initd_symlink}
ln -s /data/app/titan-patrol-srv/init.d/patrol-srv %{buildroot}%{patrol_srv_initd_symlink}
ln -s /data/app/titan-scan-srv/init.d/scan-srv %{buildroot}%{scan_srv_initd_symlink}
ln -s /data/app/titan-connect-sh/init.d/connect-sh %{buildroot}%{connect_sh_initd_symlink}
ln -s /data/app/titan-connect-dh/init.d/connect-dh %{buildroot}%{connect_dh_initd_symlink}
ln -s /data/app/titan-connect-agent/init.d/connect-agent %{buildroot}%{connect_agent_initd_symlink}
ln -s /data/app/titan-connect-selector/init.d/connect-selector %{buildroot}%{connect_selector_initd_symlink}

mkdir -p %{buildroot}%{_sysconfdir}/rc2.d
ln -s %{initd_symlink} %{buildroot}%{rc2d_symlink}
ln -s %{patrol_srv_initd_symlink} %{buildroot}%{patrol_srv_rc2d_symlink}
ln -s %{scan_srv_initd_symlink} %{buildroot}%{scan_srv_rc2d_symlink}
ln -s %{connect_sh_initd_symlink} %{buildroot}%{connect_sh_rc2d_symlink}
ln -s %{connect_dh_initd_symlink} %{buildroot}%{connect_dh_rc2d_symlink}
ln -s %{connect_agent_initd_symlink} %{buildroot}%{connect_agent_rc2d_symlink}
ln -s %{connect_selector_initd_symlink} %{buildroot}%{connect_selector_rc2d_symlink}

mkdir -p %{buildroot}%{_sysconfdir}/rc3.d
ln -s %{initd_symlink} %{buildroot}%{rc3d_symlink}
ln -s %{patrol_srv_initd_symlink} %{buildroot}%{patrol_srv_rc3d_symlink}
ln -s %{scan_srv_initd_symlink} %{buildroot}%{scan_srv_rc3d_symlink}
ln -s %{connect_sh_initd_symlink} %{buildroot}%{connect_sh_rc3d_symlink}
ln -s %{connect_dh_initd_symlink} %{buildroot}%{connect_dh_rc3d_symlink}
ln -s %{connect_agent_initd_symlink} %{buildroot}%{connect_agent_rc3d_symlink}
ln -s %{connect_selector_initd_symlink} %{buildroot}%{connect_selector_rc3d_symlink}

mkdir -p %{buildroot}%{_sysconfdir}/rc5.d
ln -s %{initd_symlink} %{buildroot}%{rc5d_symlink}
ln -s %{patrol_srv_initd_symlink} %{buildroot}%{patrol_srv_rc5d_symlink}
ln -s %{scan_srv_initd_symlink} %{buildroot}%{scan_srv_rc5d_symlink}
ln -s %{connect_sh_initd_symlink} %{buildroot}%{connect_sh_rc5d_symlink}
ln -s %{connect_dh_initd_symlink} %{buildroot}%{connect_dh_rc5d_symlink}
ln -s %{connect_agent_initd_symlink} %{buildroot}%{connect_agent_rc5d_symlink}
ln -s %{connect_selector_initd_symlink} %{buildroot}%{connect_selector_rc5d_symlink}


%post -n titan-patrol-srv
# delete installing.json only if both of installing.json and ip.json are exist
if [ -f "/data/install/installing.json" ]; then
    if [ -f "/data/app/www/titan-web/config_scripts/ip.json" ]; then
        mv /data/install/installing.json /data/install/installing.%{upstream_version}_%{upstream_release}.json
    fi
fi
if [ -f "%{install_base}/titan-patrol-srv/sysinfo" ]; then
    chmod +x %{install_base}/titan-patrol-srv/sysinfo
    chown root:root %{install_base}/titan-patrol-srv/sysinfo
    chmod u+s %{install_base}/titan-patrol-srv/sysinfo
fi
echo %{upstream_version}_%{upstream_release} > %{install_base}/titan-patrol-srv/version
if [ -f "%{install_base}/titan-patrol-srv/patrol_user.sql" ]; then
    password=$(more %{install_base}/titan-patrol-srv/patrol_user.sql | grep "VALUES" | sed -r "s/.*','(.*)'.*/\1/")
    if [ -n "$password" ]; then
        echo "restore patrol_user start..."
        if [ ${#password} -ne 32 ]; then
                echo "encrypt password...."
                md5sum=$(echo -n $password | md5sum | awk -F' ' '{print$1}')
                regex="s/$password/$md5sum/g"
                sed -i $regex %{install_base}/titan-patrol-srv/patrol_user.sql
        fi
        sqlite3 %{install_base}/titan-patrol-srv/db.sqlite "drop table patrol_user" && sqlite3 %{install_base}/titan-patrol-srv/db.sqlite < %{install_base}/titan-patrol-srv/patrol_user.sql
        echo "restore patrol_user done"
    fi
else
   %{install_base}/titan-patrol-srv/script/setPwd.sh
fi

%post -n %{name}
mkdir -p %{log_base}/wisteria %{log_base}/gateway %{log_base}/user-srv %{log_base}/upload-srv %{log_base}/detect-srv %{log_base}/job-srv
chown -R %{titan_user}:%{titan_group} %{log_base}/wisteria %{log_base}/gateway %{log_base}/user-srv %{log_base}/upload-srv %{log_base}/detect-srv %{log_base}/job-srv
mkdir -p /data/log
chown -R %{titan_user}:%{titan_group} /data/log
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-config %{install_base}/titan-detect-srv %{install_base}/titan-gateway
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-job-srv %{install_base}/titan-upload-srv %{install_base}/titan-user-srv
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-wisteria %{install_base}/upgradeTool
mkdir -p %{install_base}/license
chown -R %{titan_user}:%{titan_group} %{install_base}/license
mkdir -p /data/titan-upload
chown -R %{titan_user}:%{titan_group} /data/titan-upload
mkdir -p %{log_base}/job-data
chown -R %{titan_user}:%{titan_group} %{log_base}/job-data
if [ -d "%{install_base}/titan-dfs" ]; then
    mkdir -p %{install_base}/titan-dfs/titan-config && mv -f /data/app/titan-config/java.json %{install_base}/titan-dfs/titan-config/ && ln -f -s %{install_base}/titan-dfs/titan-config/java.json /data/app/titan-config/java.json
fi

%post -n titan-scan-srv
mkdir -p %{log_base}/scan-srv
chown -R %{titan_user}:%{titan_group} %{log_base}/scan-srv
mkdir -p %{install_base}/titan-config
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-scan-srv %{install_base}/titan-config

%post -n titan-connect-sh
mkdir -p %{log_base}/connect-sh
chown -R %{titan_user}:%{titan_group} %{log_base}/connect-sh
mkdir -p %{install_base}/titan-config
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-connect-sh %{install_base}/titan-config

%post -n titan-connect-dh
mkdir -p %{log_base}/connect-dh
chown -R %{titan_user}:%{titan_group} %{log_base}/connect-dh
mkdir -p %{install_base}/titan-config
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-connect-dh %{install_base}/titan-config

%post -n titan-connect-agent
mkdir -p %{log_base}/connect-agent
chown -R %{titan_user}:%{titan_group} %{log_base}/connect-agent
mkdir -p %{install_base}/titan-config
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-connect-agent %{install_base}/titan-config
if [ -f "%{install_base}/titan-connect-agent/sysinfo" ]; then
    chmod +x %{install_base}/titan-connect-agent/sysinfo
    chown root:root %{install_base}/titan-connect-agent/sysinfo
    chmod u+s %{install_base}/titan-connect-agent/sysinfo
fi

%post -n titan-connect-selector
mkdir -p %{log_base}/connect-selector
chown -R %{titan_user}:%{titan_group} %{log_base}/connect-selector
mkdir -p %{install_base}/titan-config
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-connect-selector %{install_base}/titan-config

%post -n titan-java-lib
chown -R %{titan_user}:%{titan_group} %{install_base}/titan-java-lib

%preun
%{initd_symlink} force-stop

%postun
cd %{install_base}
rm -rf %{services} %{startup_script}

%clean
rm -rf %{_builddir}/%{dist_pkg_name}
rm -rf %{buildroot}

%files
%defattr(-,%{titan_user},%{titan_group},-)
%{install_base}/titan-wisteria/*
%{install_base}/titan-gateway/*
%{install_base}/titan-user-srv/*
%{install_base}/titan-upload-srv/*
%{install_base}/titan-detect-srv/*
%{install_base}/titan-job-srv/*
%{install_base}/upgradeTool/*
%{install_base}/titan-config/java.json
%{install_base}/titan-config/job.json
%{install_base}/%{startup_script}
%{initd_symlink}
%{rc2d_symlink}
%{rc3d_symlink}
%{rc5d_symlink}

%files -n titan-patrol-srv
%defattr(-,root,root,-)
%{install_base}/titan-patrol-srv/*
%config(noreplace) %{install_base}/titan-patrol-srv/patrol-srv.conf
%{patrol_srv_initd_symlink}
%{patrol_srv_rc2d_symlink}
%{patrol_srv_rc3d_symlink}
%{patrol_srv_rc5d_symlink}

%files -n titan-scan-srv
%defattr(-,%{titan_user},%{titan_group},-)
%{install_base}/titan-scan-srv/*
%{scan_srv_initd_symlink}
%{scan_srv_rc2d_symlink}
%{scan_srv_rc3d_symlink}
%{scan_srv_rc5d_symlink}

%files -n titan-connect-sh
%defattr(-,%{titan_user},%{titan_group},-)
%{install_base}/titan-connect-sh/*
%{install_base}/titan-config/sh.json
%{connect_sh_initd_symlink}
%{connect_sh_rc2d_symlink}
%{connect_sh_rc3d_symlink}
%{connect_sh_rc5d_symlink}

%files -n titan-connect-dh
%defattr(-,%{titan_user},%{titan_group},-)
%{install_base}/titan-connect-dh/*
%{connect_dh_initd_symlink}
%{connect_dh_rc2d_symlink}
%{connect_dh_rc3d_symlink}
%{connect_dh_rc5d_symlink}

%files -n titan-connect-agent
%defattr(-,%{titan_user},%{titan_group},-)
%{install_base}/titan-connect-agent/*
%{connect_agent_initd_symlink}
%{connect_agent_rc2d_symlink}
%{connect_agent_rc3d_symlink}
%{connect_agent_rc5d_symlink}

%files -n titan-connect-selector
%defattr(-,%{titan_user},%{titan_group},-)
%{install_base}/titan-connect-selector/*
%{install_base}/titan-config/selector.json
%{connect_selector_initd_symlink}
%{connect_selector_rc2d_symlink}
%{connect_selector_rc3d_symlink}
%{connect_selector_rc5d_symlink}

%files -n titan-java-lib
%defattr(-,%{titan_user},%{titan_group},-)
%{install_base}/titan-java-lib/*


%changelog

