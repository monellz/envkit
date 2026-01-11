FROM caddy:builder AS builder
ENV GOPROXY="https://goproxy.io,direct"
RUN xcaddy build --with github.com/mholt/caddy-webdav

FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
