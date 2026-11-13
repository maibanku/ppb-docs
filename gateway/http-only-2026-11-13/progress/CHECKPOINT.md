# 当前执行检查点

目标：server-gateway 最终只做 HTTP/WS 透明反向代理；全部旧入口归属真实服务，权限与客户端契约不回退。

基准：ppb-base/main@9989a6a 起步。当前 HEAD cc92503（P3 已提交推送；活栈已切 forward.enabled=true）。31 测试包绿。

## 已完成

### P0/P1/P2（详见前次检查点；docs 96338dd + 本轮）
P0 基线/负控；P1 svcauth/authzguard/网关别名/IM member 直验；P2 IM 39 manage 路由 + 网关前转 + MQ 公告广播（14/14 活体验证）。

### P3（cc92503）
- IAM 服务自有 HTTP：user-member 8 + user-anon 8（含 manage/login 退役信封）+ user-manage 5 契约；D4 闸门/IAM_JWT_SECRET env。
- 登录编排迁 IAM（memberauth 包平移：两步链/OIDC 兑换 in-process/denylist/minClientVersion）；IssueMemberCredentials RPC（注册/邀请 token 签发权威=IAM）。
- IM public 契约 4 匿名（register/accept 经 mint 钩子注入 token）。
- IAM 业务桥：internal/bridge（Cookie→新鲜授权→请求绑定断言按 owner 前转；治理段拒；file/camera 503 待 P4）；网关桥仅保留 file/camera legacy 闭包。
- 网关 user/auth 前转表 + ForwardConfig 回退杠杆（已 enable）。
- 活体验证：login/session/profile 全链、wrong-password 401、email-log 200、桥无 Cookie 401、死路由（user/sessions 族——上游 RPC 基线即未承接）行为等价 503（已如实记录）、P2 回归 14/14。
- IAM cookie Secure 测试债：**未修**（基线既有 TestE2E_HTTPAPIContract 失败，P4 顺手修）。

## P4/P5 并行进行中（2026-11-13 上午）

- 3 subagents 运行：file-http（12 manage + member 面加固）、camera-http（10 subject + 18 manage）、im-realtime（ws/route ~2600 行迁 server-im/internal/realtime + /ws 端点 + MQ 消费）。
- Lead 已落：servicehttp PolicySpec.bridgeAppKey（file 桥重映射）；IAM cookie 测试债修复（f25620a）；网关 /ws 透明前转（4e54e11，forward.enabled 联动——**活栈下次重启必须等 IM realtime 就绪**，否则 WS 断）。
- 协调点：P4+P5 全部就绪后统一重启（im/iam/gateway/file），跑 P2 矩阵 + WS 真机验证。

## 后续批次：P6/P7（不变）

范围：
1. server-file：12 manage 路由契约（bridgeAppKey=file 重映射！）+ member 文件流面（upload/download/thumb/chunk 的 memberBizKey 从网关注入改为服务端 svcauth 直验注入——A06/A14 加固）；网关 /api/v1/file/* 切凭据透传。
2. server-camera：10 subject + 18 manage 路由契约（camera 主体 token 直验 svcauth.CameraSubjectAuth；管理面 CameraAdmin）+ 9116 HTTP 装配；网关 camera 域切前转。
3. 网关桥 file/camera legacy 闭包退役（/iam business 全量直通 IAM）。
4. IAM cookie 测试债修复。
5. PolicySpec 增 bridgeAppKey 字段（servicehttp 桥判定用）。

## 下一步

1. servicehttp PolicySpec.bridgeAppKey（Lead，小改）。
2. 分派 P4a（file 契约+装配+member 面加固）、P4b（camera 契约+装配）；Lead 网关切换+验收。
3. P5 实时面迁移（ws/hub/route/poller→server-im realtime；网关 WS 透明 Upgrade）。
4. P6 透明网关替换（去 registry/JWT/edgeauth/permguard 依赖）。
5. P7 部署/CI/全量验收。

## 纪律不变项

不动他人 dirty 文件；不 force push；密钥不进日志/提交；P6 前网关守卫全保留；远端 MySQL/Redis/MQ 凭据只经 db.env 与进程环境。
