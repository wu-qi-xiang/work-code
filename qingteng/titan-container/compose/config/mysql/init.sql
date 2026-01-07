SET PASSWORD FOR 'root'@'localhost' = PASSWORD('{{readSecret "/run/secrets/mysql_password"}}');
grant all privileges on *.* to 'root'@'%' identified by '{{readSecret "/run/secrets/mysql_password"}}' with grant option;
grant all privileges on *.* to 'root'@'localhost' identified by '{{readSecret "/run/secrets/mysql_password"}}' with grant option;
grant all privileges on *.* to 'root'@'127.0.0.1' identified by '{{readSecret "/run/secrets/mysql_password"}}' with grant option;