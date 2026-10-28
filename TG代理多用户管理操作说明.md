# Telegram 代理多用户管理操作说明

**适用环境：** RackNerd VPS、Ubuntu 22.04、Telemt 3.5.14、tgctl
**文档日期：** 2026-10-28
**文档版本：** 1.1
**文档用途：** 说明当前 Telegram MTProto 代理的日常使用、多用户管理、端口变更、安全检查与故障恢复方法。

## 文档范围

本文档面向 VPS 管理员。管理员应通过 SSH 登录服务器，并使用 root 权限运行
`tgctl`。文档不包含真实 secret 或可直接用于连接的代理链接。

当前代理使用 FakeTLS 模式，仅允许 TLS 传输。每个用户拥有独立 secret，可以在不
影响其他用户的情况下新增、停用、启用、删除或轮换认证。

## 当前部署概览

| 项目 | 当前值 |
| --- | --- |
| VPS 公网 IPv4 | 安装时自动识别，可用 `tgctl status` 查看 |
| 操作系统 | Ubuntu 22.04 |
| 代理后端 | Telemt 3.5.14 |
| MTProto 端口 | `2053/TCP` |
| FakeTLS 伪装域名 | `www.bing.com` |
| 管理命令 | `/usr/local/sbin/tgctl` |
| 管理 API | `127.0.0.1:19091`，仅本机访问 |
| API 认证 | Bearer 令牌，保存在 `/etc/telemt/api.token` |
| 服务名称 | `telemt.service` |
| 服务用户 | `telemt` |
| 配置文件 | `/etc/telemt/telemt.toml` |
| 配置备份目录 | `/etc/telemt/backups` |

公网 IP、端口和伪装域名可能随部署调整而变化。执行 `tgctl status` 可以查看服务、
端口和用户数量的当前状态。

## 系统结构

客户端连接 `VPS_PUBLIC_IP:2053`，使用与用户对应的 FakeTLS secret。Telemt 验证
连接并转发至 Telegram。管理操作通过本机 API 完成，公网不开放管理端口。

管理员使用 `tgctl` 发出本地 API 请求。请求必须携带 `/etc/telemt/api.token` 中的
Bearer 令牌。Telemt 将用户配置写入 TOML 文件，并同步更新运行状态。新增用户、
轮换认证、停用和删除操作不要求重启整个代理服务；修改监听端口时，`tgctl` 会备份
配置并重启服务完成切换。

## 首次登录和打开菜单

通过 SSH 登录 VPS 后，确认当前用户为 root：

```bash
id
```

运行管理菜单：

```bash
tgctl
```

菜单选项如下：

| 选项 | 功能 |
| --- | --- |
| 1 | 查看服务、端口和用户数量 |
| 2 | 查看用户、连接数和累计流量 |
| 3 | 查看一个或全部用户的连接链接 |
| 4 | 新增用户 |
| 5 | 轮换某个用户的认证 |
| 6 | 启用或停用用户 |
| 7 | 删除用户 |
| 8 | 修改代理端口 |
| 9 | 重启服务 |
| 10 | 查看 systemd 日志 |
| 0 | 退出菜单 |

菜单会持续显示，完成一项操作后自动返回主菜单。

## 查看运行状态

命令行方式：

```bash
tgctl status
```

正常输出应包含以下信息：

```text
服务：运行中
对外端口：2053（正在监听）
用户数量：2
版本：telemt 3.5.14
```

如果服务停止或管理 API 不可用，先查看日志：

```bash
tgctl logs 120
```

## 查看用户和流量

执行：

```bash
tgctl users
```

列表包含用户名、启用状态、当前连接数和累计流量。连接数反映当前活动 TCP
连接；累计流量在 Telemt 运行期间统计。

用户数据应从当前系统读取，不应仅依赖本文档。执行以下命令可以确认当前用户列表：

```bash
tgctl users
```

## 新增用户

新增用户会生成独立 secret。该用户的连接链接不会影响其他用户。

菜单方式：

1. 运行 `tgctl`。
2. 输入 `4`。
3. 输入用户名，例如 `alice`。
4. 复制生成的 FakeTLS 链接。
5. 只将链接发送给 alice。

命令行方式：

```bash
tgctl add alice
```

用户名只能使用字母、数字、点、下划线和短横线，长度为 1 到 64 个字符。

新增完成后，用以下命令确认：

```bash
tgctl users
```

