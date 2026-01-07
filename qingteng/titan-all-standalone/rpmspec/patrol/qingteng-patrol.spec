Name:      titan-patrol-srv
Version:   %{upstream_version}
Release:   %{upstream_release}
Summary:   The %{name} rpm package

Group:     application/webserver
License:   qingteng
URL:       www.qingteng.cn
Prefix:    %{_prefix}

AutoReqProv: no

#BuildRequires:
#Requires:

%define app_name patrol-srv
%define dist_pkg_name patrol-srv
%define install_base /data/app
%define startup_script patrol-srv.jar
%define initd_symlink %{_initrddir}/%{app_name}
%define rc2d_symlink %{_sysconfdir}/rc2.d/S99%{app_name}
%define rc3d_symlink %{_sysconfdir}/rc3.d/S99%{app_name}
%define rc5d_symlink %{_sysconfdir}/rc5.d/S99%{app_name}

%define __os_install_post %{nil}

%description
The %{name} is java server to qingteng

%prep

%pre
mkdir -p /data/install/rule
if [ -f "%{install_base}/titan-patrol-srv/db.sqlite" ]; then
    echo "backup patrol_user start..."
    sqlite3 %{install_base}/titan-patrol-srv/db.sqlite ".dump patrol_user" > %{install_base}/titan-patrol-srv/patrol_user.sql
    echo "backup patrol_user done"
fi

%build

%install
rm -rf %{_builddir}/%{dist_pkg_name}
unzip %{_builddir}/%{dist_pkg_name}.zip -d %{_builddir}/%{dist_pkg_name}

mkdir -p %{buildroot}%{install_base}/titan-patrol-srv
cp -r %{_builddir}/%{dist_pkg_name}/* %{buildroot}%{install_base}/titan-patrol-srv

mkdir -p %{buildroot}%{_initrddir}
ln -s %{install_base}/titan-patrol-srv/%{startup_script} %{buildroot}%{initd_symlink}

mkdir -p %{buildroot}%{_sysconfdir}/rc2.d
ln -s %{initd_symlink} %{buildroot}%{rc2d_symlink}

mkdir -p %{buildroot}%{_sysconfdir}/rc3.d
ln -s %{initd_symlink} %{buildroot}%{rc3d_symlink}

mkdir -p %{buildroot}%{_sysconfdir}/rc5.d
ln -s %{initd_symlink} %{buildroot}%{rc5d_symlink}

mkdir -p %{buildroot}%{_sysconfdir}/rc5.d

%post
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

if [ -f "%{install_base}/titan-patrol-srv/script/titan_system_check.py" ]; then
    if [ -f /data/app/www/titan-web/config_scripts/titan_system_check.py ]; then
        user=$(grep "DEFAULT_SSH_USER = " /data/app/www/titan-web/config_scripts/titan_system_check.py | cut -d '"' -f 2)
        port=$(grep "DEFAULT_SSH_PORT" /data/app/www/titan-web/config_scripts/titan_system_check.py | head -n 1 | cut -d '=' -f 2)
        sed -i "s/DEFAULT_SSH_USER = .*/DEFAULT_SSH_USER = \"$user\"/g" %{install_base}/titan-patrol-srv/script/titan_system_check.py
        sed -i "s/DEFAULT_SSH_PORT = .*/DEFAULT_SSH_PORT = $port/g" %{install_base}/titan-patrol-srv/script/titan_system_check.py
        if [ -f "%{install_base}/titan-patrol-srv/version" ]; then
            ver=$(cat "%{install_base}/titan-patrol-srv/version")
            lowerVersion=`echo "${ver%%_*} v3.4.0" | awk '{if ($1 < $2) print "true"; else print "false"}'`
            if [ "$lowerVersion" = "true" ]; then
                /bin/bash -c "cp -f %{install_base}/titan-patrol-srv/script/titan_system_check.py /data/app/www/titan-web/config_scripts/titan_system_check.py"
            fi
        else
            /bin/bash -c "cp -f %{install_base}/titan-patrol-srv/script/titan_system_check.py /data/app/www/titan-web/config_scripts/titan_system_check.py"
        fi
    fi
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
service %{app_name} restart


%preun
# here 0 means install,1 means upgrade
if [ $1 = 0 ] ; then
    %{initd_symlink} force-stop
fi
if [ -d %{install_base}/titan-patrol-srv/jdk ]; then
    mv %{install_base}/titan-patrol-srv/jdk %{install_base}/titan-patrol-srv/jdk_not_remove
    mkdir %{install_base}/titan-patrol-srv/jdk
fi

%postun
# here 0 means install,1 means upgrade
if [ $1 = 0 ] ; then
    cd %{install_base}/titan-patrol-srv
    rm -rf %{services} %{startup_script}
fi
if [ -d %{install_base}/titan-patrol-srv/jdk_not_remove ]; then
    if [ -d %{install_base}/titan-patrol-srv/jdk ]; then
        rm -fr %{install_base}/titan-patrol-srv/jdk
    fi
    mv %{install_base}/titan-patrol-srv/jdk_not_remove %{install_base}/titan-patrol-srv/jdk
fi

%clean
rm -rf %{_builddir}/%{dist_pkg_name}
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{install_base}/titan-patrol-srv/*
%config(noreplace) %{install_base}/titan-patrol-srv/patrol-srv.conf
%{initd_symlink}
%{rc2d_symlink}
%{rc3d_symlink}
%{rc5d_symlink}

%changelog


