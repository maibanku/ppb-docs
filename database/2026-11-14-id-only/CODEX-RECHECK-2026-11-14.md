# 全量 ID 改造独立复核

日期：2026-11-14。代码快照：ppb-base `2e7249f`，ppb-chat `3e7eaac6`。复核期间随后新增 `774f017`（P2a：common/iam 增加兼容 ID 字段及生成物），尚未完成服务端和客户端消费切换，不改变本报告 R1–R4 的结论。64 包完整运行结果对应 P1 快照，P2a 随后对六模块执行 -run '^$' 编译复核，退出 0（不计作运行测试）。此次为审查与隔离复现，未修改业务实现，也未对业务库执行 DDL。

## 结论

**全量改造未完成，不通过整体切换验收。** 通用删除时间的代码改造和升级工具已提交；雪花节点配置/ID 字符串转换及消息请求键拆分已提交。但实体业务键仍在模型、接口、JWT、数据库查询和客户端中使用；P2–P6 的接口、服务端、客户端、Camera 和最终删列尚未完成。

本次 `go test` 对六个 Go 模块使用 `-count=1` 重新执行：64 个包通过，退出 0。这说明既有服务端回归通过，不代表新增跨版本/客户端场景通过。补充探针发现以下问题。

## 阻止切换的问题

### R1 / P1：后端新消息键与桌面端请求键还原不兼容

后端 `server-im/internal/service/message/message_service.go:83-84` 生成 `msg-{senderID}-{clientMsgId}`；桌面端 `chat-desktop/src-tauri/src/session.rs:4043-4045` 仍只去掉 `msg-`，把 `msg-1-cid` 还原成 `1-cid`，实际请求键是 `cid`。

桌面 `store.rs:134-154` 按 client_msg_id 查找占位消息并将占位主键改成服务端主键。若 push/历史先于 ack 到达，`pending_cid` 与 `msg-1-cid` 会各留一行；随后 ack 尝试改主键会发生 UNIQUE 冲突。

已使用当前 Rust 的真实 SQLite schema 和相同查询/改主键 SQL 做隔离复现，确认两行并存及 UNIQUE constraint failed；这不是完整 UI E2E。实际 Rust 解析函数的临时回归探针也已编译并运行：断言失败，left="1-cid"、right="cid"，确认解析不兼容；临时源文件已清理。使用 rustup Cargo 1.99.1；系统 Homebrew Cargo 1.68.1 无法读取当前 lockfile v4，不能用于本项目验收。

修复要求：消息请求键应作为独立协议字段返回，客户端不再从消息主键推导；必须一起处理旧快照与 SQLite 升级。回归覆盖 push-before-ack、ack-before-push、断线重发、重启缓存、不同发送者同 clientMsgId。该问题修复前禁止单独部署 P1 后端。

### R2 / P1：回退 SQL 的“旧服务仍幂等”结论不成立

`deploy/sql/ppb_im/incremental/20261114_01_msg_request_key.sql:60-64` 指示删除新索引/列并恢复旧服务，称新键仍是不透明幂等键。但旧版 SendMessage 只查询 `msg-`+clientMsgId，无法命中新版写入的 `msg-{senderID}-{clientMsgId}`。

临时 Go 探针通过现有 Service 发送新消息，再执行旧版本同样的键查询，确认未命中。回退后重试可能再次生成一条消息。新版本还允许不同发送者复用请求键，旧全局唯一语义不能无条件表示这些数据，不能仅改回字符串格式宣称无损回退。

修复要求：明确回退边界，使用能兼容新请求键的回退版本/适配层，并保留必要索引与数据；或停止写入且验证可回退条件。提供实际新写入→回退→原请求重发仅一条的测试，不能仅验证 DROP COLUMN 成功。

### R3 / P1：无效雪花节点号仍回退共用默认值

`server-pkg/snowflake/snowflake.go:45-54` 对显式非法配置打印警告后继续使用 fallback。多个实例配置错误时可能共用同一节点号，从而冲突。此项在上一轮 COORDINATION 已提出，当前仍未修复。

