#!/bin/bash
# Idempotent Vultr provisioning: firewall group + block volume + instance (+ attach); state in state-$LABEL.env.
# See config.env for parameters. Needs: curl-based Vultr wrapper ($VULTR), jq, envsubst.
#   SSH_AUTHORIZED_KEYS_FILE=~/.ssh/authorized_keys ./deploy.sh
#   ./deploy.sh render        render user-data to stdout and syntax-check it; no API calls
set -euo pipefail
cd "$(dirname "$0")"
source config.env
VULTR=${VULTR:-vultr}
STATE="state-$LABEL.env"

render() { # $1 = block serial
  [[ -r "${SSH_AUTHORIZED_KEYS_FILE:-}" ]] || { echo "set SSH_AUTHORIZED_KEYS_FILE to a file of public keys" >&2; exit 1; }
  local keys; keys=$(grep -E '^(ssh-|ecdsa-|sk-)' "$SSH_AUTHORIZED_KEYS_FILE" | sed 's/^/      - /' || true)
  [[ -n "$keys" ]] || { echo "no public keys found in $SSH_AUTHORIZED_KEYS_FILE (root would be unreachable)" >&2; exit 1; }
  SSH_AUTHORIZED_KEYS="$keys" \
  SHORT="${FQDN%%.*}" BLOCK_SERIAL="$1" FQDN="$FQDN" \
    envsubst '${FQDN} ${SHORT} ${BLOCK_SERIAL} ${SSH_AUTHORIZED_KEYS}' < user-data.yaml.tmpl
}
if [[ "${1:-}" == render ]]; then
  out=$(render "${LABEL}-serial"); printf '%s
' "$out"
  python3 -c 'import sys,yaml; yaml.safe_load(sys.stdin)' <<<"$out" && echo "# yaml ok" >&2
  exit 0
fi
api() { local out; out=$("$VULTR" "$@"); if jq -e '.error? // empty' >/dev/null 2>&1 <<<"$out"; then echo "API error: $out" >&2; exit 1; fi; printf '%s' "$out"; }

# --- firewall group ------------------------------------------------------------
FW_ID=$(api GET /firewalls | jq -r --arg d "$LABEL" '.firewall_groups[]|select(.description==$d)|.id' | head -1)
if [[ -z "$FW_ID" ]]; then
  FW_ID=$(api POST /firewalls "{\"description\":\"$LABEL\"}" | jq -r .firewall_group.id)
  echo "created firewall group $FW_ID"
  rule() { api POST "/firewalls/$FW_ID/rules" "{\"ip_type\":\"$1\",\"protocol\":\"$2\",\"port\":\"$3\",\"subnet\":\"$4\",\"subnet_size\":0,\"notes\":\"$5\"}" >/dev/null; sleep 1; }
  for t in "v4 0.0.0.0" "v6 ::"; do set -- $t
    rule "$1" tcp 22  "$2" ssh
    rule "$1" tcp 80  "$2" http-acme
    rule "$1" tcp 443 "$2" https
    rule "$1" icmp "" "$2" icmp
  done   # 9050/9051 (tor) deliberately NOT opened
fi

# --- block volume (becomes ZFS pool "tank" -> /srv) -----------------------------------
read -r BLOCK_ID BLOCK_MOUNT < <(api GET /blocks | jq -r --arg l "$LABEL-srv" '.blocks[]|select(.label==$l)|"\(.id) \(.mount_id)"' | head -1) || true
if [[ -z "${BLOCK_ID:-}" ]]; then
  read -r BLOCK_ID BLOCK_MOUNT < <(api POST /blocks "$(jq -nc --arg r "$REGION" --arg l "$LABEL-srv" --arg t "$BLOCK_TYPE" --argjson s "$BLOCK_GB" \
    '{region:$r,size_gb:$s,label:$l,block_type:$t}')" | jq -r '.block|"\(.id) \(.mount_id)"')
  echo "created block volume $BLOCK_ID ($BLOCK_TYPE ${BLOCK_GB}GB, serial $BLOCK_MOUNT)"
fi

# --- render user-data ----------------------------------------------------------------
render "$BLOCK_MOUNT" > "user-data-$LABEL.yaml"

# --- instance ------------------------------------------------------------------------
INSTANCE_ID=$(api GET /instances | jq -r --arg l "$LABEL" '.instances[]|select(.label==$l)|.id' | head -1)
if [[ -z "$INSTANCE_ID" ]]; then
  body=$(jq -nc --arg r "$REGION" --arg p "$PLAN" --argjson os "$OS_ID" --arg l "$LABEL" --arg h "$FQDN" \
    --arg fw "$FW_ID" --arg ud "$(base64 -w0 "user-data-$LABEL.yaml")" \
    '{region:$r,plan:$p,os_id:$os,label:$l,hostname:$h,enable_ipv6:true,backups:"disabled",firewall_group_id:$fw,user_data:$ud,tags:["is-decred"]}')
  INSTANCE_ID=$(api POST /instances "$body" | jq -r .instance.id)
  echo "created instance $INSTANCE_ID"
fi
umask 077
printf 'FW_ID=%s\nINSTANCE_ID=%s\nBLOCK_ID=%s\nBLOCK_SERIAL=%s\n' "$FW_ID" "$INSTANCE_ID" "$BLOCK_ID" "$BLOCK_MOUNT" > "$STATE"

# --- attach volume once the instance is up (bootstrap waits for it) -------------------
for i in $(seq 1 60); do
  [[ "$("$VULTR" GET "/instances/$INSTANCE_ID" 2>/dev/null | jq -r '.instance.status+" "+.instance.power_status' 2>/dev/null)" == "active running" ]] && break; sleep 10
done
att=$("$VULTR" GET "/blocks/$BLOCK_ID" | jq -r '.block.attached_to_instance')
[[ "$att" == "$INSTANCE_ID" ]] || { sleep 5; api POST "/blocks/$BLOCK_ID/attach" "{\"instance_id\":\"$INSTANCE_ID\",\"live\":true}" >/dev/null; echo "attached volume"; }
api GET "/instances/$INSTANCE_ID" | jq -c '.instance|{id:.id,label:.label,region:.region,plan:.plan,status:.status,ip:.main_ip,v6:.v6_main_ip}'
