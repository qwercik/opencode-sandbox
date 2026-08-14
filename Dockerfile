FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS opencode
ARG OPENCODE_VERSION
RUN apk add --no-cache curl tar && \
    case "$(uname -m)" in \
      x86_64)  arch="x64" ;; \
      aarch64) arch="arm64" ;; \
      *)       echo "unsupported arch: $(uname -m)"; exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-${arch}-musl.tar.gz" \
    | tar -xz -C /usr/local/bin opencode && \
    chmod 755 /usr/local/bin/opencode

FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
RUN apk add --no-cache ca-certificates git libstdc++ libgcc bc iptables && \
    mkdir -p /home/sandbox/.config/opencode/plugins && chmod -R 777 /home/sandbox
COPY --from=opencode /usr/local/bin/opencode /usr/local/bin/opencode
COPY opencode-tools/scripts/. /usr/local/bin/
COPY opencode-tools/plugin /home/sandbox/.config/opencode/plugins/
ENTRYPOINT ["opencode"]
