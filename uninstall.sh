#!/usr/bin/env bash
set -Eeuo pipefail

PURGE=0
if [[ ${1:-} == "--purge" ]]; then
  PURGE=1
fi

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 运行"

if [[ $PURGE == 1 ]]; then
  printf '这会停止 Telemt 并删除配置、用户认证、备份和运行依赖。\n'
  read -r -p '确认彻底删除请输入 PURGE：' confirmation
  [[ $confirmation == PURGE ]] || die "已取消"
fi

systemctl disable --now telemt 2>/dev/null || true
rm -f /etc/systemd/system/telemt.service
systemctl daemon-reload
rm -f /usr/local/bin/telemt /usr/local/sbin/tgctl

if [[ $PURGE == 1 ]]; then
  rm -rf /etc/telemt /opt/telemt
  if id telemt >/dev/null 2>&1; then
    userdel telemt
  fi
  rm -f /root/tg-proxy-owner.link
  printf 'Telemt 和全部相关数据已删除。\n'
else
  printf '服务已移除，配置保留在 /etc/telemt 和 /opt/telemt。\n'
fi
