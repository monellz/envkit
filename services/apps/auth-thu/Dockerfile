FROM golang:alpine AS builder
ENV GOPROXY="https://goproxy.io,direct"
WORKDIR /app
COPY ./auth-thu-src .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /app/auth-thu /app/cli/main.go

FROM alpine
RUN apk add --no-cache ca-certificates curl
COPY --from=builder /app/auth-thu /auth-thu
ENTRYPOINT ["/auth-thu"]
