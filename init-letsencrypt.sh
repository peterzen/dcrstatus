#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────
: "${SERVER_URL:?Set SERVER_URL to your domain (e.g. status.example.com)}"
: "${CERTBOT_EMAIL:?Set CERTBOT_EMAIL for Lets Encrypt notifications}"
STAGING="${STAGING:-0}"
# ────────────────────────────────────────────────────────────────

CERTBOT_ARGS=(
  certonly --webroot
  -w /var/www/certbot
  -d "$SERVER_URL"
  --email "$CERTBOT_EMAIL"
  --agree-tos
  --no-eff-email
  --force-renewal
)

if [ "$STAGING" = "1" ]; then
  CERTBOT_ARGS+=(--staging)
  echo "WARNING: Using Lets Encrypt STAGING environment"
fi

LIVE_DIR="/etc/letsencrypt/live/$SERVER_URL"

echo "==> Creating temporary self-signed cert so nginx can start..."

docker compose run --rm -T --entrypoint sh certbot -c "\
  mkdir -p $LIVE_DIR && \
  openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
    -keyout $LIVE_DIR/privkey.pem \
    -out $LIVE_DIR/fullchain.pem \
    -subj /CN=localhost 2>/dev/null && \
  echo Done"

echo "==> Starting proxy for ACME challenge..."
docker compose up -d proxy
sleep 5

echo "==> Removing temporary self-signed cert..."
docker compose run --rm -T --entrypoint sh certbot -c "rm -rf $LIVE_DIR"

echo "==> Requesting certificate from Lets Encrypt..."
docker compose run --rm -T --entrypoint certbot certbot "${CERTBOT_ARGS[@]}"

echo "==> Reloading nginx with real certificate..."
docker compose exec proxy nginx -s reload

echo "==> Starting all services..."
docker compose up -d

echo ""
echo "Done! Certificate issued for $SERVER_URL"
echo "  Certbot container will auto-renew every 12 hours."
echo "  To force renewal:  docker compose run --rm certbot certbot renew --force-renewal"
echo "  Then reload nginx:  docker compose exec proxy nginx -s reload"
