# 公司服务器下发的扫码登录地址（scan_code_login_url）是 /multiple-pages/scan-login.html，
# 而上游 corplink-headless 仍然使用已经下线的 /api/token/verify/view，手机扫码后会打开 404 页面，
# 所以构建时打补丁替换成新地址
FROM --platform=$BUILDPLATFORM golang:1.24 AS headless-builder
ARG TARGETARCH
ARG CORPLINK_HEADLESS_REV=2e9656729485274bb0162010ce6dfe486dbb4e70
WORKDIR /src
RUN git init \
    && git remote add origin https://github.com/overvenus/corplink-headless.git \
    && git fetch --depth=1 origin "${CORPLINK_HEADLESS_REV}" \
    && git checkout --detach FETCH_HEAD
RUN grep -q 'cli.Url("/api/token/verify/view"' pkg/headless/login.go \
    && sed -i 's#/api/token/verify/view#/multiple-pages/scan-login.html#' pkg/headless/login.go
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -trimpath -o /out/corplink-headless .

FROM overvenus/corplink:latest
COPY --from=headless-builder /out/corplink-headless /opt/Corplink/corplink-headless
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
