# The company's server advertises /multiple-pages/scan-login.html as its
# scan_code_login_url. The upstream client still encodes the retired
# /api/token/verify/view page, which opens the portal's 404 page on phones.
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
