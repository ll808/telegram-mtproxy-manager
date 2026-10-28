#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly TELEMT_VERSION="3.5.14"
readonly TELEMT_X86_SHA256="b10f86c6851f5c422a49d98deea55e8ef4aea7879605e59c1d4aa43c8f4c70ce"
readonly TELEMT_ARM_SHA256="d2e3ca6a3f407aecb190c4a73db74ec581d56b5dd6ab469cb0e1d0f2c3d31c57"

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 运行"
command -v curl >/dev/null || die "缺少 curl"
command -v sha256sum >/dev/null || die "缺少 sha256sum"

case "$(uname -m)" in
  x86_64|amd64)
    archive="telemt-x86_64-linux-gnu.tar.gz"
    expected_sha="$TELEMT_X86_SHA256"
    ;;
  aarch64|arm64)
    archive="telemt-aarch64-linux-gnu.tar.gz"
    expected_sha="$TELEMT_ARM_SHA256"
    ;;
  *)
    die "不支持的 CPU 架构：$(uname -m)"
    ;;
esac

tmp_dir=$(mktemp -d)
cleanup() {
  if [[ -n $tmp_dir ]] && [[ $tmp_dir == /tmp/tmp.* ]] && [[ -d $tmp_dir ]]; then
    rm -rf -- "$tmp_dir"
  fi
}
trap cleanup EXIT

url="https://github.com/telemt/telemt/releases/download/${TELEMT_VERSION}/${archive}"
curl --proto '=https' --tlsv1.2 -fL --retry 3 -o "${tmp_dir}/${archive}" "$url"
printf '%s  %s\n' "$expected_sha" "${tmp_dir}/${archive}" | sha256sum -c -
tar -xzf "${tmp_dir}/${archive}" -C "$tmp_dir" telemt

backup="/usr/local/bin/telemt.pre-${TELEMT_VERSION}"
if [[ -f /usr/local/bin/telemt ]]; then
  cp -a /usr/local/bin/telemt "$backup"
fi
install -m 0755 "${tmp_dir}/telemt" /usr/local/bin/telemt

if ! systemctl restart telemt || ! systemctl is-active --quiet telemt; then
  if [[ -f $backup ]]; then
    mv "$backup" /usr/local/bin/telemt
    systemctl restart telemt || true
  fi
  die "升级失败，已尝试恢复旧二进制"
fi

printf 'Telemt 已升级到 %s。\n' "$TELEMT_VERSION"
tgctl status
