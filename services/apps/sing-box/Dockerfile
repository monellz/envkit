FROM golang:1.25-alpine AS builder
COPY sing-box-src /go/src/github.com/sagernet/sing-box
WORKDIR /go/src/github.com/sagernet/sing-box
ARG TARGETOS TARGETARCH
ARG GOPROXY="https://goproxy.io,direct"
ENV GOPROXY ${GOPROXY}
ENV CGO_ENABLED=0
ENV GOOS=$TARGETOS
ENV GOARCH=$TARGETARCH
RUN set -ex \
    && sed -i 's#https\?://dl-cdn.alpinelinux.org/alpine#https://mirrors.tuna.tsinghua.edu.cn/alpine#g' /etc/apk/repositories \
    && apk add git build-base \
    && go build -v -trimpath -tags \
        "with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale" \
        -o /go/bin/sing-box \
        -ldflags "-X \"github.com/sagernet/sing-box/constant.Version=0.0.0\" -s -w -buildid=" \
        ./cmd/sing-box

FROM alpine AS dist
RUN set -ex \
    && sed -i 's#https\?://dl-cdn.alpinelinux.org/alpine#https://mirrors.tuna.tsinghua.edu.cn/alpine#g' /etc/apk/repositories \
    && apk upgrade \
    && apk add entr \
    && apk add bash tzdata ca-certificates nftables \
    && rm -rf /var/cache/apk/*
COPY --from=builder /go/bin/sing-box /usr/local/bin/sing-box

# ENTRYPOINT sing-box -c $CONFIG_PATH run
# config文件修改时自动重启
ENTRYPOINT echo $CONFIG_PATH | entr -n -r sing-box -c $CONFIG_PATH run

