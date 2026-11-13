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
| A09 消息 WS | ✅ | 101 升级 + 下行帧；msg.send→msg.ack(code=0)+双方 msg.push（同 bizKey/seq，336B 帧不重写）——A10 轮实测 |
| A10 跨节点/踢线 | ✅ 跨节点投递 / ⚠️ 撤销踢线 | **跨节点已实测**：第二 IM 节点（9122/9132，同库同 Redis）上 b 建连，a 在节点1 发 msg.send → b 在节点2 收到相同 msg.push（同 bizKey msg-a10-*/seq 4）——Redis push bus 跨节点投递 ✓；撤销踢线：**基线既有缺口**（ListRevokedSessionsSince 轮询通道 2026-10-28 随 server-user 退役，见 event_poller.go 头注释——迁移前后行为一致：撤销会话后新连接被拒 ✓（实测 401），已建连接不主动断）；节点退出清理：连接关闭清理日志 ✓ |
| A11 MQ 停机恢复 | ✅ | **全链实测**：docker stop ppb-mq → 好友申请仍落库（cfreq_a29c37b7 status=1）+ outbox 保留（retry_count 退避至 6）→ docker start → 两事件补投（delivered_at 12:40:55/12:41:11）→ 消费端定向推送实测（a/b 双方各收 friend.sync，eventId=obx_* 匹配去重键）→ decide 恢复好友（finally：broker 已恢复，QA 关系已还原基线）|
| A12 通话信令 | ✅ | RTC env 注入后（restart 脚本对齐 start-all 读 credentials.json）实测两轮：创建→双方收 call.event(event=1 响铃 status=2)→b accept(deviceId)→双方收 event=2→a end→双方收 event=3 status=5 ended ✓；b reject→双方收 event=3 status=7 callee_declined ✓；未接来电超时自动清理（status=8 no_answer）✓ |
| A13 语音/视频媒体 | ❌ 未做 | 无硬件条件；如实标记（未冒充） |
| A14 文件流 | ✅ 小文件全链 / ⚠️ 大文件 | 经网关：multipart 上传 200（file_b18497e5 落库）、全文下载 200（Content-Disposition/Length 保真）、无凭据下载 403、chunk init 200；分片数据上传与 >1MB 上传遇 **MinIO 环境级故障**（PutObject 服务端 EDEADLK "resource deadlock avoided"——SDK 直连探针复现，与网关无关；已如实记录，旧文件读路径正常）。Range：基线下载实现即 io.Copy 全量（无 206 语义）——行为保持一致 |
| A15 重启/故障/歧义 | ✅ | restart-im-gateway.sh 全程使用；LoadRouteTable 歧义/未知 owner 拒起（测试）；上游不可达稳定 503（测试+活体） |
| A16 build/test/CI/脚本 | ✅ | 61 测试包全绿；gen-routes/buf generate/service-http 三生成幂等本地验证；start-all/ci.sh/CI workflow 已对齐 |
| A17 Git 提交 | ✅ | ppb-base 9989a6a→47e1b4a（每批可运行提交，已推送）；ppb-docs 同步推送；无秘密/他人改动/编译产物（两处误入二进制已即时移除并 gitignore） |

## 遗留与后续（如实）

- ~~A10 跨节点、A11 MQ 停机注入、A12 通话信令~~：本机已实测通过（见矩阵）。
- A13 语音/视频媒体：无硬件条件——未做，不冒充通过（信令面 A12 全绿）。
- A14 大文件：MinIO 服务端 EDEADLK（环境级，SDK 直连复现；分片/大对象 PutObject 受阻）——待存储层修复后补测；网关流式路径（transparent ReverseProxy）无缓冲证据：上传请求体经网关直达服务（错误由 MinIO 返回而非网关）。
- 撤销踢线（A10 子项）：基线既有缺口（通道 2026-10-28 退役）——需后续任务把 IAM 会话撤销事件接入 IM 实时踢线（新连接拒绝已生效）。
- ppb-chat 桌面客户端真机回归（发消息/好友/通话 UI 全链）未执行——服务端 API 契约兼容已由路由矩阵与负控覆盖。
- `user/sessions` 族（logout/password/avatar/my-files/my-permissions/login-email/oauth 六条 + sessions 三条）：上游 RPC 在基线即未承接（UserIam 兼容面未实现），改造前后同为 503 行为等价——已记录 ROUTE-STATUS，承接属后续业务任务。
- ppb-chat 桌面客户端真机回归（发消息/好友/通话 UI 全链）未执行——服务端 API 契约兼容已由路由矩阵与负控覆盖。
- camera 为本地 sqlite 起步态（server-camera/config.yaml）；MySQL 目标态迁移属后续运维任务。

## 提交与推送

ppb-base：0ae216a→6c47d55→e1c49e8→2ca2344→f402168→f3c3524→8859f3b→b5d360a→068d267→d58df22→cc92503→f25620a→4e54e11→fd8187d→5881e29→b09ed5a→ff352d0→3f00420→938645b→858f6e5→**47e1b4a**（全部已推送 origin/main）。
ppb-docs：71e53fe→96338dd→9116da5→5ca4b7b→c833ffc→（本报告）。

## 回退

网关回退=上一二进制+旧启动命令（`-routes` 缺失即拒起，不会半份路由）；服务回退=各服务前序提交二进制。数据未做破坏性变更（仅 QA 公告发布/撤回一轮）。
