# 当前执行检查点

目标：server-gateway 只做 HTTP/WS 透明反向代理；全部旧入口归属真实服务，权限与客户端契约不回退。**P0-P7 代码与验收全部完成**（含本轮补测 A10/A11/A12/A14）。

基准：ppb-base/main@9989a6a → 当前 HEAD；活栈：透明网关 8080 + im（RTC 已启用）9102/9112 + iam 9107/9117 + file 9104/9114 + camera 9106/9116。

## 本轮（P7 验收补测）新增实测

- **A10 跨节点**：第二 IM 节点（9122/9132 同库同 Redis）实测 a@节点1 发消息 → b@节点2 收同 bizKey/seq 的 msg.push（Redis push bus 跨节点投递 ✓）；撤销会话后新连接 401 ✓；**撤销踢线=基线既有缺口**（轮询通道 2026-10-28 退役，event_poller.go 头注释可查）——已如实记录为后续任务，非本次回归。
- **A11 MQ 停机/恢复**：docker stop ppb-mq → 好友申请落库 ✓ + outbox 退避保留（retry 6 次）→ start → 事件补投 + 消费端定向推送（双方收 friend.sync，eventId 匹配）✓ → decide 恢复好友终态 ✓；broker 已恢复。
- **A12 通话信令**：RTC env 修复后全链两轮——create→响铃(双方 event=1)→accept(带 deviceId)→event=2→end→status=5 ended ✓；reject→status=7 callee_declined ✓；未接超时 status=8 no_answer ✓。媒体(A13)无硬件未做（如实）。
- **A14 文件**：小文件 multipart 上传/全文下载/无凭据 403/chunk init 经网关全通 ✓；>1MB 与分片数据上传遇 **MinIO 服务端 EDEADLK**（SDK 直连探针复现——环境级故障，与网关无关，已记录待存储层修复）。Range：基线下载即 io.Copy 无 206——行为一致。
- 修复落地：restart 脚本补 RTC env（对齐 start-all credentials.json 注入）；b 的 QA 好友关系已还原基线。

## 全量状态（不变 + 更新）

- ROUTE-STATUS 167/167；透明网关依赖审计 0 禁项；61 测试包绿；P2 矩阵 14/14 + P4/P5 脚本 6/6 持续回归通过。
- FINAL-ACCEPTANCE.md 矩阵已更新为实测结论（A10✅/⚠️、A11✅、A12✅、A13❌无硬件、A14✅/⚠️MinIO）。

## 下一步（若继续）

1. 提交本轮 docs+restart 脚本改动并推送。
2. （可选后续任务，超出本次范围）撤销踢线通道重建（IAM 撤销事件→IM 实时踢线）；MinIO EDEADLK 修复后补 A14 大文件；桌面客户端真机回归。