修复要求：显式配置错误应拒绝启动；多实例部署必须配置互异节点号并验证。缺省只可作为明确的单实例开发约定。不要把“可配置”算作“多实例唯一性已保障”。

### R4 / P2：兼容消息键长度可能超列宽

当前 client_msg_id 与 im_message_biz_key 都是 VARCHAR(64)，拼接又增加 sender ID 和前缀。实际调用 MsgBizKeyOf(9007199254740993, 48字符请求键)，得到 69 字符，超出业务键列宽。服务端没有前置 UUID 格式/长度校验。桌面正常生成的 36 字符 UUID 通常不触发，但兼容输入范围已经收窄，MySQL 严格模式会拒绝写入。

修复要求：实体消息 ID 与请求键解耦，或定义并校验请求键协议长度，确保所有允许输入均能落库；补真实 MySQL 边界测试。不能依赖 SQLite 不限制 VARCHAR 长度而认为测试通过。

## 实际残留范围

排除生成 Go 文件和 Go 测试后，GORM 模型仍声明 89 个业务键字段：IAM 33、IM 33、File 5、Camera 16、共享 outbox/inbox 2。这里只计显式 column:*biz_key 标签，不把注释算成字段。

客户端仍有 149 个桌面端文件、34 个聊天管理端文件出现旧键引用（该文件统计包括测试/注释，不等价于缺陷数量）。例如桌面 SQLite 仍以 msg_biz_key/conv_biz_key/sender_biz_key 存储，HTTP/WS 和 IAM 契约也仍使用旧键。

直接只读检查本地 Docker `ppb-mysql` 的 information_schema：

| 数据库 | 业务键列 | 通用删除时间列 |
|---|---:|---:|
| ppb_iam | 33 | 33 |
| ppb_im | 38 | 35 |
| ppb_file | 5 | 4 |
| ppb_camera | 16 | 14 |
| 合计 | 92 | 86 |

这是本地 Docker 实例的结果，不代表其他 LAN/部署实例。代码不再读写通用删除时间，但旧库尚未删列，符合此前停写/备份/统一迁移的安排；不能称数据库已清理完成。

## 执行与交付状态

Claude 进程在审查时仍运行，已从 P1 转入 P2。status.md 阶段表尚未及时反映 P0/P1 已提交事实，不能只依据表格判断成果。复核结束时 P1 与 P2a 两个提交本地领先 origin/main 2 个，尚未推送；以之后 git 状态为准。

下一步先修复 R1/R2/R3，再完成接口与客户端切换。最终验收必须包含旧数据映射、数字 ID 字符串精度、双组织身份隔离、待发队列恢复、消息引用/转发/撤回、文件与通话路径，以及真实业务库升级与回退。不要在仍有独立 UUID 实体字段或活跃旧契约调用时标记 complete。

## 证据目录

`/Users/pipi-ban/Documents/Codex/2026-10-24/du/work/id-only-20261114/`

- recheck-all-go.log：64 个 Go 包全量重新执行通过（非缓存运行）。
- recheck-p2a-compile.log：P2a 后六模块编译复核通过（没有运行测试）。
- recheck-residual-inventory.json：代码模型与调用残留统计。
- recheck-docker-schema.json：本地 MySQL 四库残留列数。
- review-desktop-key-compat.json：真实 SQLite schema/SQL 下的占位归并失败复现。
- review-backend-probes.go.txt / review-backend-probes.log：旧版查找未命中、兼容键超长的负向探针，预期失败；临时 Go 源文件已清理。
- review-rust-probe-stable.log：实际 Rust 函数探针断言失败，临时源代码已清理。

没有把负向探针失败混入“正常测试通过”的数量，也没有把服务端单测等同于桌面 E2E 验收。

复核问题已交回原 Claude 会话优先修复，进程 72947 已恢复并开始处理 R3；R1/R2/R4 继续跟踪，未经复验不关闭问题。
