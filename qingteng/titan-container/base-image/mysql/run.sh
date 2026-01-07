#!/bin/bash

set -e

DEFAULTS_EXTRA_FILE="/tmp/extra-conf"
if [ "$1" = 'mysqlrouter' ]; then
    if [[ -z $MYSQL_HOST || -z $MYSQL_PORT || -z $MYSQL_USER || -z $MYSQL_PASSWORD_FILE ]]; then
	    echo "some variable not set. Exiting."
	    exit 1
    fi

    PASSFILE=$(mktemp)
    MYSQL_PASSWORD="$(cat $MYSQL_PASSWORD_FILE)"
    echo "$MYSQL_PASSWORD" > "$PASSFILE"
    echo "$MYSQL_PASSWORD" >> "$PASSFILE"
    
    cat >"$DEFAULTS_EXTRA_FILE" <<EOF
[client]
password="$MYSQL_PASSWORD"
EOF
    echo "[Entrypoint] begin Checking group replication state."
    if ! [[ "$(mysql --defaults-extra-file="$DEFAULTS_EXTRA_FILE" -u "$MYSQL_USER" -h "$MYSQL_HOST" -P "$MYSQL_PORT" -e "show status;" 2> /dev/null)" ]]; then
      echo "[Entrypoint] ERROR: Can not connect to database. Exiting."
      exit 1
    fi

    echo "[Entrypoint] Begin bootstrap use account $MYSQL_USER"
    mysqlrouter --bootstrap "$MYSQL_USER@$MYSQL_HOST:$MYSQL_PORT" --disable-rest --client-ssl-mode PASSTHROUGH --directory /tmp/mysqlrouter --force --account-create=never --account=$MYSQL_USER --user=mysqlrouter < "$PASSFILE" || exit 1

    sed -i -e 's/logging_folder=.*$/logging_folder=/' /tmp/mysqlrouter/mysqlrouter.conf
    echo "[Entrypoint] Starting mysql-router."
    exec "$@" --config /tmp/mysqlrouter/mysqlrouter.conf

    rm -f "$PASSFILE"
    rm -f "$DEFAULTS_EXTRA_FILE"
else
    exec "$@"
fi
