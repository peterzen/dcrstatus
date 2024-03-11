# This Dockerfile is used to add Decred branding assets and CSS to the uptime kuma image.
FROM louislam/uptime-kuma:1

RUN rm -f /app/dist/icon.svg*
COPY ./decred.css /app/dist/
COPY ./assets/ /app/dist/
RUN perl -pi -e 's|</head>|<link rel="stylesheet" href="/decred.css"></head>|' /app/dist/index.html
