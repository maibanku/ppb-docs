# 06 Claude Lead 执行协议与上下文管理

## 授权与职责

用户已要求 Claude Code 按完整文档开发，允许在本地修改代码、启动相关服务、使用现有 Docker 与专用 QA 账号验收，分批提交并推送远程。所有密钥只留私有配置，不改无关项目/系统权限，不清空数据库，不删 Docker 卷，不发送无关外部消息。

Lead 负责产品/架构目标、任务依赖、集成、审查、真实验收与提交；可以使用 Claude 自身 agent team/subagents。首先读取 README、CHECKPOINT、STATUS，再按当前批次读取对应设计与少量原始代码。不要只写计划后结束，也不要把第一批 42 条当成全量完成。

## 执行批次（依赖顺序）

- P0：复核基线与真实环境，生成全量 ROUTE-STATUS.csv，建立旧权限负控。
- P1：抽出公共服务认证/权限适配，服务端接受原凭据，移出网关身份依赖；所有负控通过。
- P2：IM 管理 HTTP、业务审计/广播；兼容旧 manage 路径，不改变既有成员 API。
- P3：IAM 自有 HTTP、成员登录/OIDC/组织选择/注册邀请凭据签发；网关不再编排。
- P4：Camera 主体/管理及 File 管理/流式 HTTP；身份与应用隔离完整。
- P5：Hub、WS 分发、Redis/MQ/Presence/撤销通道迁入 IM 实时接入，网关透明 Upgrade。
- P6：替换 gateway 为固定 HTTP/WS 代理，兼容路由配置由各服务契约生成；移除业务依赖和凭据。
- P7：启动脚本/配置/CI/契约审计/回退说明；真实跨进程回归，最终报告与全部提交推送。

可调整 P2–P5 的细分顺序以减少冲突，但不能跳过授权补齐、先裸删原保护。每批实现→必要测试→独立审查→可运行提交→更新检查点→下一批。

## 并行协作边界

优先使用短生命周期 subagents：HTTP/service adapter、Auth/IAM、Realtime/File、只读 Reviewer/QA。Lead 为每个任务声明文件范围、接口、输出和验收；共享认证包/契约/schema/启动组合根由 Lead 统一集成，不让多个 writer 同改一个文件。Reviewer 不负责一边审查一边重写同一提交。

并发数以本机资源和模型接口允许为准，建议 2–3 个有效子任务；不要为追求并发启动几十个控制台或重复全量构建。每个 worker 输出不超过约 600 字，详细证据写文档。Lead 不把整份历史会话传给每个 worker。

## 自动压缩（本次本地 CLI 已验证支持）

运行器使用 `claude --autocompact 100k`，不使用 1M 窗口拖延压缩。该值是本地 CLI 的自动压缩窗口参数；实际触发由 Claude Code 控制。

- 每次批次/关键测试/提交后，更新 CHECKPOINT.md（控制在约 1500 中文字以内）和 STATUS.json，不等接近窗口上限才写。
- CHECKPOINT 必须含：HEAD、目标不变项、当前批次、已完成与未完成、修改文件、最近测试及日志、正在运行任务、明确下一步、真实阻塞。
- 接近上限或上下文混乱时，先保存检查点，再 `/compact`；保留约束/接口契约/当前任务，丢弃长日志与重复探索。
- PreCompact hook 自动写 RUNTIME-CHECKPOINT.md（git HEAD/status/stat、session ID/时间）；这不是业务总结，不能替代 Lead 手写 CHECKPOINT。
- SessionStart 的 startup/resume/compact hook 注入简短检查点路径和内容，恢复后先核对实际 git 状态，继续当前批次，不从头重复分析。
- Stop hook 在未完成时提醒继续，并先保存状态；真实 API/认证/资源阻塞必须记录，不可伪造 complete。为避免无限空转，hook 不反复阻止已由 Stop 提醒继续的一轮。
- 不使用 cron/launchd 定时任务；本次仅启动原生后台 Claude 会话。查看状态使用 CLI agents/logs/attach。

## 汇报和阻塞

API 超限、余额、认证或本机环境异常，先做有限重试与可独立工作；反复失败时写 STATUS.blockers、CHECKPOINT 和恢复命令，诚实说明暂停原因。不要降低权限校验、跳过必测项或改 fake 数据来让测试看起来通过。

每个提交仅包含自己的明确路径，保持用户已有未提交改动。只允许常规 push；被远程拒绝先 fetch/rebase 或按实际冲突集成，禁止 force。最终给出事实证据，不宣称无人值守绝不会停止或所有媒体已通过。

## 继续/查看命令

本机 CLI：`/Users/pipi-ban/.nvm/versions/node/v24.21.0/bin/claude`。本次后台会话 ID 和启动命令由运行目录记录，查看进度还可直接读取本目录 progress 文件。脚本/配置只对本次会话生效，不覆盖全局 Claude 设置。

Hook 机制参照 [Claude Code 官方文档](https://code.claude.com/docs/en/hooks)；100k 参数以本机 `claude --help` 的 `--autocompact <auto|tokens>` 为依据。
