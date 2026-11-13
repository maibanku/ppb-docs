# HTTP-only 网关改造：最终验收报告（FINAL-ACCEPTANCE）

日期：2026-11-13。代码 ppb-base/main@47e1b4a；文档 ppb-docs/main@c833ffc+。活栈：透明网关 8080 + im 9102/9112 + iam 9107/9117 + file 9104/9114 + camera 9106/9116；数据在 LAN MySQL 192.168.3.55（deploy/db.env，未入 Git）；RabbitMQ/Redis 同机。

## 最终架构（目标 1-6 全部达成）

1. **server-gateway = 透明反向代理**：`tools/gen-routes` 从五份服务契约 JSON 生成 `deploy/config/gateway-routes.yaml`（1 前缀 + 150 精确/模板），`transparent.go` 按配置分派固定 upstream；头卫生（清 X-Ppb-*、凭据透传）；不解码业务请求/响应；不签发任何凭据；TLS/限流/静态/`/ping` 保留。路由配置缺失=拒绝启动。
2. **依赖图（A01）**：`go list -deps ./server-gateway` 禁项计数 **0**（基线 79 个 grpc 族）。CI 步骤 `gateway dependency audit` 非零退出守护。
3. **WebSocket（A09/A10 部分）**：`/ws` 透明 Upgrade → server-im `internal/realtime`（hub/route/poller/MQ 消费自网关平移；worker 随 ctx 启停）。活体验证：无凭据 401、有效 token 101、升级后下行帧活性 ✓。跨节点路由（Redis 双节点）与通话信令全链为后续真机项（见下）。
4. **148+19 承接（A02）**：ROUTE-STATUS.csv 167/167 落位——163 承接完成（im 81 / iam 24+登录编排 3 / file 12+member 门 / camera 29 / member 42 + 匿名 4 + 特殊面）+ 4 项 P6 退役（system-health 网关本地聚合、swagger 随 registry 退役等，均记录处置）。
5. **鉴权不回退（A05/A06/A07）**：服务端 svcauth 直验（member 双权威复检 fail-closed / manage / camera-subject）+ authzguard（revision 一致）+ authzport 逐方法；IAM 业务桥（迁入 server-iam）断言即凭据；伪造 actor/token/断言全拒。负控矩阵在 svcauth/authzguard/servicehttp/bridge 各包测试内。
6. **登录编排（A08）**：两步链 + OIDC 兑换 + 注册/邀请签发全部归 IAM（`IssueMemberCredentials`）；网关不再包装返回值。浏览器 IAM Cookie/回调/直通 `/iam/*` 不变。

## 逐项验收（A01-A17）

| 项 | 结果 | 证据 |
|---|---|---|
| A01 依赖图 | ✅ | 禁项 0（本报告§2；CI 门禁）；启动 main=透明唯一形态 |
| A02 148+19 对照 | ✅ | ROUTE-STATUS.csv 167/167；无 pending |
| A03 契约兼容 | ✅（含两类已记录差异） | servicehttp Reply 保留大整数精确编码（json.RawMessage，不经 float64）；差异 1：未知路由 404（legacy 403，拒绝等价）；差异 2：方法不匹配 405（legacy 401，拒绝等价）；差异 3：camera JWT manage 直连 503=基线即如此（gRPC 面只收断言） |
| A04 新接口免重编译 | ✅ | `/api/v1/im/` 前缀放行（transparent 前缀路由 + 测试 TestBuildTransparentMuxRouting） |
| A05 无/坏/撤销 token | ✅ | svcauth 负控矩阵 + 活体：manage/member/im 面无凭据 401、坏 token 401、直连服务端口同拒 |
| A06 伪造身份字段 | ✅ | 伪造 X-Ppb-Actor/断言 → 403/忽略（transparent_test + live forged-actor 200 无 5xx）；operator 一律覆盖式注入 |
| A07 管理权限矩阵 | ✅ | authzguard 测试（跨应用同码不互通/撤权下请求拒/revision 回源失败拒）+ 桥 is_super 不通配；活体：demo 超管全通 + 无码 403 |
| A08 IAM 登录编排 | ✅ | 活体：login→orgs→session→token→profile 全链；wrong-password 401 IAM-2001；manage/login 退役信封保持 |
| A09 消息 WS | ✅（连接/升级/下行帧） | 101 升级 + 下行帧 122B；帧内容不重写（透明转发） |
| A10 跨节点/踢线 | ⚠️ 未做 | 单节点活栈；跨节点 Redis 路由与踢线全链未验证（rtws 单测覆盖逻辑面） |
| A11 MQ 停机恢复 | ⚠️ 部分 | 公告 publish→MQ→（网关消费退役后）IM 消费→hub 广播闭环已活体验证；RabbitMQ 停机注入场景未执行 |
| A12 通话信令 | ⚠️ 未做 | RTC 未配置（活栈 IM-8000）；信令面无真机验证 |
| A13 语音/视频媒体 | ❌ 未做 | 无硬件条件；如实标记（未冒充） |
| A14 文件流 | ✅（路由/身份） | file member 门（svcauth 直验注入 memberBizKey）+ manage 面 200；Range/206/大文件长传未注入大流量实测（服务端 handler 未改动——流式行为原样） |
| A15 重启/故障/歧义 | ✅ | restart-im-gateway.sh 全程使用；LoadRouteTable 歧义/未知 owner 拒起（测试）；上游不可达稳定 503（测试+活体） |
| A16 build/test/CI/脚本 | ✅ | 61 测试包全绿；gen-routes/buf generate/service-http 三生成幂等本地验证；start-all/ci.sh/CI workflow 已对齐 |
| A17 Git 提交 | ✅ | ppb-base 9989a6a→47e1b4a（每批可运行提交，已推送）；ppb-docs 同步推送；无秘密/他人改动/编译产物（两处误入二进制已即时移除并 gitignore） |

## 遗留与后续（如实）

- A10 跨节点、A11 MQ 停机注入、A12 通话信令、A13 媒体、A14 大流量：需多节点部署/硬件/RTC 配置的真机窗口，本机条件未覆盖——按验收文档口径明确标记，不以测试全绿替代。
- `user/sessions` 族（logout/password/avatar/my-files/my-permissions/login-email/oauth 六条 + sessions 三条）：上游 RPC 在基线即未承接（UserIam 兼容面未实现），改造前后同为 503 行为等价——已记录 ROUTE-STATUS，承接属后续业务任务。
- ppb-chat 桌面客户端真机回归（发消息/好友/通话 UI 全链）未执行——服务端 API 契约兼容已由路由矩阵与负控覆盖。
- camera 为本地 sqlite 起步态（server-camera/config.yaml）；MySQL 目标态迁移属后续运维任务。

## 提交与推送

ppb-base：0ae216a→6c47d55→e1c49e8→2ca2344→f402168→f3c3524→8859f3b→b5d360a→068d267→d58df22→cc92503→f25620a→4e54e11→fd8187d→5881e29→b09ed5a→ff352d0→3f00420→938645b→858f6e5→**47e1b4a**（全部已推送 origin/main）。
ppb-docs：71e53fe→96338dd→9116da5→5ca4b7b→c833ffc→（本报告）。

## 回退

网关回退=上一二进制+旧启动命令（`-routes` 缺失即拒起，不会半份路由）；服务回退=各服务前序提交二进制。数据未做破坏性变更（仅 QA 公告发布/撤回一轮）。
