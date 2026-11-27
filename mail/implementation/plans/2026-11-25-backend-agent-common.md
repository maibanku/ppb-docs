# 后端工作流转派说明（三个后端工作流共用）

> 2026-11-25 由负责人（主会话）写。派给 WS1、WS2、WS3 的每个 agent 先读完本文，再读自己那一轮的任务书。
> 总计划在 [2026-11-25-agent-team-master.md](2026-11-25-agent-team-master.md)（「全局约束」「评审时重点看」两节对每个工作流都有效）；骨架的装配和接口在 `ppb-mail/service-mail/docs/implementation/wiring-plan.md`。

## 1. 你是谁、怎么配合

- 你是 agent 团队里负责一个后端工作流**其中一轮**的成员。负责人在同时协调多个工作流，每个工作流分两轮，每轮一个 agent。你只做任务书里这一轮的事。
- 三个工作流各在自己的 worktree 和分支上，同时进行，**只改自己名下的路径**（接线计划第 2 节的归属表）。别人的包还没做出来时，你用到的那一侧是空指针，按接线计划第 5 节处理：判空，返回 MAIL-3003，不替别人实现。
- 你的上下文有限，上一批已经有两个 agent 因为上下文过长被中断。所以：
  - **读文件取片段**：大文件先 `grep -n` 定位，再 `sed -n '起,止p'`。`contracts-mail/proto/mail.proto` 有两千多行，只看你用到的那几条消息和 RPC 注释。设计文档只读任务书点名的节。
  - **命令输出落文件**：`go test ./... > /tmp/你的工作流-test.log 2>&1; tail -20 …`，失败时再 `grep`。不要把整份测试输出读进上下文。
  - **小块提交**：做完一个任务块就提交、更新进度文件。
  - **进度文件是给下一个 agent 看的**：`service-mail/docs/implementation/progress-<工作流>.md`（WS1 是 `progress-ws1.md`，依此类推），跟着代码提交。每完成一块追加一行：做了什么、提交短哈希、还没做的、留下的判断。上下文丢了先读它。
  - **做不完就交棒**：任务书里的任务块按顺序做。如果剩下的还很多、你已经做了大量工作，不要硬撑：把进度文件写清楚（做到哪、下一步做什么、试过什么），提交，然后在报告里写「未完成，交棒」。负责人会派下一个 agent 接着做。把没做完的写成做完是最糟的结果。

## 2. 环境

```bash
export PATH=/Users/pipi-ban/sdk/go1.26.0/bin:/Users/pipi-ban/go/bin:$PATH
export GOWORK=off GOPRIVATE='github.com/maibanku/*,github.com/ppbchat/*'
cd /Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/<你的工作流>/service-mail
GOWORK=off go build ./... && GOWORK=off go vet ./... && GOWORK=off go test ./...
gofmt -l .        # 应当没有输出
```

