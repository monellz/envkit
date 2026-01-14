FROM caddy:builder AS builder
ENV GOPROXY="https://goproxy.io,direct"
RUN xcaddy build --with github.com/mholt/caddy-webdav  --with github.com/caddyserver/transform-encoder

FROM caddy:latest
RUN apk add --no-cache tzdata
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
