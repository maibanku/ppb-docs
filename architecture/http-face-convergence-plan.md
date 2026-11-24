# HTTP 面收敛计划：消 DTO/VO 偏差（iam 管理面 + file 群文件契约化）

> 日期：2026-11-24 · 触发：零重复架构审计查出两处偏差区（见下）
> 关联：`grpc-to-http-howto.md`（目标形态）、`external-api-over-rpc-design.md`（设计依据）

## 一、背景：审计结论

全平台 136 条对外路由中 ~130 条已走契约引擎（零 DTO/VO/零手写 handler），
两处偏差区仍是「HTTP 层手写方法 + 自定义请求结构」：

| 偏差区 | 规模 | 结构（实证） |
|---|---|---|
| **iam 管理面手写层** | 27 HandleFunc + 自有 DTO（createRoleRequest 等） | `manage_http.go`/`manage_security_http.go`，handler **直调进程内 PlatformService**（不经回环 RPC）；挂载前缀 `/iam/api/v1/manage/**`（网关另有 3 条 `/api/v1/manage/*→iam` 路由——**双前缀拓扑待统一**） |
| **file 群文件手写层** | 7 HandleFunc + DTO（folderReq/entryPatchReq） | `group_file_http.go`，`/api/v1/file/groups/**`；其中 upload（multipart）/download（流式）= 车道，**5 条 JSON 端点可契约化** |

合理例外（不改造）：file 传输车道（multipart/Range）、im mint 钩子（响应改写）、
camera sms 探针、WS payload。

## 二、改造路线决策

| 路线 | 内容 | 判定 |
|---|---|---|
| A. 全链契约化（契约→回环 RPC→handler） | proto 扩面 + kitex handler + 契约路由 | ✅ **iam 采用**——与 camera/file/im 管理面模式完全一致；管理操作获得 RPC 面（未来网关上收现成） |
| B. 进程内 Invoker | 契约引擎加进程内分派 Invoker，直调 service | ❌ 引入第二条调用路径，破坏「HTTP 面测真实 RPC 链」属性 |
| C. 混合 | JSON 端点契约化 + 车道保留 | ✅ **file 采用** |

## 三、批次一：iam 管理面契约化（主项，2-4 天）

### 3.0 前置：拓扑核实与统一（0.5 天）

理清双前缀：`/iam/api/v1/manage/**`（iam-web 直连 9117？）与网关
`/api/v1/manage/*→iam` 3 条的关系。目标态：统一走网关前缀
`/api/v1/manage/iam/**`（一服务一前缀约定）；iam-web 直连路径若必须保留，
契约面挂双前缀或网关补路由——**执行第一步先实证访问拓扑再定**。

### 3.1 端点分类（27 条逐一处置）

| 类别 | 端点 | 处置 |
|---|---|---|
| RBAC CRUD（~19 条） | users 列表/状态、roles CRUD+菜单、menus CRUD、permissions CRUD+usage+挂载、admins CRUD+角色、audit | 契约化：proto 扩 AdminCompatService（或新 ManageService）+ handler 平移 + 契约路由 |
| 会话类（2 条） | me / context | 契约化（GetMe/GetContext RPC——claims 已有，薄实现） |
| security 类（~6 条） | revoke/mfaReset/改密/会话管理等 | 逐条判别：响应语义特殊者（如返回新 token）可保留手写或加特殊注记；其余契约化 |

### 3.2 实施步骤

1. proto：AdminCompatService 增 ~20 方法（消息带 BaseResp 信封，字段名
   json 标签对齐现有手写响应——**前端兼容的关键**）
2. handler 平移：手写 handler 的参数校验/权限判定逻辑移入 transport
   `*_kitex.go`（多数为直译；DTO 字段 → proto 字段映射表随批次提交）
3. 契约：`user-manage-http.json` 扩容（manage 面，policy 声明沿用
   authzguard 码）
4. 删除：manage_http.go / manage_security_http.go 手写层与全部 DTO
5. 回归：iam-web 管理台全功能（见 §5 对拍策略）

## 四、批次二：file 群文件契约化（1-1.5 天）

1. proto：FileService 增 5 方法（ListGroupEntries/CreateFolder/UpdateEntry/
   TrashEntry/RestoreEntry——PATCH 语义契约引擎已支持，body+path 混合绑定 ✓）
2. handler 平移：group_file_http.go 的 5 个 JSON handler → transport
   `*_kitex.go`；folderReq/entryPatchReq 删除
3. 车道保留：handleGroupUpload（multipart）/handleGroupDownload（流式）不动
4. 回归：桌面群文件 F02-F09（上传/建夹/改名/删除/恢复/下载）

## 五、前端兼容（最大风险，专节）

手写层响应是手拼 JSON；契约化后统一为「Reply 剥 base 投影 data」。
**形状差异 = 前端破坏**。对拍策略：

1. 改造前先录基线：逐端点 curl 采响应 JSON 快照（iam-web/file 桌面两链路）
2. proto 消息字段命名（json 标签）按快照对齐；嵌套结构用嵌套 message 复刻
3. 无法用 proto 表达的形状差异（如动态键、字段省略习惯）→ 该端点保留手写，
   登记例外清单（预期少数）
4. 验收 = 快照 diff 为零（允许 key 顺序差异）

## 六、验收标准与回退

- [ ] 审计 grep 全绿：transport/cmd 层无 `type.*Req|Resp|Request|Response struct`
      （例外=登记车道/钩子/探针）
- [ ] iam 21 包 / file 12 包测试 0 FAIL；iam-web 管理台 + 桌面群文件全功能回归过
- [ ] 响应快照 diff 零差异
- [ ] 双前缀拓扑问题有结论并落地
- 回退：两批次各自独立分支，任一批次失败不影响另一批次与现有 130 条契约路由

## 七、总账

完成后「HTTP 层零 DTO/VO、零重复方法」从主体事实变为**全量事实**（例外=
multipart/流式车道与响应改写钩子等登记在册的 HTTP 原生语义）。
