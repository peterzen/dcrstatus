# Provisioning on Vultr

Builds a host for the stack in this repo (Debian 13, 2 vCPU / 4 GB, ZFS `/srv` on a block volume).

| File | Purpose |
|------|---------|
| `user-data.yaml.tmpl` | the single cloud-init template: root key-only SSH, unattended-upgrades, ZFS (DKMS), pool `tank` (`ashift=12 lz4 atime=off`) on the block volume mounted at `/srv`, Docker CE started after `zfs-mount`. No secrets. |
| `deploy.sh` | idempotent: firewall group (22/80/443/ICMP; tor ports closed) + block volume + instance, attaches the volume. State in `state-$LABEL.env` (git-ignored). `./deploy.sh render` renders/validates the template offline. |
| `config.env` | parameters (all overridable from the environment). |

Requirements: a Vultr API wrapper (`VULTR=/path/to/wrapper`, called as `$VULTR METHOD /endpoint [json]`), `jq`, `envsubst`, `python3` with PyYAML for `render`.

```bash
cd deploy/vultr
export VULTR=/path/to/vultr-wrapper SSH_AUTHORIZED_KEYS_FILE=~/.ssh/authorized_keys
./deploy.sh                       # ~15 min until cloud-init (ZFS DKMS build) finishes
until ssh root@<ip> test -f /var/lib/is2-bootstrap.done; do sleep 20; done
# then copy the project tree + .env to /root/dcrstatus and restore the database dump (see below)
```

Data is not provisioned by these scripts. To move an existing deployment: copy the project tree and `.env`
to `/root/dcrstatus`, start only `mariadb`, load a dump taken on the old host with
`mariadb-dump --single-transaction --databases kumadb`, then `docker compose up -d`. Point DNS at the new
host; Caddy obtains certificates on its own once the names resolve there.

Notes
- Block storage: `high_perf` (NVMe) is not available in every region (mia: HDD `storage_opt` only, 40 GB min).
- The current production instance predates the defaults here and is labelled `is2-test-atl`; run with `LABEL=is2-test-atl` to manage it.
- Two live hosts running the same Kuma monitor set duplicate checks and notifications; stop the old stack after cutover.
- Vultr Debian 13: never use `write_files` with `defer: true` (it runs after `runcmd`); `cloud-init status` may report a harmless vendor-script error, check services instead.
