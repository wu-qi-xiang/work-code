CREATE USER IF NOT EXISTS 'root'@'%';
CREATE USER IF NOT EXISTS 'root'@'localhost';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';

ALTER USER 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '9pbsoq6hoNhhTzl';
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '9pbsoq6hoNhhTzl';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '9pbsoq6hoNhhTzl';

grant all privileges on *.* to 'root'@'%' with grant option;
grant all privileges on *.* to 'root'@'localhost' with grant option;
grant all privileges on *.* to 'root'@'127.0.0.1' with grant option;
flush privileges;
