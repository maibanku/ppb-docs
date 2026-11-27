# WS4 第四轮任务书：把邮件核心这一路的收尾做完

> 上一轮（第二轮）的 agent 又因为上下文过长被中断了两次，工作做的差不多了，但有一批改动没提交、核对文档的结论表没按结果更新。这一轮只做收尾，**不要再开新的核对**。
> 派给这一轮的 agent 先读 [后端工作流转派说明](2026-11-25-backend-agent-common.md) 的第 1 节（怎么配合、上下文怎么省）和第 5 节（报告）。

## 身份

- 工作目录：`/Users/pipi-ban/Desktop/code/vscode/ppb-mail-ws/ws4-infra`（worktree），分支 `feat/ws4-infra`，最后一个提交是 `d74e8c2`。不合并 `main`，不推送。
- 进度记录就是 `docs/verification/M1-技术核对.md` 末尾的「进度」表。

## 接手时的状态

工作区里有上一轮没提交的改动（`git status --short` 看）：

- 改动：`deploy/scripts/dev-verify.py`、`deploy/scripts/start.sh`、`docs/verification/M1-技术核对.md`。
- 改名（已暂存）：`docs/verification/evidence/T10-4-formal-compose-volumes.txt` → `deploy-formal-compose-volumes.txt`。
- 新增：`deploy/.dockerignore`、`deploy/compose/standin/`（给正式编排做冒烟测试用的控制面替身）、`deploy/scripts/formal-smoke.sh`、`docs/verification/evidence/checks/`。

本机有两套编排在跑，都不要动它们的容器：`ppbmail-dev-*`（这一路的开发编排，你可以读它的容器和日志、可以跑核对脚本里只读的检查）和 `ppbmail-e2e-*`（负责人的联调编排，正在用，绝对不要碰）。

## 要做的（按顺序，每步做完提交一次）

1. **看清没提交的改动，确认它们是完整的**。`git diff` 读每一处（输出落文件再看片段）。判断每个文件是不是改到一半：
   - 改完了的，按主题提交（脚本修正一个提交、冒烟测试和替身一个提交、证据一个提交、文档一个提交）。
   - 改到一半的：能补完就补完，补不完就还原（`git checkout -- <文件>`）并在进度表里记一笔。
2. **核对脚本能跑**。`deploy/scripts/dev-verify.py` 的改动如果涉及某几组检查，只跑那几组（看它的 `--only` 之类的参数），输出落到 `docs/verification/evidence/checks/` 下。**不要全量重跑**。脚本里引用的容器名、端口和 `ppbmail-dev` 那套对得上的才算数。
3. **正式编排的冒烟测试**（`formal-smoke.sh` 加 `deploy/compose/standin/`）：如果上一轮已经跑通过、证据在 `deploy-formal-compose-volumes.txt` 里，就不重跑，只核对脚本和证据对得上。没跑通过的，跑一次：用独立的项目名和端口，起完拆掉，不碰上面两套在跑的。
4. **把结论表更新完**（这是这一轮最主要的事）。`docs/verification/M1-技术核对.md` 第 4 节里还标着「未核对（进行中）」「待做」的条目，逐条去证据目录和提交记录里找对应的结果：
   - 找得到的，改成「已核对，设计不变」或「已核对，设计要改」，写明证据文件和提交；
   - 确实没做成的，改成「未核对」并写清卡在哪（写进第 5 节的表）。
   - 已知落定的几条（从提交记录能对上）：T04-2 主账号登录之后打不开邮箱（`ac7488f`，证据 `T04-2-master-acl.txt`）；T05-6 标记头 `X-Spam: Yes`（`e094bfe`）；T07-3 队列方向字段（`7d6d063`，证据 `T07-3-queue-direction.txt`）；T10-2 证书客户端选型；T10-3 备份恢复演练；T10-4 数据卷属主。
   - 不属于邮件核心的那几条（IAM、IM、页面）照旧写「不属于邮件核心」，但把归属的工作流写准：IAM 的登记和业务桥已经做完（ppb-iam 的分支），IAM 的 `ListUsers` 也做了；页面的时间参数名已经落地。
5. **进度表补上第二轮后半段和这一轮**：做了什么、提交短哈希、遗留。遗留里写清楚要负责人定的几件事（转发改写、DKIM 配置怎么生效、停用邮箱后踢会话要不要加命令、告警通道）。
6. **三份文档最后过一遍口径**（`deploy/docs/control-plane-contract.md`、`log-samples.md`、`runbook.md`）：有没有和最终实现矛盾的句子（比如还写着旧的目录、旧的端口、「控制面镜像才刚有」）。只改口径，不加新内容。负责人这边已经有的、可以写进去的事实：控制面镜像 `ppb-mail/service-mail:dev` 已经和邮件核心一起起来过（本机联调编排 `deploy/compose/docker-compose.e2e.yml`，在另一个分支上）；`rspamd` 依赖 `service-mail` 健康（你已经改了）。

## 不要做的

- 不改 `ppb-docs`，不动别的 worktree，不碰 `ppbmail-e2e-*` 和 `ppb-mysql` 等别人的容器。
- 不开新的核对项，不重写文档，不改镜像里的程序逻辑（除非是为了让没提交的改动完整）。
- 不用 Agent 工具再派子 agent。

## 完成标准与报告

- 工作区干净，所有东西都在 `feat/ws4-infra` 上。
- 核对文档里没有「进行中」；每一条要么有结论和证据，要么写明卡在哪。
- 报告：提交列表；还留着「未核对」的条目和原因；没提交被还原的东西（如果有）；要负责人定的事。