- 基线：`main` 的 787e37e 上（骨架 92d3c22 加一处契约修正），骨架在 92d3c22 上构建、vet、测试全过（30 个包有测试，11 个包只有说明或模型），`gofmt -l` 没有输出。你接手时先跑一遍确认基线是绿的，不是绿的先告诉负责人。
- `go.mod` 里第三方库已经加齐（IMAP 客户端 `github.com/emersion/go-imap` v1.2.1、MIME、HTML 净化、`golang.org/x/crypto/argon2`、`github.com/miekg/dns` 等），尽量不再动 `go.mod`。确实要加依赖，在报告里说明理由。
- 契约模块经 `go.mod` 里的本地 `replace` 指向同仓的 `../contracts-mail`，不改契约（proto、契约 JSON、`api/`）。契约和设计对不上、或者实现时发现契约缺字段：不要改契约，在报告里列出来，先用现有字段做，做不了的留桩并在进度文件里写明。
- 本机代理会劫持回环地址的请求：要连本机端口时先 `unset HTTP_PROXY HTTPS_PROXY ALL_PROXY`（或 `export NO_PROXY=127.0.0.1,localhost`）。
- **数据库**：单元测试用内存 SQLite（`tests/testkit.OpenMailDB(t)`）。需要真实并发或 MySQL 特有行为的测试，自己起一次性的 MySQL 容器（名字和端口都不要用别人的：3306 上的 `ppb-mysql` 是别人在用的开发库，绝对不要连），用环境变量门控，没有容器时跳过并打印原因。跑完把容器删掉。
- 本机 Docker 可用。拉镜像失败时在镜像名前加 `docker.m.daocloud.io/`。
- 跑引入 Kitex 的程序会打印一行 `dynamicgo only support amd64 …` 的提示，不影响结果。
- **这台机器的沙箱里，Go 程序解引用空指针不一定 panic，可能是那个协程直接挂死**（WS3 踩过四回）：表现是测试卡住不结束，`-timeout` 也常常打不出堆栈。排查时先怀疑空指针；测试里不要去打印「非空的 error 接口包着一个空指针」这种值。
- 测试里 Unix 套接字的路径不要用 `t.TempDir()`（它带测试名，容易超过 104 字节的长度上限），用 `os.MkdirTemp` 起一个短路径。
- 各 worktree 都从 `main` 的早期提交拉的：开工和每个大块之前 `git merge main` 一次，负责人会往 main 上补共用的东西（骨架的小改动、共享的包）。

## 3. 写法

- 平台写法照 `ppb-mail/docs/conventions/backend-service-conventions.md`，参照 `ppb-file/service-file`（只读）。
- 测试先行：先写失败的测试，看到它按预期失败，再写实现，再跑全部测试。测试和被测文件同目录同包名，不用 testify，失败消息带 got 和 want。
- RPC 方法恒返回 `(resp, nil)`，业务失败落 `resp.Base = mailtransport.BaseOf(bizErr)`；错误码只在 `internal/mailerr` 里定义。
- 线上不省略零值：必须出现的消息字段哪怕空也要赋值（否则是 `null`）；int64 在线上是字符串，不会超过 21 亿的数值用 int32。
- 秘密不进日志、不进错误信息、不进审计：口令、令牌、私钥、连接串。日志里不出现邮件内容；用主账号访问邮箱时记接口名和邮箱地址。
- 提交：conventional commits，中文主题，一个提交只做一件事，每个提交都能通过测试。提交信息末尾加一行 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`。只 `git add` 自己名下的路径。
- 不推送，不建远端，不合并，不改 `ppb-docs`，不动别的 worktree 和 `ppb-mail` 的主检出。

## 4. 评审时重点看的五类情况

负责人最后按这五条逐条查，做的时候就照它们写测试：

1. **开放中继和可信提交端口**：未认证向外部投递必须被拒；内部提交端口只能被控制面访问；控制面提交前必须校验发件地址归属。
2. **跨邮箱访问**：用别人的邮件、文件夹、附件标识访问，一律 404；主账号登录不被记成用户登录。
3. **秘密外泄**：日志、错误信息、配置摘要、审计里不能出现口令、私钥、完整连接串。
4. **并发下的重复**：同一个幂等键并发只发一封；两个请求同时申请同一个地址只成功一个。
5. **密码哈希能被 Dovecot 验证**：控制面写入的哈希，邮件核心里的 Dovecot 能认。

## 5. 报告（负责人只能看到这个）

1. 提交列表（短哈希加主题）。
2. 最终的 build / vet / test 命令和结果：多少个包通过、多少个顶层测试函数通过和跳过、有没有失败。跳过的逐条说明原因。
3. 任务书里没做完的，逐条写卡在哪。
4. 你替负责人做的判断：每条写判断、理由、错了的代价。
5. 和设计文档、契约不一致的地方。
6. 没跑的验证。
7. 给下一轮（或集成）的提醒：哪些桩还在、哪些接口的对方还没做、哪些值是按邮件核心工作流的开发编排写死的。
