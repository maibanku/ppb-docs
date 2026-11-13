# 当前执行检查点

目标：server-gateway 最终只做 HTTP/WS 透明反向代理；全部旧入口归属真实服务，权限与客户端契约不回退。

基准：ppb-base/main@9989a6a 起步。当前 HEAD 8859f3b（P2 已提交推送）。所有测试包绿（42 包）。

## 已完成

### P0（docs 71e53fe）
环境复核、ROUTE-STATUS.csv 167 行、负控基线。**环境事实**：活栈 IM/IAM/file/camera 数据在 LAN MySQL 192.168.3.55（deploy/db.env 凭据，gitignored）；本地 sqlite 是旧快照。legacy /api/v1/manage/login 已退役（USER-9501）——真实管理入口是 IAM Cookie 业务桥 /iam/api/v1/business/manage/**。

### P1（ppb-base 0ae216a+e1c49e8）
svcauth（member/manage/camera 直验+双检查器 fail-closed）、authzguard（permguard 平移）、网关 auth 别名化单源、IM member HTTP 直验（D4 闸门、edgeauth 过渡兼容）、servicehttp 身份类扩展。

### P2（ppb-base 2ca2344+f402168+f3c3524）
- IM 自有 manage HTTP：39 条（api/manage-http.json；嵌套 PageParam 桥接；roles-scope resolver；5 审计+公告广播入服务；AdminListGroupMembers 补码）。
- 网关 manage 前转：ForwardRegistry 39 条 + AuthorizeManage（permguard 纵深保留）+ NewServiceManageForward（Authorization 透传、X-Ppb-* 清除）；IAM 业务桥仍走 registry gRPC 闭包（P3 迁）。
- 公告实时：IM→MQ announcement.publish→网关 hub 广播（P5 迁 IM）；发布/撤回 QA 公告已清理。
- servicehttp：claims 二源身份（svcauth 优先/edgeauth 兼容）、manage Operator 可空、政策/审计/广播 schema。
- 活体验证 14/14 PASS（deploy/scripts/verify-p2-manage.sh）：直连负控 401、member 网关+直连双通、manage 全链 200、roles-scope、未知路由双侧 403 fail-closed、伪造 actor 无害、公告 MQ 链端到端日志。
- 2 条匿名发码路由已备 public-http.json（edgeauth 退役后启用；现走网关闭包）。register/accept-invite 留网关（P3 IAM 签发）。

## 当前批次：P3（IAM 自有 HTTP + 登录编排迁移）

范围：
1. server-iam 服务自有 HTTP：15 user 路由（8 member+7 anonymous 契约）+ 6 manage 路由（login/exempt 归匿名面）+ system-health 承接评估。
2. 登录编排迁 IAM：member/login+session+oidc-exchange（调 IM ChatOrg 查组织）、token mint 密钥归 IAM、register/accept-invite 成功后 IAM 签发（新 RPC IssueMemberCredentials）；网关 /api/v1/auth/member/* 兼容前转。
3. IAM 业务桥迁移：/iam/api/v1/business/manage/** 按 owner 前转到承接服务 HTTP（IAM 会话验证后的服务间凭据机制）；网关桥退役。
4. IAM 侧测试债：cookie Secure 断言与 LAN issuer 行为（基线既有失败）。
5. manage 2 条匿名发码路由随网关 member 面前转策略处理。

## 下一步

1. 读 server-iam cmd/server main + iam_http_handler 的 mux 结构与 session/OIDC handler（P3 集成点）。
2. 设计 IssueMemberCredentials RPC（proto+服务端）与 IAM member-token 配置。
3. 分派 2-3 个子任务（IAM user/manage 契约、登录编排迁移、桥迁移），Lead 集成。
4. 每批活体验证（复用 restart-im-gateway.sh 模式扩 iam）。

## 纪律不变项

不动他人 dirty 文件；不 force push；密钥不进日志/提交；服务端授权未等价前不删网关守卫；P6 前网关 permguard/JWT/edgeauth 全保留。远端 MySQL/Redis/MQ 凭据只经 deploy/db.env 与进程环境。
