# 当前执行检查点

目标：server-gateway 最终只做 HTTP/WS 透明反向代理；全部旧入口归属真实服务，权限与客户端契约不回退。不得仅搬旧网关至泛业务 BFF 宣称完成。

基准：ppb-base/main@9989a6a，工作树 clean（他人无 dirty 文件）。已完成首批 42 条服务 HTTP；剩余 105 个 gRPC 入口、1 健康聚合、19 特殊入口。

## P0 已完成（2026-11-13）

- 环境复核：im 9102/9112、gateway 8080、file 9104/9114、iam 9107/9117 在跑；camera 未启动；Docker mysql/redis/mq/livekit healthy；go.work 六模块。
- ROUTE-STATUS.csv 重新生成：167 行 = 148 Registry + 19 特殊；生成器 implementation/gen-route-status.py（join api/policies/*.yaml）。
- 旧权限负控基线：`go test ./server-gateway/... ./server-pkg/servicehttp/...` 全绿（exit=0，含 auth_middleware_test 16 个负控：无凭据/撤销/无 sid/org-select 冒充/未知 typ/checker 未装配/session 检查失败等）。
- 线上负控抽查（旧 gateway :8080）：无凭据 → user/manage/im 均 401 USER-0001；/iam 面 401 IAM-2001；/ping 200。
- 迁移图谱已确认：105 gRPC = manage→UserOrg(IM)27 + manage→IM 10 + manage→UserIam(IAM)6 + manage→File 11 + manage→CameraAdmin 18 + user→UserIam(IAM)15 + user→UserOrg(IM)4 + camera→Camera 10 + system_health 1。

## 当前批次：P1（服务端公共认证/权限适配）

核心：把 gateway 侧 member/manage 凭据验证与权限判定抽到 server-pkg 共享认证包（无 gateway 依赖），服务先接受并验证原始凭据（Authorization Bearer / edgeauth 兼容），负控等价后才允许 P6 删除网关守卫。edgeauth 现用 internalauth.Token() 作 HMAC key。

## 下一步

1. 等三只 Explore 报告（IM HTTP 模式 / gateway auth+permguard / 三服务结构）→ 定 P1 包设计（server-pkg/svcauth 候选名）。
2. P1 实现：抽 claims/验签/session 复检/member token 复检 → 服务侧中间件（先 IM，后 IAM/File/Camera）→ 负控测试等价。
3. 每批小提交推送；服务端认证补齐前不删网关 JWT/permguard/edgeauth。

## 纪律不变项

- 不动他人 dirty 文件（当前无）；.bak-claude* 勿删；不 force push；密钥不进日志/提交。
- 历史验证目录 /Users/pipi-ban/Documents/Codex/2026-10-24/du/work/thin-gateway-20261112 可复用脚本。

最近测试：见上。最近提交：docs P0 批次（本文件 + ROUTE-STATUS.csv + 生成器）。
