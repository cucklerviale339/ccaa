#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="cucklerviale339"
REPO_NAME="ccaa"
DEFAULT_VERSION="latest"
TARGET_VERSION="${1:-$DEFAULT_VERSION}"
INSTALL_ROOT="/usr/local/V2bX"
CONFIG_ROOT="/etc/V2bX"
SERVICE_FILE="/etc/systemd/system/V2bX.service"
MANAGEMENT_SCRIPT_URL="https://raw.githubusercontent.com/cucklerviale339/ccaa/feature/source-bound-egress-jiasu3/V2bX.sh"
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

detect_asset_name() {
  case "$(uname -m)" in
    x86_64|amd64)
      ASSET_NAME="linux-64"
      ;;
    aarch64|arm64)
      ASSET_NAME="linux-arm64-v8a"
      ;;
    armv7l|armv7)
      ASSET_NAME="linux-arm32-v7a"
      ;;
    armv6l|armv6)
      ASSET_NAME="linux-arm32-v6"
      ;;
    armv5tel|armv5)
      ASSET_NAME="linux-arm32-v5"
      ;;
    mips64el)
      ASSET_NAME="linux-mips64le"
      ;;
    mips64)
      ASSET_NAME="linux-mips64"
      ;;
    mipsel)
      ASSET_NAME="linux-mips32le"
      ;;
    mips)
      ASSET_NAME="linux-mips32"
      ;;
    ppc64le)
      ASSET_NAME="linux-ppc64le"
      ;;
    ppc64)
      ASSET_NAME="linux-ppc64"
      ;;
    riscv64)
      ASSET_NAME="linux-riscv64"
      ;;
    s390x)
      ASSET_NAME="linux-s390x"
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
    apt-get install -y curl unzip ca-certificates
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y curl unzip ca-certificates
    return
  fi
  if command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip ca-certificates
    return
  fi
  fail "unsupported package manager, please install curl unzip ca-certificates manually"
}

download_release() {
  WORKDIR="$(mktemp -d /tmp/v2bx-release.XXXXXX)"
  trap 'rm -rf "$WORKDIR"' EXIT

  ARCHIVE_NAME="V2bX-${ASSET_NAME}.zip"
  ARCHIVE_PATH="${WORKDIR}/${ARCHIVE_NAME}"

  if [ "$TARGET_VERSION" = "latest" ]; then
    DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/${ARCHIVE_NAME}"
  else
    DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TARGET_VERSION}/${ARCHIVE_NAME}"
  fi

  log "downloading ${ARCHIVE_NAME}"
  if ! curl -fsSL "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"; then
    if [ "$TARGET_VERSION" = "latest" ]; then
      fail "download failed. publish a GitHub Release first, then rerun this installer"
    fi
    fail "download failed for release ${TARGET_VERSION}. make sure that tag exists and the release asset ${ARCHIVE_NAME} has been published"
  fi

  unzip -oq "$ARCHIVE_PATH" -d "$WORKDIR"
}

copy_if_missing() {
  local source_path="$1"
  local target_path="$2"
  if [ -f "$source_path" ] && [ ! -f "$target_path" ]; then
    install -m 0644 "$source_path" "$target_path"
  fi
}

copy_always() {
  local source_path="$1"
  local target_path="$2"
  if [ -f "$source_path" ]; then
    install -m 0644 "$source_path" "$target_path"
  fi
}

write_service() {
  cat >"$SERVICE_FILE" <<'EOF'
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/V2bX/
ExecStart=/usr/local/V2bX/V2bX server
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

install_binary() {
  mkdir -p "$INSTALL_ROOT"
  install -m 0755 "${WORKDIR}/V2bX" "${INSTALL_ROOT}/V2bX"
}

install_management_script() {
  rm -f /usr/bin/V2bX /usr/bin/v2bx
  curl -fsSL "$MANAGEMENT_SCRIPT_URL" -o /usr/bin/V2bX
  chmod 0755 /usr/bin/V2bX
  ln -sf /usr/bin/V2bX /usr/bin/v2bx
}

install_assets() {
  mkdir -p "$CONFIG_ROOT"

  copy_if_missing "${WORKDIR}/config.json" "${CONFIG_ROOT}/config.json"
  copy_if_missing "${WORKDIR}/dns.json" "${CONFIG_ROOT}/dns.json"
  copy_if_missing "${WORKDIR}/route.json" "${CONFIG_ROOT}/route.json"
  copy_if_missing "${WORKDIR}/custom_inbound.json" "${CONFIG_ROOT}/custom_inbound.json"
  copy_if_missing "${WORKDIR}/custom_outbound.json" "${CONFIG_ROOT}/custom_outbound.json"

  copy_always "${WORKDIR}/geoip.dat" "${CONFIG_ROOT}/geoip.dat"
  copy_always "${WORKDIR}/geosite.dat" "${CONFIG_ROOT}/geosite.dat"
  copy_always "${WORKDIR}/geoip.db" "${CONFIG_ROOT}/geoip.db"
  copy_always "${WORKDIR}/geosite.db" "${CONFIG_ROOT}/geosite.db"
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

show_management_usage() {
  cat <<'EOF'

V2bX 管理脚本使用方法 (兼容使用 V2bX / v2bx 执行):
------------------------------------------
V2bX              - 显示管理菜单 (功能更多)
V2bX start        - 启动 V2bX
V2bX stop         - 停止 V2bX
V2bX restart      - 重启 V2bX
V2bX status       - 查看 V2bX 状态
V2bX enable       - 设置 V2bX 开机自启
V2bX disable      - 取消 V2bX 开机自启
V2bX log          - 查看 V2bX 日志
V2bX x25519       - 生成 x25519 密钥
V2bX generate     - 生成 V2bX 配置文件
V2bX update       - 更新 V2bX
V2bX update x.x.x - 更新 V2bX 指定版本
V2bX install      - 安装 V2bX
V2bX uninstall    - 卸载 V2bX
V2bX version      - 查看 V2bX 版本
------------------------------------------
EOF
}

main() {
  require_root
  detect_asset_name
  if [ -f "${CONFIG_ROOT}/config.json" ]; then
    CONFIG_WAS_PRESENT=1
  fi
  install_packages
  download_release
  install_binary
  install_management_script
  install_assets
  reload_service
  show_management_usage
}

main "$@"
