#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly TELEMT_VERSION="3.5.14"
readonly TELEMT_X86_SHA256="b10f86c6851f5c422a49d98deea55e8ef4aea7879605e59c1d4aa43c8f4c70ce"
readonly TELEMT_ARM_SHA256="d2e3ca6a3f407aecb190c4a73db74ec581d56b5dd6ab469cb0e1d0f2c3d31c57"
readonly DEFAULT_PORT="443"
readonly DEFAULT_API_PORT="19091"
readonly DEFAULT_DOMAIN="www.bing.com"
readonly DEFAULT_USER="owner"
readonly REPO_RAW_BASE="${TGCTL_REPO_RAW_BASE:-https://raw.githubusercontent.com/ll808/telegram-mtproxy-manager/main}"

SCRIPT_DIR=""
if [[ -n ${BASH_SOURCE[0]:-} ]] && [[ -f ${BASH_SOURCE[0]} ]]; then
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi

PORT="$DEFAULT_PORT"
API_PORT="$DEFAULT_API_PORT"
TLS_DOMAIN="$DEFAULT_DOMAIN"
OWNER_NAME="$DEFAULT_USER"
PUBLIC_HOST=""
START_SERVICE=1
TMP_DIR=""
API_HEADER_FILE=""

cleanup() {
  if [[ -n $TMP_DIR ]] && [[ $TMP_DIR == /tmp/tmp.* ]] && [[ -d $TMP_DIR ]]; then
    rm -rf -- "$TMP_DIR"
  fi
  if [[ -n $API_HEADER_FILE ]] && [[ -f $API_HEADER_FILE ]]; then
    rm -f -- "$API_HEADER_FILE"
  fi
}
trap cleanup EXIT

log() {
  printf '[install] %s\n' "$*"
}

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法：
  sudo bash install.sh [选项]

选项：
  --port PORT           MTProxy TCP 端口，默认 443
  --api-port PORT       本机管理 API 端口，默认 19091
  --domain DOMAIN       FakeTLS 伪装域名，默认 www.bing.com
  --user USERNAME       初始用户，默认 owner
  --public-host HOST    客户端连接使用的公网 IPv4
  --no-start            安装后不启动服务
  -h, --help            显示帮助
EOF
}

while (($#)); do
  case "$1" in
    --port)
      PORT=${2:-}
      shift 2
      ;;
    --api-port)
      API_PORT=${2:-}
      shift 2
      ;;
    --domain)
      TLS_DOMAIN=${2:-}
      shift 2
      ;;
    --user)
      OWNER_NAME=${2:-}
      shift 2
      ;;
    --public-host)
      PUBLIC_HOST=${2:-}
      shift 2
      ;;
    --no-start)
      START_SERVICE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1"
      ;;
  esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 运行"

if [[ ! -r /etc/os-release ]]; then
  die "无法识别操作系统"
fi
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "仅支持 Ubuntu 或 Debian" ;;
esac

