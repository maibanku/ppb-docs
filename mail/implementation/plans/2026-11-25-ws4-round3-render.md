# WS4 第三轮任务书：控制面的配置渲染

> 派给这一轮的 agent 先读 [后端工作流转派说明](2026-11-25-backend-agent-common.md)（全文），再读 `ppb-mail-ws/ws4c-render/deploy/docs/control-plane-contract.md`（邮件核心对控制面的全部要求，是这一轮的权威依据）。

## 身份

- 工作流：WS4 邮件核心与编排的后续——**控制面按模板渲染 Postfix、Dovecot、Rspamd 的配置**（总计划里「WS4 之后还有一步」）。这是邮件核心能真正跑起来的前提：没有这些文件，邮件核心的入口脚本会一直等。
- 工作目录：`/Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws4c-render`（worktree），分支 `feat/ws4c-render`。它从 `main` 的 265f025 拉出来，已经合进了邮件核心分支 `feat/ws4-infra` 的现状（有 `deploy/` 和契约文档）。服务模块在它下面的 `service-mail/`。
- 进度文件：`service-mail/docs/implementation/progress-render.md`（新建，跟着代码提交）。

## 能改的路径

- `service-mail/internal/render/`（新建，连同它内嵌的 `templates/`）。
- `service-mail/cmd/server/wire_render.go`。
- `service-mail/internal/platform/argon2id/`（共享的口令哈希，见第 2 块）。
- `service-mail/internal/config/` 和 `env/`：只加这一轮缺的配置项（下面第 1 块列了），照现有的写法加测试。
- `service-mail/internal/transport/mail/` 根包：只有 `/ping` 的时序确实需要时才动，动了在报告里单列。

不动：`deploy/` 下的任何文件（模板和契约文档只读；要改模板告诉负责人）、契约、`internal/maildomain`、`internal/blocklist`、`internal/mailconf`（只读它们的模型、登记表和接口）、别人的包。

## 要读的

1. `deploy/docs/control-plane-contract.md` 全文（三百多行）。第 0 节是一页速查，第 2、3、6 节最要紧。
2. 模板：`deploy/config/mail-config/*.tmpl`、两个 `.example`，`deploy/config/rspamd/local.d-examples/`。`deploy/scripts/dev-prepare.sh` 里的 `render` 函数是开发环境的渲染逻辑（把 `{{变量}}` 换成值，先写临时文件再改名，权限 0640）——**你的渲染结果要和它对同样的输入产出逐字相同的内容**。
3. 邮件核心的入口脚本 `deploy/images/mailcore/rootfs/entrypoint.sh`：它等哪些文件出现才启动 Postfix 和 Dovecot、启动时读哪些文件。你启动时渲染的集合必须是它的超集。
4. 接线计划 `service-mail/docs/implementation/wiring-plan.md` 的第 3 节（接缝和钩子）、第 5 节（接口 12、13、14：DKIMRenderer、WhitelistRenderer、SettingsApplier，签名在 `internal/maildomain/ports.go`、`internal/blocklist/ports.go`、`internal/mailconf/ports.go`）。
5. 设计（在 `/Users/pipi-ban/Desktop/code/vscode/ppb-docs/mail/`）：`tech/10-部署与运维.md` 第 3 节（启动顺序）、第 5 节（控制面启动时渲染的文件）、第 4.3 节；`tech/07-管理端设计.md` 第 9.3 节（DKIM 密钥目录）、第 10 节（黑白名单的生效）、第 11 节（全局设置每项的生效方式）。
6. `internal/mailconf/spec.go`（设置项的键和取值）、`internal/maildomain/model`（`Domain`、`DomainDKIMKey`）、`internal/blocklist/model`（`Blocklist` 的 `ListType`、`BlockType`、`BlockValue`）。

## 任务块（按顺序做，每块做完提交一次）

### 1. 配置项

在 `internal/config` 里加或改下面几项，两份环境文件同步，每项配正控和负控：

