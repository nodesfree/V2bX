#!/usr/bin/env bash
set -Eeuo pipefail

REPO="nodesfree/V2bX"
INSTALL_DIR="/usr/local/V2bX"
CONFIG_DIR="/etc/V2bX"
SERVICE_NAME="V2bX"

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'
fail() { echo -e "${red}错误：$*${plain}" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "请使用 root 用户运行此脚本。"
command -v curl >/dev/null 2>&1 || fail "未安装 curl。请先安装 curl 后重试。"
command -v unzip >/dev/null 2>&1 || fail "未安装 unzip。请先安装 unzip 后重试。"
command -v systemctl >/dev/null 2>&1 || fail "此安装脚本目前支持使用 systemd 的 VPS 系统。"

case "$(uname -m)" in
  x86_64|amd64) asset_arch="linux-64" ;;
  aarch64|arm64) asset_arch="linux-arm64-v8a" ;;
  s390x) asset_arch="linux-s390x" ;;
  *) fail "暂不支持此架构：$(uname -m)（支持 x86_64、aarch64、s390x）。" ;;
esac

version="${1:-}"
if [[ -z "$version" ]]; then
  version="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
[[ -n "$version" ]] || fail "获取最新版本失败。请先在 ${REPO} 发布 Release，或用 install.sh <版本标签> 指定版本。"

asset="V2bX-${asset_arch}.zip"
tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT
release_url="https://github.com/${REPO}/releases/download/${version}/${asset}"
echo "下载 V2bX ${version} (${asset_arch})..."
curl -fL --retry 3 "$release_url" -o "${tmp_dir}/${asset}" || fail "下载失败：${release_url}"
unzip -q "${tmp_dir}/${asset}" -d "${tmp_dir}/payload" || fail "发行包解压失败。"
[[ -x "${tmp_dir}/payload/V2bX" ]] || fail "发行包中没有可执行文件 V2bX。"

install -d -m 0755 "$INSTALL_DIR" "$CONFIG_DIR"
install -m 0755 "${tmp_dir}/payload/V2bX" "${INSTALL_DIR}/V2bX"
ln -sfn "${INSTALL_DIR}/V2bX" /usr/local/bin/V2bX

# Preserve existing configuration on upgrades; initialize it only on first install.
for file in config.json dns.json route.json custom_inbound.json custom_outbound.json; do
  if [[ -f "${tmp_dir}/payload/${file}" && ! -e "${CONFIG_DIR}/${file}" ]]; then
    install -m 0644 "${tmp_dir}/payload/${file}" "${CONFIG_DIR}/${file}"
  fi
done
for file in geoip.dat geosite.dat; do
  if [[ -f "${tmp_dir}/payload/${file}" ]]; then
    install -m 0644 "${tmp_dir}/payload/${file}" "${CONFIG_DIR}/${file}"
  fi
done

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=V2bX Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/V2bX server --config ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=999999

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
if [[ -f "${CONFIG_DIR}/config.json" ]]; then
  systemctl restart "$SERVICE_NAME" || systemctl start "$SERVICE_NAME"
fi

echo -e "${green}V2bX ${version} 已安装。${plain}"
echo "配置文件：${CONFIG_DIR}/config.json"
echo "查看状态：systemctl status ${SERVICE_NAME}"
echo "查看日志：journalctl -u ${SERVICE_NAME} -f"
echo "首次安装请先编辑配置文件中的面板地址、密钥和节点信息。"
