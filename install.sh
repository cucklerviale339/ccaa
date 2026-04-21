#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://github.com/cucklerviale339/ccaa.git"
DEFAULT_REF="feature/source-bound-egress-jiasu3"
TARGET_REF="${1:-$DEFAULT_REF}"
GO_VERSION="1.26.0"
INSTALL_ROOT="/usr/local/V2bX"
CONFIG_ROOT="/etc/V2bX"
SERVICE_FILE="/etc/systemd/system/V2bX.service"
BUILD_TAGS="sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor"
CACHE_ROOT="/var/cache/V2bX"
CONFIG_WAS_PRESENT=0

log() {
  printf '[V2bX] %s\n' "$*"
}

fail() {
  printf '[V2bX] %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "please run this script as root"
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      GO_ARCH="amd64"
      ;;
    aarch64|arm64)
      GO_ARCH="arm64"
      ;;
    *)
      fail "unsupported architecture: $(uname -m)"
      ;;
  esac
}

install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl git tar gzip ca-certificates
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y curl git tar gzip ca-certificates
    return
  fi
  if command -v yum >/dev/null 2>&1; then
    yum install -y curl git tar gzip ca-certificates
    return
  fi
  fail "unsupported package manager, please install curl git tar gzip ca-certificates manually"
}

ensure_go() {
  local current_version=""
  if command -v go >/dev/null 2>&1; then
    current_version="$(go env GOVERSION 2>/dev/null || true)"
    current_version="${current_version#go}"
  fi

  if [ -n "$current_version" ] && [ "$(printf '%s\n%s\n' "$GO_VERSION" "$current_version" | sort -V | head -n1)" = "$GO_VERSION" ]; then
    export PATH="/usr/local/go/bin:$PATH"
    return
  fi

  log "installing Go ${GO_VERSION}"
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz
  export PATH="/usr/local/go/bin:$PATH"
}

clone_repo() {
  WORKDIR="$(mktemp -d /tmp/v2bx-src.XXXXXX)"
  trap 'rm -rf "$WORKDIR"' EXIT

  if git clone --depth 1 --branch "$TARGET_REF" "$REPO_URL" "$WORKDIR" 2>/dev/null; then
    return
  fi

  git clone --depth 1 "$REPO_URL" "$WORKDIR"
  (
    cd "$WORKDIR"
    git fetch --depth 1 origin "$TARGET_REF"
    git checkout --detach FETCH_HEAD
  )
}

copy_if_missing() {
  local source_path="$1"
  local target_path="$2"
  if [ ! -f "$target_path" ]; then
    install -m 0644 "$source_path" "$target_path"
  fi
}

copy_always() {
  local source_path="$1"
  local target_path="$2"
  install -m 0644 "$source_path" "$target_path"
}

write_service() {
  cat >"$SERVICE_FILE" <<'EOF'
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/V2bX
ExecStart=/usr/local/V2bX/V2bX server --config /etc/V2bX/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=512000

[Install]
WantedBy=multi-user.target
EOF
}

install_binary() {
  local build_log
  build_log="$(mktemp /tmp/v2bx-build.XXXXXX.log)"

  log "building V2bX from ${TARGET_REF}, this may take a few minutes on first install"
  mkdir -p "$INSTALL_ROOT"
  mkdir -p "${CACHE_ROOT}/go-build" "${CACHE_ROOT}/go-mod"
  (
    cd "$WORKDIR"
    export PATH="/usr/local/go/bin:$PATH"
    export GOTOOLCHAIN=local
    export CGO_ENABLED=0
    export GOEXPERIMENT=jsonv2
    export GOCACHE="${CACHE_ROOT}/go-build"
    export GOMODCACHE="${CACHE_ROOT}/go-mod"
    go build -o "${INSTALL_ROOT}/V2bX" \
      -tags "${BUILD_TAGS}" \
      -trimpath \
      -ldflags "-X 'github.com/InazumaV/V2bX/cmd.version=${TARGET_REF}' -s -w -buildid=" \
      >"${build_log}" 2>&1
  ) || {
    tail -n 80 "${build_log}" >&2 || true
    rm -f "${build_log}"
    fail "build failed"
  }
  rm -f "${build_log}"
  chmod 0755 "${INSTALL_ROOT}/V2bX"
  ln -sf "${INSTALL_ROOT}/V2bX" /usr/bin/V2bX
}

install_assets() {
  mkdir -p "$CONFIG_ROOT"

  copy_if_missing "${WORKDIR}/example/config.json" "${CONFIG_ROOT}/config.json"
  copy_if_missing "${WORKDIR}/example/dns.json" "${CONFIG_ROOT}/dns.json"
  copy_if_missing "${WORKDIR}/example/route.json" "${CONFIG_ROOT}/route.json"
  copy_if_missing "${WORKDIR}/example/custom_inbound.json" "${CONFIG_ROOT}/custom_inbound.json"
  copy_if_missing "${WORKDIR}/example/custom_outbound.json" "${CONFIG_ROOT}/custom_outbound.json"

  copy_always "${WORKDIR}/example/geoip.dat" "${CONFIG_ROOT}/geoip.dat"
  copy_always "${WORKDIR}/example/geosite.dat" "${CONFIG_ROOT}/geosite.dat"
  copy_always "${WORKDIR}/example/geoip.db" "${CONFIG_ROOT}/geoip.db"
  copy_always "${WORKDIR}/example/geosite.db" "${CONFIG_ROOT}/geosite.db"
}

reload_service() {
  local was_active=0

  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not found, skipping service registration"
    return
  fi

  if systemctl is-active --quiet V2bX.service 2>/dev/null; then
    was_active=1
  fi

  write_service
  systemctl daemon-reload
  systemctl enable V2bX.service >/dev/null 2>&1 || true

  if [ "$was_active" -eq 1 ]; then
    systemctl restart V2bX.service
    log "V2bX updated and restarted"
    return
  fi

  if [ "$CONFIG_WAS_PRESENT" -eq 1 ]; then
    log "V2bX updated. Start it with: systemctl start V2bX"
    return
  fi

  log "V2bX installed. Edit ${CONFIG_ROOT}/config.json then start with: systemctl start V2bX"
}

main() {
  require_root
  detect_arch
  if [ -f "${CONFIG_ROOT}/config.json" ]; then
    CONFIG_WAS_PRESENT=1
  fi
  install_packages
  ensure_go
  clone_repo
  install_binary
  install_assets
  reload_service
  log "management command: V2bX"
}

main "$@"