| 键 | 缺省 | 说明 |
|---|---|---|
| `mail.rspamd_local_dir` | `/etc/rspamd/local.d` | **现在的缺省是 `/etc/rspamd/local`，是错的**：官方镜像读的本地覆盖目录是 `local.d`（契约文档 T10-2）。改缺省、改两份环境文件、改断言它的测试 |
| `mail.mail_config_dir` | `/run/mail-config` | 渲染 Postfix 和 Dovecot 数据库配置的目录（契约 3.1 到 3.5） |
| `mail.master_users_file` | `/etc/mail-secrets/master/users` | Dovecot 主账号的口令文件（契约 3.6） |
| `mail.master_allow_nets` | 空 | 主账号允许登录的网段，写进 `allow_nets`。一个地址或 CIDR，例如 `172.30.0.10/32`。**生产环境必填**（生产门禁），开发环境可以留空 |
| `mail.cert_files` | `["fullchain.pem", "privkey.pem"]` | `tls_dir` 下证书和私钥的文件名，证书变化检查用（契约第 6 节） |

路径类的键照现有的规则校验（绝对路径）。

### 2. 口令哈希的共享包 `internal/platform/argon2id`

主账号的口令文件要写 Argon2id 哈希，账号的口令也是同一种格式，两边用同一份实现。另一个工作流（账号与域名，worktree `ppb-mail-ws/ws1-be-admin`）正在写这个包，接口和测试向量是负责人定的：

```go
package argon2id
func Hash(plain string) (encoded string, err error)   // 随机盐
func Verify(encoded, plain string) bool
// 另加一个接收盐的入口（导出的 HashWithSalt，或包内测试可用的写法），让测试能算出固定的串
```

- 格式：`{ARGON2ID}$argon2id$v=19$m=19456,t=2,p=1$<盐>$<摘要>`；内存 19456 KiB、2 轮、并行度 1；盐 16 字节、摘要 32 字节；base64 用不带填充的标准字母表。
- 测试向量：盐取 `SHA-256("ppb-mail argon2id test vector salt")` 的前 16 字节，口令 `throwaway-check-password`（一次性的检查串），期望
  `{ARGON2ID}$argon2id$v=19$m=19456,t=2,p=1$jNMPuIhhk0rqHqoWBXOcaA$rBHh+0BM3bxQGxDxfacRpvxlrgdDZvMNy7b+3+jzGqQ`
  （负责人在邮件核心镜像 `ppb-mail/mailcore:dev` 里用 `doveadm pw -t` 验过：这一串能通过，换口令报 `Password mismatch`）。

**怎么拿到这个包**：开工时看 `git -C /Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws1-be-admin log --oneline -- service-mail/internal/platform/argon2id`。已经提交了，就从那个提交里把整个目录原样取过来（`git -C … show <提交>:service-mail/internal/platform/argon2id/<文件>`），不要改它；在进度文件里记下来源提交。还没提交，就先做第 3 到第 7 块，最后回头做用到它的那一部分；到时候还没提交，就照上面的接口和向量自己写一份（合并时负责人去重）。

### 3. 模板内嵌和同步测试

- 把 `deploy/config/mail-config/` 下的模板和两个样例、`deploy/config/rspamd/local.d-examples/` 下的样例拷进 `service-mail/internal/render/templates/`，用 `go:embed` 内嵌（镜像的构建上下文只有二进制，运行时读不到 `deploy/`）。
- 加一个同步测试：内嵌的每一份和 `deploy/` 下的原件逐字节相同；`deploy/` 那边多出或少了文件也报。任何一边改了模板、另一边没跟上，测试就红。
- 渲染就是字符串替换，变量名和 `dev-prepare.sh` 的 `render` 函数一致。**值里出现模板分隔符或换行要拒绝或转义**，不能悄悄写坏文件（口令里可能有各种字符：Postfix 的 `mysql_table` 配置里口令那一行怎么写特殊字符，去查 `mysql_table(5)` 的说明，按它来，并写进测试）。

### 4. 启动时渲染（接缝的 `Startup` 钩子，监听之前做完）

