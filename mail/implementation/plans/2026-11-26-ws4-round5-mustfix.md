# WS4 第五轮任务书：上线前必须修的两件事

> 派给这一轮的 agent 先读 [后端工作流转派说明](2026-11-25-backend-agent-common.md) 的第 1 节（怎么配合、上下文怎么省）和第 5 节（报告）。它的第 3 节是给控制面那三个工作流的写法；你这里 Go 代码只有运维代理一处。总计划在 [2026-11-25-agent-team-master.md](2026-11-25-agent-team-master.md) 的「WS4 邮件核心与编排」一节。

## 身份

- 工作流：WS4 邮件核心与编排，第五轮。前四轮把镜像、编排、三份文档、技术核对都做完了（分支 `feat/ws4-infra`，最后一个提交 `31f7f54`，工作区干净）。第四轮在**正式编排**上跑冒烟测试时查出两件必须在上线前解决的事，这一轮只做这两件：
  1. **按契约的权限渲染时，LMTP 投递会失败**（24 项冒烟里唯一没通过的一项）。
  2. **自动回复的 DKIM 签名验不过**（核对脚本的 F8.1b）。
- 工作目录：`/Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws4-infra`（worktree），分支 `feat/ws4-infra`。不合并 `main`，不推送。不改 `service-mail/`（控制面那一侧的问题写进报告）。
- 进度记录：`docs/verification/M1-技术核对.md` 末尾的「进度」表，每做完一步追加一行。

## 环境里要注意的

