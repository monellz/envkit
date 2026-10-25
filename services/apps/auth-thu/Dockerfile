# 清华校园网认证客户端 GoAuthing（auth-thu）。
# 直接使用上游 release 的静态二进制，不再从源码编译；升级时同时修改 VERSION 和下面的 sha256。
FROM alpine

ARG TARGETARCH
ARG VERSION=v2.4.0

# curl 用于 compose 中的健康检查
RUN set -eu; \
    apk add --no-cache ca-certificates curl; \
    case "$TARGETARCH" in \
        arm64) asset=auth-thu.linux.arm64;  sha=fc1709e7c516ddf5a8408a63255c31d83c7db624214e87e371dc47dc85a8599e ;; \
        amd64) asset=auth-thu.linux.x86_64; sha=e016433751bf0b0a59658486c0b1c67aa1152e55f2f1aaca3947d3aae771870f ;; \
        *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    wget -q -O /auth-thu "https://github.com/z4yx/GoAuthing/releases/download/$VERSION/$asset"; \
    echo "$sha  /auth-thu" | sha256sum -c -; \
    chmod 755 /auth-thu

ENTRYPOINT ["/auth-thu"]