全部照契约第 3 节。**每个文件都是：先写同目录下的临时文件、设好权限、再改名覆盖**；写不进去（目录不存在、没权限）就让启动失败，错误里点名是哪个目录、应当是什么属主，不要带着残缺的配置去监听。

| 文件 | 内容 | 权限 |
|---|---|---|
| `mail_config_dir/postfix-{domain,mailbox,alias,sender,recipient-policy,blocklist}.cf` | 六个映射。主机、端口、库名从控制面自己的连接串里解析（用 MySQL 驱动自带的 DSN 解析，不要自己切字符串；连 MySQL 走 `inet:<主机>:<端口>`），只读账号的口令取环境变量 `MAIL_DB_READER_PASSWORD` | 0640 |
| `mail_config_dir/dovecot-sql.conf.ext` | 查账号，只读账号 | 0640 |
| `mail_config_dir/dovecot-dict-sql.conf.ext` | 读写配额用量，字典账号的口令取 `MAIL_DB_DICT_PASSWORD` | 0640 |
| `mail_config_dir/cleanup-retention.conf` | 已删除和垃圾邮件的保留期，取全局设置 | 0640 |
| `mail_config_dir/postfix-settings.cf` | 见下 | 0640 |
| `mail_config_dir/dovecot-local.conf` | POP3 开着写 `protocols = imap lmtp pop3`，关着写 `protocols = imap lmtp` | 0640 |
| `master_users_file` | 一行：`<主账号用户名>:<哈希>::::::allow_nets=<网段>`。哈希用 `argon2id.Hash` 算 `MAIL_IMAP_MASTER_PASSWORD`；用户名是 `imap_master_user`；`master_allow_nets` 为空时去掉 `allow_nets` 那一段 | **0400** |
| `rspamd_local_dir/actions.conf` | 三个阈值；灰名单关着写 `greylist = null;`。**直接写各项，不套小节名** | 0644 |
| `rspamd_local_dir/dkim_signing.conf` | 每个域用哪个选择器、私钥在哪（见第 5 块） | 0644 |
| `rspamd_local_dir/whitelist.inc` | 白名单（见第 5 块） | 0644 |

`postfix-settings.cf`：只能写白名单里的 5 个参数，取值是非负整数。`message_size_limit` 取 `max_message_bytes`，`smtpd_recipient_limit` 取 `max_recipients_client`；三个频率上限（`smtpd_client_connection_rate_limit`、`smtpd_client_auth_rate_limit`、`smtpd_client_message_rate_limit`）全局设置里没有对应的项，用样例文件里的 30、20、50 当常量，写在一处并注明来源。文件里带注释行是可以的（样例就是带注释的；以邮件核心解析它的代码为准，去看 `deploy/images/mailcore/mailops` 里 `reload.postfix` 读这个文件的那段）。

`/ping`：契约要求它在这批文件渲染完之后才应答（邮件核心拿它当启动条件）。确认骨架的启动顺序是「启动钩子 → 监听」，写一条测试钉住：启动钩子没跑完时端口还没开。

**开发环境专有的文件不要渲染**：契约第 9 节说了开发编排里有一份 `rspamd-local/settings.conf`（按邮件头 `X-Dev-Action` 定处置），正式环境没有，控制面不要碰。

### 5. 运行期的三个接口

都定义在用的一方（骨架已经写好签名），你在这个包里实现，在接缝里发布到 `deps.X.Render`：

- **`RenderDKIM`**：读域表和 DKIM 密钥表（状态正常的域、没删的密钥；轮换期间新旧选择器都列），重写 `dkim_signing.conf`。表里的 `dkim_key_path` 是相对密钥目录的路径，渲染时换成容器里的绝对路径（`dkim_dir` 加它）。域和选择器要先校验：只允许域名和选择器的合法字符，防止写坏 Rspamd 的配置。
- **`RenderWhitelist`**：读白名单（`ListType` 是白名单的那些行），每行一个，重写 `whitelist.inc`。改完就生效，不用重载。
- **`Apply`**（`mailconf.SettingsApplier`）：按改了哪些键决定做什么，返回告警，不让保存失败：