不要把链接发到公开群组、论坛、代码仓库或截图中。链接中的 secret 等同于该用户
的代理密码。

## 查看连接链接

查看全部用户：

```bash
tgctl link
```

查看指定用户：

```bash
tgctl link alice
```

输出中的 FakeTLS 链接可以通过 Telegram 打开并自动添加代理。链接包含 secret，
命令输出应与用户身份对应，避免发错人。

## 轮换用户认证

轮换后，该用户的旧 secret 立即失效，活动会话被撤销。其他用户不受影响。

菜单方式：

1. 运行 `tgctl`。
2. 输入 `5`。
3. 输入用户名。
4. 将新链接发送给该用户。

命令行方式：

```bash
tgctl rotate alice
```

以下情况应立即轮换认证：

- 链接被误发到群组或公开页面；
- 用户设备丢失或账号被他人控制；
- 发现异常连接或异常流量；
- 用户主动要求更换认证。

## 停用和重新启用用户

临时停用用户：

```bash
tgctl disable alice
```

停用会阻止该用户建立新连接，并关闭其现有活动会话。其他用户继续使用代理。

重新启用：

```bash
tgctl enable alice
```

启用后可以继续使用原链接；如果认证已经泄露，应先执行 `tgctl rotate alice`，
再发送新链接。

## 删除用户

菜单方式：

1. 运行 `tgctl`。
2. 输入 `7`。
3. 输入用户名。
4. 输入 `yes` 确认。

命令行方式：

```bash
tgctl delete alice
```

命令会再次要求确认。删除后，该用户的配置和活动会话会被撤销。删除 `owner`
需要输入大写 `DELETE`，防止误操作主用户。

## 修改代理端口

修改端口前，先确认新端口未被其他程序使用，并确认云厂商安全组允许该端口。当前
系统 UFW 未启用，因此不要直接执行 `ufw enable`，否则可能阻断现有 nginx 和
sing-box 服务。

菜单方式：

1. 运行 `tgctl`。
2. 输入 `8`。
3. 输入 1024 到 65535 之间的端口。

命令行方式：

```bash
tgctl port 2087
```

`tgctl` 会完成以下检查和处理：

1. 检查端口是否已被占用；
2. 在 `/etc/telemt/backups` 中保存一份权限为 600 的配置备份；
3. 通过本机管理 API 更新监听器和连接链接端口；
4. 如果系统防火墙已启用，添加新端口规则；
5. 重启 Telemt；
6. 检查新端口是否实际监听；
7. 启动失败时恢复备份并重启旧配置。

切换成功后，所有用户都需要把客户端中的端口改成新端口。旧端口会立即关闭。
如果使用云厂商安全组，还需要在控制台手动放行新端口。

验证端口：

```bash
tgctl status
ss -lntp | grep ':新端口'
```

将命令中的“新端口”替换为实际数字。

## 重启服务

用户配置操作通常不需要重启。仅在修改 systemd、二进制或需要恢复异常状态时重启：

```bash
tgctl restart
```

也可以使用 systemd：

```bash
systemctl restart telemt
```

重启后执行：

```bash
tgctl status
```

## 查看日志

查看最近 80 行：

```bash
tgctl logs
```

查看最近 200 行：

```bash
tgctl logs 200
```

直接使用 journalctl：

```bash
journalctl -u telemt -n 200 --no-pager
```

日志中不应出现用户完整 secret。如果发现 secret 被写入聊天、日志或公开文件，
应立即轮换对应用户的认证。

## 安全规则

代理链接等同密码。配置文件和备份目录只允许 root 读取。执行以下命令检查权限：

```bash
ls -ld /etc/telemt /etc/telemt/backups
ls -l /etc/telemt/telemt.toml /etc/telemt/api.token
```

配置文件和备份应为 `600`，目录应为 root 可访问的受限目录。

管理 API 只监听 `127.0.0.1:19091`，并且要求随机 Bearer 令牌。不要将其绑定到
公网地址，不要在云防火墙开放 19091，也不要复制或提交 api.token 文件。

