FROM golang:1.22-alpine AS builder
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/cc-anywhere ./cmd/cc-anywhere

FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S cca && adduser -S -G cca cca && \
    mkdir -p /etc/cc-anywhere /var/lib/cc-anywhere /var/lib/cc-anywhere/inbox && \
    chown -R cca:cca /var/lib/cc-anywhere

COPY --from=builder /out/cc-anywhere /usr/local/bin/cc-anywhere

USER cca
VOLUME ["/etc/cc-anywhere", "/var/lib/cc-anywhere"]
EXPOSE 8443

ENTRYPOINT ["/usr/local/bin/cc-anywhere"]
CMD ["serve", "--config", "/etc/cc-anywhere/config.yaml"]
