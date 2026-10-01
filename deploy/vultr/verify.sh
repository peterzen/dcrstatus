#!/bin/bash
# Compare kumadb row counts old vs new (heartbeat may lag: source keeps writing). ./verify.sh <new-ip>
source "$(dirname "$0")/config.env"; S="ssh -o BatchMode=yes"
cnt='for t in $(mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -e "show tables" kumadb); do echo "$t $(mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -e "select count(*) from \`$t\`" kumadb)"; done'
f() { grep -vE "^(heartbeat|stat_minutely|stat_hourly|stat_daily) "; }
diff <($S "${OLD_HOST:?set OLD_HOST=root@<old-ip>}" "docker exec mariadb sh -c '$cnt'" | f) <($S "root@${1:?new ip}" "docker exec mariadb sh -c '$cnt'" | f) && echo "ALL STATIC TABLES IDENTICAL (heartbeat/stat_* excluded: source keeps writing)"
