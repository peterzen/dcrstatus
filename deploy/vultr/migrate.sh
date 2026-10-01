#!/bin/bash
# Copy app + data from the old host to the new Vultr host. READ-ONLY on the source:
# nothing is stopped, modified or deleted there. Streams via this workstation over ssh.
#   OLD_HOST=root@<old-ip> [SERVER_URL="a, b"] ./migrate.sh <new-ip>
set -euo pipefail
source "$(dirname "$0")/config.env"
NEW="root@${1:?usage: migrate.sh <new-ip>}"
OLD="${OLD_HOST:?set OLD_HOST=root@<old-ip>}"
S="ssh -o BatchMode=yes"

echo "== 0. preflight: /srv must be the ZFS pool; snapshot for rollback"
$S $NEW 'mountpoint -q /srv && [ "$(findmnt -no FSTYPE /srv)" = zfs ] && zfs snapshot tank@pre-migrate-$(date +%s)'

echo "== 1. project tree (compose, caddy, Dockerfiles, .git incl. uncommitted changes)"
$S $OLD 'tar -C /root -cf - dcrstatus' | $S $NEW 'tar -C /root -xf -'
# .env is copied as-is (same SERVER_URL, DB credentials). To serve different names while testing
# before DNS points here, run with SERVER_URL="host1, host2" and the .env is rewritten.
if [[ -n "${SERVER_URL:-}" ]]; then
  $S $NEW "sed -i 's|^SERVER_URL=.*|SERVER_URL=${SERVER_URL}|' /root/dcrstatus/.env && grep ^SERVER_URL /root/dcrstatus/.env"
fi

echo "== 2. small state dirs (tor, uptime-kuma); numeric owners preserved"
for d in tor_data uptime-kuma; do
  $S $OLD "tar -C /srv --numeric-owner -cf - $d" | $S $NEW 'tar -C /srv --numeric-owner -xpf -'
done

echo "== 3. start mariadb (empty, initialised from .env) and load a consistent dump"
$S $NEW 'cd /root/dcrstatus && docker compose up -d mariadb'
$S $NEW 'for i in $(seq 1 60); do [ "$(docker inspect -f {{.State.Health.Status}} mariadb)" = healthy ] && exit 0; sleep 5; done; exit 1'
$S $OLD 'docker exec mariadb sh -c '"'"'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --quick --routines --triggers --events --databases kumadb'"'"' | gzip -1' \
  | $S $NEW 'gunzip | docker exec -i mariadb sh -c '"'"'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" --max-allowed-packet=256M'"'"
echo "== 4. build + start full stack"
$S $NEW 'cd /root/dcrstatus && docker compose build -q && docker compose up -d && sleep 60 && docker ps --format "{{.Names}}\t{{.Status}}"'
echo "== done; run ./verify.sh ${1}"
