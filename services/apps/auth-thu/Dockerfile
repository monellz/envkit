FROM golang:alpine AS builder
ENV GOPROXY="https://goproxy.io,direct"
WORKDIR /app
COPY ./auth-thu-src .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /app/auth-thu /app/cli/main.go

FROM scratch
COPY --from=builder /app/auth-thu /auth-thu
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["/auth-thu"]
