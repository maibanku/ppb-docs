# 单端口改造剩余任务清单（逐项执行跟踪）

> 日期：2026-11-23 · 目标终态：**每服务单 Kitex RPC 口 + 网关统一翻译 HTTP + 东西向 100% RPC**
> 用法：Claude Code 逐项实现，每项完成即更新状态并提交；测试门禁全绿才算完成；
> 未跑的验证显式标 NOT_RUN。关联分析：`single-port-json-mapping-summary.md`（总纲）、
> `iam-bridge-rpc-only-plan.md`（桥退役）、`external-api-over-rpc-design.md`（外部接口设计）。

## 验收口径（全部完成时成立）

1. 服务进程内只剩一个监听口（Kitex 910x，或含本地 healthz 探针）
2. 出站服务间调用零 HTTP（grep `http.Client` 仅剩 mesh 外部端点）
3. 客户端只见网关 8080，URL/JSON 形状/错误码零变化
4. 回退路径：按服务灰度，一行 upstream/契约装载选择切换

## 任务清单

### A 线：IAM 业务桥退役（东西向 100% RPC 收口）

- [x] **A1 manage-token 换发端点**（服务半）——`ppb-iam@feat/bridge-retire-manage-token 0ab2a30`；
  token 经承接服务同款 svcauth.Validator 验签实证；deploy 密钥登记 `ppb-base@c13690d`
- [ ] **A2 iam-web 前端拦截器换 Bearer**：manage 调用前确保 token（401 触发重取），
  路径改经网关 `/api/v1/manage/**`（依赖 A1；前端仓）
- [ ] **A3 双跑观察 → 删桥**：`internal/bridge` 前转段 + boot_wire 挂载删除；
  `iamOwnedExact`（audit/iam、email-log）迁 token 车道或 iam 自有面；治理拒绝段口径随删
  （依赖 A2 上线观察期）

### B 线：S0 文件直传收尾（file 去 HTTP 口前置）

- [x] **B1 预签名凭证面**（服务半）——`ppb-file@feat/presign-direct-upload 5bdf3e4`；
  proto v9 三方法 + 会话复用 + member 契约 3 条 + 真实 MinIO SigV4 回环实证
- [ ] **B2 contracts-file tag v0.1.2 发布** + service-file go.mod replace 桥撤除（发布授权项）
- [ ] **B3 客户端切换 presign 直传**（desktop ppb-chat Rust `httpapi.rs` upload_file 族 +
  mobile chat-mobile；跨仓）
- [ ] **B4 file_transfer 车道退役**：网关 special 移除 + 服务传输 handler 删除（依赖 B3 放量）

### C 线：特殊车道独立（im/iam 去 HTTP 口前置）

- [ ] **C1 im `/ws` 独立接入**（独立进程或网关长连接能力；im 收敛纯 RPC）
- [ ] **C2 iam OIDC 随门户独立**（认证门户承载 `/authorize` `/token` `/jwks` 重定向语义）
- [ ] **C3 im `/im/rtc/webhook` 安置**（LiveKit 回调：网关 special 显式化或保留 im 专口，小项）

### D 线：S2 网关翻译化（核心——「HTTP 都在网关」）

- [x] **D1 契约上收 contracts 仓**（camera 试点先行）——`ppb-camera@feat/
  contracts-api-home 3690b2b`：subject/admin 迁 contracts-camera/api/（纯数据
  embed 零依赖）；service-camera 薄装载层；route-manifest 跨仓 ../ 路径；
  gateway-routes 再生零漂移（139 条恒等实证）；其余三服务待复制
- [ ] **D2 契约 v2 schema**（ParseV2 + security 块 + policy 仅 manage + 匿名六纪律校验器）——
  演进项，可与 D1 并行设计、延后实施
- [x] **D3 网关翻译模式**（subject 面试点）——`ppb-gateway@feat/translate-mode
  1e56722`：internal/translate（契约 + servicehttp + CameraSubjectAuth 链 +
  SMS 两阶段/主体注入上收 + grpc 回环腿）；路由粒度灰度（BuildTransparentMux
  override）；config 门控缺省关 + 三要素 fail-fast；端到端测试实证（匿名
  templates 200 / 非白名单 401 / 未知 401）
- [x] **D4 camera 试点切换（双面全量）**——`ppb-gateway@7b4bc36`：subject 面（D3）+
  **manage 面（19 条）**：guard 回源（AdminAuthz/RbacVersion 经 IAM grpc 直连试点路）+
  manageAssertionInvoker 断言补签 + 断言即凭据分派 + ManageAuth 直验（D4 密钥门控）；
  双面独立开关互不串面；端到端双 TCP 桩实证全链路（token 直验→guard→断言→回环→200）
- [x] **D5 camera HTTP 口退役开关**——`ppb-camera@60e0d9b`：`server.http_enabled`
  （缺省 true 双跑；false=业务面退出口仅留健康探针，回环/面装配/iamCompat 一并跳过）；
  **活灰度已实证**（旁路 18080 实例 × 真实 camera/IAM：匿名 templates/写库
  guest-sessions/带凭据 quota 三类路由新旧路径**逐字节同响应**，无凭据 401）——
  正式切换=部署侧 gateway translate.camera.enabled=true + camera http_enabled=false
- [ ] **D6 im/file/iam 逐家切换**（依赖 A/B/C 完成度，同 D4 模式复制）
- [ ] **D7 安全复审（S2 前置专项）**：member/manage secret 进网关进程的密钥面扩大评审
  （分发、轮换、网关妥协半径）——书面前置，D4 灰度开前完成

### E 线：演进与阀

- [ ] **E1 proto `google.api.http` 注解生成器**（`make gen-api`：注解 → 契约 JSON，手写归零）
- [x] **E2 im 出站灰度开阀**——`ppb-base@bb5d151`：im.yaml iam/file service_name
  填 ppbchat-iam/ppbchat-file（Phase C 已验证；重启生效，兼容门禁过）

### F 线：观测与收口

- [ ] **F1 smoke 探针地址改网关**（四服务 smoke 的 HTTP 探针统一打 8080）
- [ ] **F2 文档收口**：kitex-placement-map（契约落位更新）、internal-rpc-howto（桥例外
  条目撤销）、kitex-replacement-checklist 增补本清单链接

## 执行纪律

1. 顺序建议：**D1 → D3 → D4（试点闭环）** 与 **E2（两行开阀）** 本批推进；A2/B3 客户端项
   与 C 线独立排期；D2/D7/E1 随 S2 批
2. 每项门禁：所在仓 `go build ./... && go test ./...` 全绿 + 相关 deploy 兼容门禁；
   跨仓项跑联动测试
3. 灰度与回退：D 线全部 config 门控（缺省透明模式 = 现状），单服务粒度可回退
4. 状态更新：完成即打勾 + 提交号；半成品标 ⏳ 并注明断点

## 状态快照（2026-11-23 本批执行后）

- 已完成：A1、B1、**D1、D3（subject 面试点）、E2**、全服务通道审计
  （提交链：camera 3690b2b / gateway 1e56722 / deploy 4e3091a·bb5d151）
- 下一批：部署侧正式切灰（subject 面先行：gateway enabled=true 观察 →
  manage 面补 manage_secret 双侧 → camera http_enabled=false **首服务单端口达成**）；
  A2/B3 客户端项独立排期；D6 im/file/iam 复制 D4/D5 模式
- 阻塞项：A2/B3 需前端/客户端仓配合；B2/D1 tag 发布需授权