if [[ ! $PORT =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
  die "代理端口必须是 1 到 65535 之间的整数"
fi
if [[ ! $API_PORT =~ ^[0-9]+$ ]] || ((API_PORT < 1024 || API_PORT > 65535)); then
  die "管理 API 端口必须是 1024 到 65535 之间的整数"
fi
if [[ $PORT == "$API_PORT" ]]; then
  die "代理端口和管理 API 端口不能相同"
fi
if [[ ! $TLS_DOMAIN =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  die "伪装域名格式无效"
fi
if [[ ! $OWNER_NAME =~ ^[A-Za-z0-9_.-]{1,64}$ ]]; then
  die "用户名只能包含字母、数字、点、下划线和短横线"
fi
validate_ipv4() {
  local address=$1
  local octet
  local -a octets
  IFS=. read -r -a octets <<<"$address"
  if ((${#octets[@]} != 4)); then
    return 1
  fi
  for octet in "${octets[@]}"; do
    if [[ ! $octet =~ ^[0-9]{1,3}$ ]] || ((10#$octet > 255)); then
      return 1
    fi
  done
}

if [[ -n $PUBLIC_HOST ]] && ! validate_ipv4 "$PUBLIC_HOST"; then
  die "--public-host 必须是有效 IPv4 地址"
fi

install_dependencies() {
  local missing=()
  local command_name

  for command_name in curl jq openssl ss tar sha256sum systemctl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$command_name")
    fi
  done
  if ((${#missing[@]} == 0)); then
    return 0
  fi

  log "安装依赖：${missing[*]}"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl jq openssl iproute2 tar coreutils systemd
}

port_is_listening() {
  local port=$1
  ss -H -ltn 2>/dev/null |
    awk '{print $4}' |
    grep -Eq "[:.]${port}$"
}

detect_public_ipv4() {
  local value
  value=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
  if [[ -z $value ]]; then
    value=$(ip -4 route get 1.1.1.1 2>/dev/null |
      awk '{
        for (i = 1; i <= NF; i++) {
          if ($i == "src") {
            print $(i + 1)
            exit
          }
        }
      }')
  fi
  printf '%s' "$value"
}

check_domain_reachable() {
  local http_code
  http_code=$(curl -4 -sS -L -o /dev/null -w '%{http_code}' \
    --max-time 12 "https://${TLS_DOMAIN}" || true)
  if [[ -z $http_code ]] || [[ $http_code == "000" ]]; then
    die "VPS 无法通过 HTTPS 访问伪装域名 ${TLS_DOMAIN}"
  fi
  log "伪装域名可达：${TLS_DOMAIN}（HTTP ${http_code}）"
}

install_dependencies

if [[ -e /etc/telemt/telemt.toml ]] ||
   [[ -e /usr/local/bin/telemt ]] ||
   systemctl cat telemt.service >/dev/null 2>&1; then
  die "检测到已有 Telemt 安装。请先迁移或卸载，避免覆盖现有用户"
fi

if port_is_listening "$PORT"; then
  die "TCP 端口 ${PORT} 已被占用"
fi
if port_is_listening "$API_PORT"; then
  die "管理 API 端口 ${API_PORT} 已被占用"
fi

check_domain_reachable
if [[ -z $PUBLIC_HOST ]]; then
  PUBLIC_HOST=$(detect_public_ipv4)
fi
if ! validate_ipv4 "$PUBLIC_HOST"; then
  die "无法自动识别公网 IPv4，请使用 --public-host 指定"
fi
log "客户端连接地址：${PUBLIC_HOST}:${PORT}"

case "$(uname -m)" in
  x86_64|amd64)
    ARCHIVE="telemt-x86_64-linux-gnu.tar.gz"
    ARCHIVE_SHA256="$TELEMT_X86_SHA256"
    ;;
  aarch64|arm64)
    ARCHIVE="telemt-aarch64-linux-gnu.tar.gz"
    ARCHIVE_SHA256="$TELEMT_ARM_SHA256"
    ;;
  *)
    die "暂不支持 CPU 架构：$(uname -m)"
    ;;
esac

TMP_DIR=$(mktemp -d)
ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE}"
DOWNLOAD_URL="https://github.com/telemt/telemt/releases/download/${TELEMT_VERSION}/${ARCHIVE}"

log "下载 Telemt ${TELEMT_VERSION}"
curl --proto '=https' --tlsv1.2 -fL --retry 3 \
  -o "$ARCHIVE_PATH" "$DOWNLOAD_URL"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE_PATH" |
  sha256sum -c -
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR" telemt

if ! id telemt >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/telemt \
    --shell /usr/sbin/nologin --user-group telemt
fi

install -d -o telemt -g telemt -m 0750 /etc/telemt /opt/telemt
install -d -o root -g root -m 0700 /etc/telemt/backups
install -m 0755 "${TMP_DIR}/telemt" /usr/local/bin/telemt

OWNER_SECRET=$(openssl rand -hex 16)
API_TOKEN=$(openssl rand -hex 32)
umask 077
printf '%s' "$API_TOKEN" > /etc/telemt/api.token
chown root:root /etc/telemt/api.token
chmod 0600 /etc/telemt/api.token

CONFIG_TMP="${TMP_DIR}/telemt.toml"
cat >"$CONFIG_TMP" <<EOF
[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = []
public_host = "${PUBLIC_HOST}"
public_port = ${PORT}

[server]
port = ${PORT}

[server.api]
enabled = true
listen = "127.0.0.1:${API_PORT}"
whitelist = ["127.0.0.1/32", "::1/128"]
auth_header = "Bearer ${API_TOKEN}"
request_body_limit_bytes = 65536
minimal_runtime_enabled = false
gray_action = "drop"

[[server.listeners]]
ip = "0.0.0.0"
port = ${PORT}

[censorship]
tls_domain = "${TLS_DOMAIN}"
mask = true
tls_emulation = true
tls_front_dir = "/opt/telemt/tlsfront"

[access.users]
${OWNER_NAME} = "${OWNER_SECRET}"
EOF

install -o telemt -g telemt -m 0600 "$CONFIG_TMP" /etc/telemt/telemt.toml

cat > /etc/systemd/system/telemt.service <<'EOF'
[Unit]
Description=Telemt MTProxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=/usr/local/bin/telemt run /etc/telemt/telemt.toml
Restart=on-failure
RestartSec=3
LimitNOFILE=65536
UMask=0077
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectClock=true
ProtectControlGroups=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
RemoveIPC=true
MemoryDenyWriteExecute=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
ReadWritePaths=/etc/telemt /opt/telemt /run/telemt
RuntimeDirectory=telemt
RuntimeDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/telemt.service

TGCTL_TMP="${TMP_DIR}/tgctl"
if [[ -n $SCRIPT_DIR ]] && [[ -f "${SCRIPT_DIR}/tgctl" ]]; then
  cp "${SCRIPT_DIR}/tgctl" "$TGCTL_TMP"
else
  curl --proto '=https' --tlsv1.2 -fsSL \
    "${REPO_RAW_BASE}/tgctl" -o "$TGCTL_TMP"
fi
bash -n "$TGCTL_TMP"
install -o root -g root -m 0750 "$TGCTL_TMP" /usr/local/sbin/tgctl

if command -v ufw >/dev/null 2>&1 &&
   ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "${PORT}/tcp" >/dev/null || log "警告：UFW 规则添加失败，请手动检查"
fi

systemctl daemon-reload
systemctl enable telemt

if ((START_SERVICE == 1)); then
  systemctl restart telemt
  success=0
  for _ in {1..30}; do
    if systemctl is-active --quiet telemt && port_is_listening "$PORT"; then
      success=1
      break
    fi
    sleep 1
  done
  ((success == 1)) || {
    journalctl -u telemt -n 100 --no-pager >&2 || true
    die "服务启动或端口检测失败"
  }

  API_HEADER_FILE=$(mktemp)
  chmod 0600 "$API_HEADER_FILE"
  printf 'Authorization: Bearer %s\n' "$API_TOKEN" >"$API_HEADER_FILE"
  OWNER_LINK=$(curl -sS --max-time 10 -H "@${API_HEADER_FILE}" \
    "http://127.0.0.1:${API_PORT}/v1/users" |
    jq -r --arg username "$OWNER_NAME" '
      .data[] |
      select(.username == $username) |
      .links.tls[0] // empty
    ')
  [[ -n $OWNER_LINK ]] || die "服务已启动，但无法生成初始用户链接"
  printf '%s\n' "$OWNER_LINK" > /root/tg-proxy-owner.link
  chmod 0600 /root/tg-proxy-owner.link
fi

if command -v sshd >/dev/null 2>&1; then
  SSH_EFFECTIVE_CONFIG=$(sshd -T 2>/dev/null || true)
  if grep -qi '^permitrootlogin yes$' <<<"$SSH_EFFECTIVE_CONFIG" ||
     grep -qi '^passwordauthentication yes$' <<<"$SSH_EFFECTIVE_CONFIG"; then
    log "警告：SSH root 密码登录仍可能启用，请先配置密钥登录再收紧 sshd"
  fi
fi

cat <<EOF

安装完成
  服务：telemt.service
  代理端口：${PORT}/TCP
  管理 API：127.0.0.1:${API_PORT}
  伪装域名：${TLS_DOMAIN}
  默认用户：${OWNER_NAME}

运行 tgctl 打开管理菜单。
初始连接链接保存在 /root/tg-proxy-owner.link，仅 root 可读。

如果云厂商提供独立安全组，请在控制台放行 TCP ${PORT}。
EOF
