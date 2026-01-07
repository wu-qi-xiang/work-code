%define __os_install_post %{nil}
Name:      titan-agent
Version:   %{upstream_version}
Release:   %{upstream_release}
Summary:   The %{name} rpm package

Group:     application/server
License:   qingteng
URL:       www.qingteng.cn
Prefix:    %{_prefix}

%define    install_path /data/app/www

#BuildRequires:
#Requires:
AutoReqProv: no

%description
The %{name} is erlang server to qingteng.

%prep

%build

%install
install -d $RPM_BUILD_ROOT%{install_path}
cp -R $RPM_BUILD_DIR/www/* $RPM_BUILD_ROOT%{install_path}

%pre

%post

%preun

%postun
rm -rf %{install_path}/agent-update 2> /dev/null || :
rm -rf %{install_path}/newshellaudit 2> /dev/null || :
rm -rf %{install_path}/rpm 2> /dev/null || :

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%{install_path}/*

%changelog
* Sat Feb 18 2017 huaqiao.long@qingteng.cn 2.3.6.1
- New Upstream Release