| 改了的键 | 做什么 |
|---|---|
| `max_message_bytes`、`max_recipients_client` | 重写 `postfix-settings.cf`，调 `reload.postfix` |
| `pop3_enabled` | 重写 `dovecot-local.conf`，调 `reload.dovecot`；告警里说明 110、995 端口要由编排发布（重建邮件核心容器） |
| `trash_retention_days`、`junk_retention_days` | 重写 `cleanup-retention.conf`，不用重载 |
| `spam_reject_score`、`spam_junk_score`、`spam_greylist_score`、`greylist_enabled` | 重写 `actions.conf`，再让 Rspamd 在线生效（`POST /saveactions`） |
| `antivirus_enabled` | 打开时写 `antivirus.conf`，关闭时删掉它；要不要让 Rspamd 重读见下 |
| 别的键 | 什么都不做 |

重载要经运维代理，Rspamd 的控制接口也是。提供方在投递与运维那一轮（`internal/platform/mailops`、`internal/platform/rspamd`），**还没合进这个分支**。所以在本包的 `ports.go` 里定义两个窄接口（`Reloader`：`ReloadPostfix`、`ReloadDovecot`；`RspamdActions`：在线改阈值的那一个方法），接缝里先接空实现：**为空时照常渲染文件，返回一条告警**说明「已写入，需要重载组件才生效」。集成时负责人把真的实现接上。

Rspamd 的一个硬限制（契约第 3.8、6、10 节）：`dkim_signing.conf` 和 `antivirus.conf` 改了之后要给 Rspamd 的主进程发 HUP 才生效，控制面做不了。所以 `RenderDKIM` 写完文件要记一条告警日志（「需要给 Rspamd 发 HUP」），不要返回错误（数据没错，只是还没生效）。

### 6. 证书变化检查

每 10 分钟一次（接缝的 `Jobs`）：读 `tls_dir` 下证书和私钥文件，算摘要，和上次记下的比。变了就**先**调 `reload.postfix`（运维代理的那条命令会先核对证书和私钥是一对），**成功之后**再调 `reload.dovecot`。`reload.postfix` 失败时不要把新摘要记成「已处理」，下一次检查到变化再来（证书客户端可能正写到一半）。摘要和上次处理的时间只放进程内存，重启后第一次见到证书就当成一次变化，做一次重载。`Reloader` 为空时只记日志。

### 7. 接缝

`wire_render.go`：构造渲染器，发布 `deps.X.Render`（同时满足上面三个接口，有编译期断言），登记启动钩子、证书检查任务；往 `/healthz` 加一项「上次渲染是否成功」。接缝的执行顺序骨架已经定了：配置渲染排在账号与域名、投递与运维、成员邮箱之前。

### 8. 真实验证（强烈建议，做不了要写明卡在哪）

本机有邮件核心镜像 `ppb-mail/mailcore:dev` 和开发编排。至少做这一步：把控制面渲染出来的六个 Postfix 映射、两个 Dovecot 配置和 `dev-prepare.sh` 对同样输入渲染出来的文件逐字节比对（临时目录里跑 `dev-prepare.sh` 的那段逻辑，或者直接拿开发编排 `.state/mail-config/` 下的现成文件，注意口令不同）。再进一步的（起一个一次性的容器，把渲染结果挂给 Postfix 用 `postconf -M`/实际查询验证）做得了就做，做不了写明。

## 完成标准

- `GOWORK=off go build ./... && go vet ./... && go test ./...` 全绿，`gofmt -l .` 没有输出。
- 契约第 3 节列的文件（除用户 Sieve 脚本，那是成员邮箱那一轮的）启动时全部渲染出来，权限位对，原子写入有测试。
- 内嵌模板和 `deploy/` 的原件有同步测试。
- 日志、错误信息、`Summary()` 里不出现任何口令、私钥、连接串（有测试扫过渲染器的日志输出和写出来的文件以外的所有输出）。
- `argon2id` 的测试向量通过。
- 没改 `deploy/` 下的文件。
