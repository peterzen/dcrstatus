# Decred status monitoring platform

This repository contains configuration to run an instance of [Uptime Kuma](https://github.com/louislam/uptime-kuma) monitoring the health of applications and services of the Decred network.

### Prerequisites

 * Docker

### Installation

  1. Clone the repository

  2. Change the `SERVER_URL` variable to the domain name the server will run on

  3. Generate the server key and certificate:

```bash
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes
```
  4. Build Docker images:
```bash
docker compose build
```

  5. Create data volume:
```bash
docker volume create uptime-kuma
```

  6. Bring up the Docker stack:

```bash
docker compose up -d
```

  7. Open Uptime Kuma at the configured URL, create admin user and import `uptime-kuma-configuration.json` in the settings menu.  The JSON file contains the services the platform will be monitoring.