验证无令牌请求已被拒绝：

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:19091/v1/users
```

应返回 `401`。systemd 服务使用非 root 用户运行，仅保留低端口绑定能力，并启用了
设备和内核隔离。当前 `systemd-analyze security telemt.service` 暴露评分为
`1.6 OK`。

端口修改产生的备份包含完整用户配置，备份目录权限为 700、文件权限为 600；
`tgctl` 只保留最近 5 份备份。

建议定期执行：

```bash
tgctl status
tgctl users
tgctl logs 120
```

发现陌生用户名、异常连接数或无法解释的流量时，先停用可疑用户，再轮换认证并检查
VPS 登录记录。

执行以下只读命令检查 SSH：

```bash
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication) '
```

如果 `permitrootlogin yes` 且 `passwordauthentication yes` 同时存在，应先添加并
验证 SSH 公钥。确认密钥登录正常后，再将 root 登录改为 `prohibit-password` 并
关闭密码认证。不要在没有备用登录方式时直接修改 SSH。

WhatsApp 代理与 Telegram MTProto 是两套独立服务。WhatsApp 的端口、聊天和影音
设置不能使用 Telemt 的 secret，Telegram 链接也不能用于 WhatsApp。

## 故障排查

| 现象 | 优先检查 | 处理方法 |
| --- | --- | --- |
| `tgctl` 提示 API 无法连接 | 服务是否运行、19091 是否监听 | 执行 `systemctl status telemt` 和 `tgctl logs` |
| 客户端突然无法连接 | 当前端口、服务状态、用户是否停用 | 执行 `tgctl status` 和 `tgctl users` |
| 新用户无法连接 | 是否使用了正确用户链接、端口是否一致 | 执行 `tgctl link 用户名`，重新发送对应链接 |
| 修改端口后无法连接 | 云安全组、客户端端口、新端口是否监听 | 执行 `tgctl status`，更新客户端端口 |
| 新端口已被占用 | `ss -lntp` 中的占用进程 | 停止切换，选择其他空闲端口 |
| 端口切换失败 | 配置备份和 Telemt 日志 | `tgctl` 会尝试恢复；必要时手动恢复备份 |
| 服务启动失败 | TOML 配置、文件权限、端口冲突 | 查看 journalctl，恢复最近备份 |
| 用户认证疑遭泄露 | 用户连接和流量 | 立即执行 `tgctl rotate 用户名` |

## 紧急恢复

先检查服务：

```bash
systemctl status telemt --no-pager
journalctl -u telemt -n 200 --no-pager
```

查看端口：

```bash
ss -lntp | grep ':2053'
```

查看备份：

```bash
ls -lt /etc/telemt/backups
```

如果确认最近一次端口修改导致故障，可在 `tgctl port` 自动回滚失败后，由管理员
恢复指定备份：

```bash
cp -a /etc/telemt/backups/备份文件名 /etc/telemt/telemt.toml
chown telemt:telemt /etc/telemt/telemt.toml
chmod 600 /etc/telemt/telemt.toml
systemctl restart telemt
```

恢复前必须确认备份文件名，不要批量覆盖目录中的全部文件。

旧 `mtg` Docker 容器仍保留在系统中但处于停止状态。只有在 Telemt 完全不可用、
需要恢复旧版单用户代理时，才考虑停止 Telemt 后启动旧容器：

```bash
systemctl stop telemt
docker start mtg
```

旧容器只包含迁移前的单用户认证，不包含后续新增用户。恢复旧容器前应确认端口
冲突和回退范围。

## 日常检查清单

- `tgctl status` 显示运行中，端口正在监听；
- 用户列表中没有陌生或多余账号；
- 用户连接数和流量处于合理范围；
- 日志没有持续报错或异常登录；
- 配置与备份权限未被意外放宽；
- 云厂商安全组没有开放管理 API 端口；
- 失效用户的认证已停用或轮换；
- 修改端口后，管理员已同步通知所有用户。

## 快捷命令汇总

| 目的 | 命令 |
| --- | --- |
| 打开菜单 | `tgctl` |
| 查看状态 | `tgctl status` |
| 用户列表 | `tgctl users` |
| 查看全部链接 | `tgctl link` |
| 查看指定链接 | `tgctl link alice` |
| 新增用户 | `tgctl add alice` |
| 轮换认证 | `tgctl rotate alice` |
| 启用用户 | `tgctl enable alice` |
| 停用用户 | `tgctl disable alice` |
| 删除用户 | `tgctl delete alice` |
| 修改端口 | `tgctl port 2087` |
| 重启服务 | `tgctl restart` |
| 查看日志 | `tgctl logs 200` |

每次操作完成后至少确认三项：`tgctl status` 显示服务运行且端口正在监听；变更用户
能够使用与本人对应的最新链接连接 Telegram；其他用户仍能正常收发消息，未受到误操作
影响。
