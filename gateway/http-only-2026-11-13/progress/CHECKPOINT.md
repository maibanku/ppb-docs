# 当前执行检查点

目标：server-gateway 最终只做 HTTP/WS 透明反向代理；全部旧入口归属真实服务，权限与客户端契约不回退。

基准：ppb-base/main@9989a6a 起步。当前 HEAD e1c49e8（P1 已提交推送）。工作树含 P2 预备改动（manage_forward/AuthorizeManage 已入 P1 提交）。

## 已完成

### P0（docs 71e53fe）
环境复核、ROUTE-STATUS.csv 167 行、负控基线（16 项 auth 负控 + 线上抽查 401 USER-0001/IAM-2001）。

### P1（ppb-base e1c49e8）
- server-pkg/svcauth（0ae216a）：member/manage/camera-subject 凭据验证共享包 + IamSessionChecker/ChatOrgMemberChecker + 负控矩阵测试（19 用例，与网关 auth_middleware_test 逐条对齐）。过渡期 EdgeCompat：无凭据+edgeauth 断言 → 放行内层（验证器未配置也不中断既有链路）。
- server-pkg/authzguard（6c47d55）：RoutePolicy + revision 一致性 AdminAuthz 守卫（permguard 语义平移，10 负控用例）。
- 网关 auth 别名化：Claims/Validator/常量/context 键 = svcauth 单源；proxy 检查器委托 svcauth。
- IM member HTTP 直验装配：main.go Wrap(servicehttp handler)；D4 闸门（dev secret 需 PPB_ALLOW_DEV_JWT=1，start-all 全局已导出）；im.yaml jwt 段。
- servicehttp 契约身份类扩展：member|manage|camera-subject|anonymous，默认拒绝。
- 全模块测试绿（gateway 23 包/im 13 包/pkg 含 svcauth/authzguard）；唯一失败 server-iam TestE2E_HTTPAPIContract 为**基线既有**（9989a6a worktree 复核同样失败；cookie Secure 断言与 6837250 LAN issuer 行为不符——P3 修）。

## 当前批次：P2（IM 管理 HTTP 承接）

范围：IM 39 条 manage（UserOrg 29 + IM 10）+ 2 条匿名 user 路由（register/invitations send-code）；register/accept-invite 留网关（P3 IAM 签发迁移）。要点：
1. servicehttp 契约 Route 增 Policy/Audit/Broadcast 字段 + NewManageHandler（claims→authzguard→authzport actor→本地 RPC）。
2. server-im/api/manage-http.json 39 条（政策/绑定见 progress/P2C-BRIEF.md）。
3. IM AdminMethodPerms 补 AdminListGroupMembers {chat, group.read}。
4. 审计 sink（UserIam.AdminAudit via iamConn）+ 公告 MQ（topic announcement.publish）；网关消费端补 hub 广播。
5. 网关：manage 组 handler 对 IM-owned 路由 AuthorizeManage（防线保留）→ NewServiceManageForward 前转 9112。
6. 活体验证：重建/重启 IM + 网关，直连 9112 负控（无凭据 401/member token 403/缺码 403 MANAGE-0004）+ 网关链路回归。

## 下一步

1. 收三个 worker 报告（gw-alias/svc-http-identity/im-direct-auth，代码已验证绿）。
2. P2 顺序：servicehttp Policy schema + NewManageHandler（Lead）→ P2c 契约+装配（subagent，简报 P2C-BRIEF.md）→ 网关前转切换 + 公告消费（Lead）→ 测试+活体验证 → 提交。
3. P3 起：IAM 自有 HTTP（15 user + 6 manage + login/oidc/session 编排 + register/accept token 签发迁移 + IAM cookie 测试债）。

## 纪律不变项

不动他人 dirty 文件；不 force push；密钥不进日志/提交；服务端授权未等价前不删网关守卫；P6 前网关 permguard/JWT/edgeauth 全保留。
