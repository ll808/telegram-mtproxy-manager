# Telegram MTProxy 多用户管理

面向 Ubuntu/Debian VPS 的 Telegram MTProto 代理部署项目。它使用
[Telemt](https://github.com/telemt/telemt) 提供 FakeTLS 和多用户支持，
并通过 `tgctl` 管理用户、认证和端口。

## 功能

- 每个用户拥有独立 secret，可单独新增、轮换、停用、启用和删除；
- 修改端口时自动备份配置、重启服务并检查结果；
- 本机管理 API 使用随机 Bearer 令牌；
- systemd 服务以非 root 用户运行，并启用严格沙箱；
- Telemt 版本和 x86_64/ARM64 安装包 SHA-256 固定；
- 不包含真实 secret，不在安装日志中输出用户认证；
- 提供交互菜单、状态、日志和用户流量查看。

## 当前限制

- 只支持 Ubuntu/Debian 和 IPv4 公网地址；
- 安装脚本不会自动修改云厂商安全组；
- 脚本不会自动启用 UFW，避免阻断 VPS 上的其他服务；
- FakeTLS 是流量伪装，不等于 VPN，也不会替代 Telegram 自身的加密机制。

## 安装

仓库首次上传后，将本文件中的 `OWNER/REPO` 替换为实际 GitHub 路径，并将
`install.sh` 中的 `REPO_RAW_BASE` 同步替换。

从本地项目目录安装：

```bash
sudo bash install.sh --port 443 --domain www.bing.com
```

从 GitHub 一行安装：

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | sudo bash -s -- --port 443 --domain www.bing.com
```

如果 443 已被占用：

```bash
sudo bash install.sh --port 2053 --domain www.bing.com
```

可选参数：

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `--port` | MTProxy TCP 端口 | `443` |
| `--api-port` | 本机管理 API 端口 | `19091` |
| `--domain` | FakeTLS 伪装域名 | `www.bing.com` |
| `--user` | 初始用户名 | `owner` |
| `--public-host` | 客户端连接使用的公网 IPv4 | 自动识别 |
| `--no-start` | 安装但不启动服务 | 不启用 |

安装前脚本会检查系统、依赖、端口占用、伪装域名可达性和已有 Telemt 安装。
公网 IP、端口和域名需按实际环境调整。

## 管理

运行交互菜单：

```bash
tgctl
```

常用命令：

```bash
tgctl status
tgctl users
tgctl link [用户名]
tgctl add <用户名>
tgctl rotate <用户名>
tgctl enable <用户名>
tgctl disable <用户名>
tgctl delete <用户名>
tgctl port <端口>
tgctl restart
tgctl logs [行数]
```

管理命令必须由 root 执行。连接链接包含 secret，只应发送给对应用户。

## 升级与卸载

升级脚本固定为项目声明的 Telemt 版本，并在启动失败时恢复旧二进制：

```bash
sudo bash update.sh
```

移除服务但保留配置和 secret：

```bash
sudo bash uninstall.sh
```

彻底删除服务、二进制、配置和用户：

```bash
sudo bash uninstall.sh --purge
```

`--purge` 会要求输入 `PURGE` 确认。

## 文件位置

| 路径 | 用途 |
| --- | --- |
| `/usr/local/bin/telemt` | Telemt 二进制 |
| `/usr/local/sbin/tgctl` | 管理命令 |
| `/etc/telemt/telemt.toml` | 服务配置和用户 secret |
| `/etc/telemt/api.token` | 管理 API 令牌 |
| `/etc/telemt/backups` | 端口变更备份 |
| `/etc/systemd/system/telemt.service` | systemd 服务 |
| `/root/tg-proxy-owner.link` | 安装时生成的初始用户链接 |

配置和令牌权限为 600，备份目录权限为 700。备份只保留最近 5 份。

## 安全说明

- 不要把 `/etc/telemt`、`api.token` 或代理链接提交到公开仓库；
- 不要将 `19091` 管理端口绑定到公网；
- 如果链接泄露，立即运行 `tgctl rotate <用户名>`；
- 修改端口后同步更新客户端和云安全组；
- 若 SSH 仍允许 root 密码登录，应先配置并验证密钥登录，再关闭密码认证；
- VPS 公网 IP 仍可能被主动探测或封锁。

更完整的审查记录见 [docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md)，操作说明见
[TG代理多用户管理操作说明.md](TG代理多用户管理操作说明.md)。

## 开发检查

```bash
shellcheck -x install.sh update.sh uninstall.sh tgctl
bash -n install.sh update.sh uninstall.sh tgctl
```

GitHub Actions 会在推送和合并请求中运行相同检查。

## 第三方软件

本项目不包含 Telemt 二进制。安装器从 Telemt 官方 GitHub Release 下载固定版本，
并按项目内置 SHA-256 校验。Telemt 的代码和分发包适用其仓库中的许可证。
