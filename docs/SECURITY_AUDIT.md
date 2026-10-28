# 安全审查记录

审查日期：2026-10-28

## 审查范围

本次审查覆盖 `tgctl`、systemd 服务权限、本机管理 API、secret 与备份处理、
安装供应链和已部署 VPS 的运行状态。Telemt 本身是第三方开源程序，本记录不代表
对其全部源码的正式安全审计。

## 已修复问题

| 编号 | 风险 | 原问题 | 修复 |
| --- | --- | --- | --- |
| SEC-01 | 高 | 管理 API 没有认证，本机任何进程均可管理用户 | 增加 256 位随机 Bearer 令牌，令牌文件仅 root 可读 |
| SEC-02 | 中 | 服务保留 `CAP_NET_ADMIN` | 删除该能力，仅保留低端口绑定所需的 `CAP_NET_BIND_SERVICE` |
| SEC-03 | 中 | 端口修改备份会无限累积完整 secret | 限制为最近 5 份，目录 700、文件 600 |
| SEC-04 | 低 | 日志行数参数未校验 | 限制为 1 到 10000 的整数 |
| SEC-05 | 低 | systemd 设备、内核和命名空间暴露面偏大 | 增加 PrivateDevices、ProtectKernel*、RestrictNamespaces 等限制 |

修复后检查：

- 无令牌访问 `/v1/users` 返回 `401`；
- systemd 暴露评分由 `6.2 MEDIUM` 降至 `1.6 OK`；
- `tgctl` 通过 ShellCheck；
- Telemt 以非 root 用户运行；
- 管理 API 仅监听 `127.0.0.1`；
- 配置和令牌文件权限为 600；
- 仓库不包含真实 secret、代理链接或 API 令牌。

## 主机级未自动修复项

实际 VPS 的 SSH 配置为：

- `PermitRootLogin yes`
- `PasswordAuthentication yes`
- `PubkeyAuthentication yes`
- `MaxAuthTries 6`

这允许公网直接尝试 root 密码登录，风险高于代理服务本身。安装器只输出警告，
不会自动修改 SSH 配置，以免在密钥尚未验证时锁死管理员。推荐流程是先添加并验证
SSH 公钥，再设置：

```text
PermitRootLogin prohibit-password
PasswordAuthentication no
```

此调整不属于一键安装脚本的自动操作范围。

## 剩余风险

- FakeTLS 只是流量伪装，不是真正的 TLS 内容加密；Telegram 消息仍由 Telegram
  自身协议保护。
- VPS 公网 IP 仍可能被主动探测或封锁，必要时需要更换 IP。
- root 用户和 VPS 服务商理论上可以读取代理配置和元数据。
- 管理令牌保存在 root 可读文件中，root 权限失守后令牌也会泄露。
- 安装脚本不会启用 UFW，避免破坏 VPS 上已有服务；主机级防火墙需要单独配置。
- 云厂商安全组无法由脚本自动识别，修改端口后仍需人工放行。

## 供应链措施

- Telemt 固定为 `3.5.14`；
- 同时固定 x86_64 和 ARM64 安装包 SHA-256；
- 下载使用 HTTPS、失败重试和 `curl --proto '=https'`；
- 不使用 `latest` 标签或未经校验的一键脚本；
- 安装前检查端口、系统和已有 Telemt，避免覆盖现有部署。
