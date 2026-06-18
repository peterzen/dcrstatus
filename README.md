# Decred status monitoring platform

This repository contains configuration to run an instance of [Uptime Kuma](https://github.com/louislam/uptime-kuma) monitoring the health of applications and services of the Decred network.

Uptime Kuma runs at **v2** with a **MariaDB** backend.

### Prerequisites

 * Docker

### Installation

  1. Clone the repository

  2. Copy `.env.example` to `.env` and set `SERVER_URL`, `CERTBOT_EMAIL`, and the
     `MARIADB_*` credentials. `SERVER_URL` must resolve to this host so Caddy can obtain
     a Let's Encrypt certificate.

  3. Build Docker images:
```bash
docker compose build
```

  4. Bring up the Docker stack:

```bash
docker compose up -d
```

  5. Open Uptime Kuma at the configured URL and create the admin user. Monitors and
     status pages live in the MariaDB database, so a fresh install starts empty — restore
     a database backup (or migrate an existing instance) to populate it. The legacy
     `uptime-kuma-configuration.json` JSON import is deprecated in v2 and does **not**
     restore status pages.