- 本机有两套编排在跑，**都不要动**：`ppbmail-e2e-*`（负责人的联调编排，正在用）和 `ppbmail-dev-*`（这一路的开发编排；你可以只读地用它的容器和日志）。别人的 `ppb-mysql` 等容器也不要碰。
- 你自己验证用的一次性容器、网络、卷，用独立的项目名和端口，用完删掉。正式编排的冒烟测试脚本 `deploy/scripts/formal-smoke.sh` 已经是这么做的，照它的来。
- 重新构建邮件核心镜像（`ppb-mail/mailcore:dev`）不会影响已经在跑的容器；但**不要重启或重建上面两套编排里的容器**。开发编排里的邮件核心容器还是旧镜像，你要验证新镜像就自己起一次性的。
- 本机代理会劫持回环地址的请求：跑 curl 之前清掉 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`。
- 上下文省着用——这一路前面有三位都是上下文过长中断的：命令输出落文件再看片段，每查清一步就写进进度表并提交。

## 要读的

- `deploy/docs/control-plane-contract.md`：第 1 节（身份、共享目录的属主和权限）、第 3 节（控制面渲染的文件）、第 10 节（已知限制，第一、二条就是这两件事的现状）。
- `docs/verification/M1-技术核对.md` 第 5 节最上面一条（LMTP）、F8.1b 的条目和 `docs/verification/evidence/checks/` 下 F 组的输出。
- `deploy/scripts/formal-smoke.sh` 和它用到的控制面替身（`deploy/compose/standin/`）；`deploy/compose/docker-compose.yml`。
- 镜像里 Dovecot 的配置：`deploy/images/mailcore/rootfs/etc/dovecot/`（`dovecot.conf`、`mailcore.conf`、`conf.d/`）、`90-quota.conf`、`90-sieve.conf`、配额字典那份配置的模板 `deploy/config/mail-config/dovecot-dict-sql.conf.ext.tmpl`，以及入口脚本 `deploy/images/mailcore/rootfs/entrypoint.sh`。

## 第一件：LMTP 投递失败

**已知的现象**：正式编排（权限位是真的）下，Dovecot 的配额字典进程以内部用户 `dovecot`（uid 101）运行，读不了 `/run/mail-config/dovecot-dict-sql.conf.ext`（契约要求 0640、属主 5000）。LMTP 对每一封邮件回 `451 4.3.0`，邮件留在队列里反复重试。开发编排上看不出来，因为 macOS 的目录挂载不按权限位做访问控制。

**上一轮试过的**：给 dict 服务加 `privileged_group = vmail`，冒烟测试里没解决，原因没查清；改动已还原、没提交。

**做法**（先把原因查实，再动手，不要凭猜测改配置）：

1. 在一次性的正式编排上复现。**拿到 Dovecot 日志里 dict 进程自己的那一行错误**（是读不了配置文件的 Permission denied，还是连不上 MySQL，还是别的）。上一轮的 `privileged_group` 没解决，很可能是真正的原因不是「读不了文件」，或者不止这一个原因。把那一行（去掉口令）记进核对文档。
2. 原因查实之后选一个修法，写明为什么不选别的。可选的方向（不限于）：
   - 让 dict 服务以虚拟用户 vmail 运行，并把它的套接字的属主、权限配对（ Dovecot 的虚拟用户部署里这是常见做法）；
   - 入口脚本（root）给字典进程留一份它读得了的副本（照 Postfix 那六个映射的做法：启动时复制、`reload.dovecot` 时再复制），Dovecot 的配额字典配置指向这份副本；
   - 改契约里这一个文件的属主或权限（它里面有字典账号的口令 `mail_dict`，只能读写那一张表；要说明放宽到谁能读、为什么可以）。
   选定之后，**契约文档、运维手册、Dovecot 配置三处一起改**，保持一致。如果修法改变了控制面要渲染的路径或权限，在报告里单列（控制面那一侧由负责人改）。
3. 顺带核对同一个坑有没有漏网的：邮件核心容器里以非 root 运行、又要读 `/run/mail-config/` 或 `/etc/mail-secrets/` 下文件的进程，逐个列出来，逐个确认读得到（上一轮已经给 Postfix 的 smtpd 做过证书副本）。把这张小表写进契约文档第 4 节。
4. 跑 `deploy/scripts/formal-smoke.sh`，这一项必须通过，整个脚本的退出码应当是 0。

## 第二件：自动回复的 DKIM 签名验不过（F8.1b）

**已知的现象**：核对脚本 F8.1b——自动回复邮件的 DKIM 签名，正文摘要（bh）对得上，头的签名（b）验不过。脚本本身的算法在普通邮件上是对的。原因没查。

**做法**：

1. 复现并定位。可以依次排除：
   - 签名之后有没有人改了被签名的头（自动回复是 Dovecot 的 Sieve 休假命令发的，走哪条路交给 Postfix？经过 Rspamd 的 milter 了吗？签名是谁加的、在哪一站加的，加完之后还有没有哪一站改写了 `From`、`To`、`Subject`、`Date`、`Message-ID` 这些被签名的头）；
   - 自动回复的头里有没有不规范的地方（编码过的显示名、过长的行、折叠的方式），让验证方和签名方算出来的头的规范形式不一样；
   - 验证脚本对这一类头处理得对不对（用一个独立的验证工具，比如 `rspamc` 或 `dkimpy` 的 `dkimverify`，对同一封邮件验一遍，看是脚本的问题还是邮件的问题）。
2. 找到原因：是控制面渲染的脚本的问题（比如休假命令带的参数）、邮件核心配置的问题（比如自动回复走的提交路径没做 DKIM 签名，或者签名后被改写）、还是核对脚本的问题——分别写清楚该由谁改。属于邮件核心的你来修；属于控制面的（Sieve 脚本的渲染）写进报告，给出确切的改法；属于核对脚本的改脚本。
3. 修完把 F8.1b 跑通，结论写进核对文档。查不清就把排除到哪一步、每一步看到了什么写清楚，结论留「未核对」，不要猜一个原因。

## 顺手的三件小事（前两轮报告里留下来的）

- 核对脚本的 F8.3「用户脚本转发」之前四次都没测到，原因上一轮查出来了（脚本自己写的 Sieve 规则里 `require ["redirect"]` 编译失败）。确认现在这一项真的测到了，并在契约文档第 3.9 节写一句：「`redirect` 是始终可用的命令，`require` 里不要列它，列了编译失败、邮件静默进收件箱」（控制面的渲染器已经只列 fileinto、imap4flags、vacation，这一句是给后来的人的）。
- `deploy/scripts/formal-smoke.sh` 在 Docker Desktop 上把 Rspamd 的数据目录换成了命名卷（macOS 目录挂载会让 Rspamd 4.3.0 段错误）。确认正式编排里它本来就是命名卷；如果本来就写对了，只在冒烟脚本的注释里说明这是本机验证专用的差别。
- 一个笔误：提交 `7c0f13e` 的提交说明里 `dovecd-dict-sql.conf.ext` 应为 `dovecot-…`。不用改历史，在进度表里记一笔就行。

## 完成标准

- LMTP 投递在正式编排的冒烟测试里通过；整个冒烟脚本退出码 0，证据落 `docs/verification/evidence/deploy-formal-compose-smoke.txt`。
- 邮件核心容器里非 root 运行、要读控制面渲染的文件的进程，有一张逐一确认过的表。
- F8.1b 要么查清并修掉，要么结论写明排除到了哪一步。
- 契约文档、运维手册、Dovecot 配置三处口径一致；核对文档的结论表和第 5 节同步更新。
- 运维代理的测试（含 `-race`）仍然通过；镜像构建成功。
- 没碰 `ppbmail-dev-*`、`ppbmail-e2e-*` 和别人的容器；自己起的一次性东西都删了。
- 提交都在 `feat/ws4-infra` 上，工作区干净。不要用 Agent 工具再派子 agent。

## 报告

按共用说明第 5 节。另外单列：LMTP 那件事真正的原因和你选的修法（以及不选别的的理由）、它对控制面有没有要求；F8.1b 的原因和归属；留给负责人定的事。
