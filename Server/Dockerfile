# 可选 build-arg：
#   APK_MIRROR  - 替换 Alpine APK 仓库域名（默认 dl-cdn.alpinelinux.org）
#                 国内 VPS 推荐 mirrors.aliyun.com 或 mirrors.ustc.edu.cn
#   GOPROXY     - Go module proxy（默认 direct，国内推荐 https://goproxy.cn）
# 示例：
#   docker build --build-arg APK_MIRROR=mirrors.aliyun.com \
#                --build-arg GOPROXY=https://goproxy.cn \
#                -t cc-anywhere:latest .

FROM golang:1.22-alpine AS builder
ARG GOPROXY
ENV GOPROXY=${GOPROXY:-https://proxy.golang.org,direct}
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/cc-anywhere ./cmd/cc-anywhere

FROM alpine:3.19
ARG APK_MIRROR
RUN if [ -n "$APK_MIRROR" ]; then \
      sed -i "s|dl-cdn.alpinelinux.org|$APK_MIRROR|g" /etc/apk/repositories; \
    fi && \
    apk add --no-cache ca-certificates tzdata && \
    addgroup -S cca && adduser -S -G cca cca && \
    mkdir -p /etc/cc-anywhere /var/lib/cc-anywhere /var/lib/cc-anywhere/inbox && \
    chown -R cca:cca /var/lib/cc-anywhere

COPY --from=builder /out/cc-anywhere /usr/local/bin/cc-anywhere

USER cca
VOLUME ["/etc/cc-anywhere", "/var/lib/cc-anywhere"]
EXPOSE 8443

ENTRYPOINT ["/usr/local/bin/cc-anywhere"]
CMD ["serve", "--config", "/etc/cc-anywhere/config.yaml"]
