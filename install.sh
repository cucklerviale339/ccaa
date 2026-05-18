#!/usr/bin/env bash
set -euo pipefail

repo="cucklerviale339/ccaa"
version="${1:-v1.0.9}"
asset="V2bX-linux-64.zip"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y curl unzip ca-certificates openssl
fi

release_api="https://api.github.com/repos/${repo}/releases/tags/${version}"
asset_url="$(curl -fsSL "$release_api" | grep -o '"browser_download_url": "[^"]*V2bX-linux-64.zip"' | head -n1 | cut -d '"' -f4)"
if [[ -z "${asset_url}" ]]; then
  echo "[V2bX] ERROR: failed to locate ${asset} in ${version}"
  exit 1
fi

curl -fsSL "$asset_url" -o "${tmp_dir}/${asset}"
curl -fsSL "${asset_url}.dgst" -o "${tmp_dir}/${asset}.dgst"
expected="$(grep '^SHA256 ' "${tmp_dir}/${asset}.dgst" | awk -F '= ' '{print $2}' | tr -d '\r')"
actual="$(sha256sum "${tmp_dir}/${asset}" | awk '{print $1}')"
if [[ -z "$expected" || "$expected" != "$actual" ]]; then
  echo "[V2bX] ERROR: sha256 mismatch for ${asset}"
  echo "[V2bX] expected: ${expected}"
  echo "[V2bX] actual:   ${actual}"
  exit 1
fi

mkdir -p /usr/local/V2bX /etc/V2bX "${tmp_dir}/pkg"
unzip -o "${tmp_dir}/${asset}" -d "${tmp_dir}/pkg" >/dev/null
install -m 755 "${tmp_dir}/pkg/V2bX" /usr/local/V2bX/V2bX
for file in config.json custom_inbound.json custom_outbound.json dns.json route.json geoip.dat geoip.db geosite.dat geosite.db; do
  if [[ -f "${tmp_dir}/pkg/${file}" && ! -f "/etc/V2bX/${file}" ]]; then
    install -m 644 "${tmp_dir}/pkg/${file}" "/etc/V2bX/${file}"
  fi
done

curl -fsSL "https://raw.githubusercontent.com/${repo}/master/V2bX.sh" -o /usr/bin/V2bX
chmod +x /usr/bin/V2bX
ln -sf /usr/bin/V2bX /usr/bin/v2bx
ln -sf /usr/bin/V2bX /bin/v2bx

cat >/etc/systemd/system/V2bX.service <<'EOF'
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitNOFILE=999999
WorkingDirectory=/usr/local/V2bX/
ExecStart=/usr/local/V2bX/V2bX server
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable V2bX >/dev/null 2>&1 || true
systemctl restart V2bX 2>/dev/null || true
echo "[V2bX] install complete"
