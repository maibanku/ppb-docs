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

- [x] 审计 grep 全绿（iam 侧，2026-11-24）：iam transport/cmd 层管理面已无 DTO——
      手写层 5 文件退役，HTTP 层仅剩契约面装配一件（file 群文件批待做，见 §9.7）
- [x] iam 20 包测试 0 FAIL（原约 4800 行管理面 e2e 原样通过）+ 真实进程冒烟 49 步
- [x] 响应 wire 保真：data 键集与零值表现同原手写面（emitUnpopulated +
      optional + omitEmpty，见 §9.6）；前端零迁移
- [x] 双前缀拓扑有结论：`/iam/api/v1/manage/**`（平台管理面，IAM Cookie）与
      `/api/v1/manage/*`（user 域管理面，manage JWT）是两个不同身份族的面，
      各自保留、不合并
- 回退：两批次各自独立分支，任一批次失败不影响另一批次与现有 130 条契约路由

## 七、总账

完成后「HTTP 层零 DTO/VO、零重复方法」从主体事实变为**全量事实**（例外=
multipart/流式车道与响应改写钩子等登记在册的 HTTP 原生语义）。


## 八、可行性核验补记（2026-11-24，代码实证）

### 关键新发现：iam 手写层是「裸 JSON 契约」，与引擎信封不同族

iam 手写层成功响应 = `writeJSON(map[string]any{...})` **裸 JSON**（如
`{items, next_cursor}`、`{ok:true}`、`{admin, menus}`），错误 =
`{code, message}`——**不是** servicehttp 的 `{data,code,success,message}`
信封。前端 iam-web（经 base-manage-web `createIamFetch`）按裸契约消费。

**后果**：iam 契约化 ≠ 纯平移，存在线缆形状差异，三选项：

| 选项 | 内容 | 判定 |
|---|---|---|
| 1. 前端跟改统一信封 | iam-web + base-manage-web 共享 request 层改信封解包 | ✅ 推荐（管理台自用，前端面收敛在共享层；换来全平台统一信封） |
| 2. 引擎加裸投影模式 | Reply 支持 per-contract 非信封输出 | ❌ 引擎复杂化，违背统一信封平台契约 |
| 3. iam 保留手写 | 只做 file 契约化 | 备选（偏差区少消一大块） |

### 体量实测与工作量修订

| 项 | 实测 | 修订工作量 |
|---|---|---|
| iam 手写层 | **2035 行**（manage 1457 + security 578），27 端点，响应裸 JSON | 3-5 批次（含前端信封跟改 +1） |
| file 群文件 | 265 行，5 JSON 端点（信封一致✓） | 1 批次 |
| 阶段1 直传 | minio-go v7.3.0 **已在 go.mod** + objectstore 平台层已存在（预签名 API 现成）；桌面调用面仅 4 处；chunk 自研协议 334 行/涉 11 文件 | 2-3 批次（客户端改造占大头） |
| 阶段4 网关 | proxy 层仅 **664 行**（transparent 181），共享件随迁即可 | 2-3 批次 |
| 单端口 L2/L1 | — | 7-9 / 10-12 批次（与原估一致，置信度提升） |

### 可行性结论

全部阶段技术可行、无阻断项：阶段 1 依赖（MinIO SDK/存储层）已就位；阶段 4
网关体量小；唯一升风险项 = iam 前端信封跟改（选项 1），属可控前端改造
（共享 request 层一处 + api 函数类型调整）。

## 九、实施前置核验与批次实录（2026-11-24，执行中发现）

### 9.1 体量与鉴权族更正（iam）

| 项 | §八原记 | 实测更正 |
|---|---|---|
| iam 手写面端点 | 27 | **43**：manage_http 25 + 安全面 9（manage_security_http.go）+ OAuth/应用域面 9（manage_oauth_http.go） |
| iam 手写面测试 | 未计 | 约 4800 行（iam_http_manage*_test 等 10 文件，回环 e2e 驱动手写 handler） |
| 鉴权族 | 未计 | **IAM Cookie 会话 + 管理会话行 + 治理 any-of 码**——与契约引擎 manage 面（manage JWT + policy self/app_perm/super_gov，拒绝恒 403 MANAGE-0004）不同族 |

由鉴权族差异引出的设计岔路（HTTP 切换批开工前须定）：

| 选项 | 内容 | 判定 |
|---|---|---|
| (a) 会话门外置 | IAM Cookie 会话解析与管理会话准入放在契约处理器**外层中间件**（requireManage 逐字平移，IAM-2001/3003/3004 码不变）；契约引擎只做绑定/回环/信封；治理授权在 RPC 面权威执行 | ✅ **已定并落地（2026-11-24，用户令「iam 只声明 http」）**——实际形态：门只做认证，准入与治理码全部下沉 RPC |
| (b) 引擎扩 policy | servicehttp 增 IAM 会话主体与 any-of 码政策、可配置拒绝码 | ❌ 共享引擎复杂化，且 136 条既有契约路由同受影响 |

### 9.2 wire 差异知会（切换批处置项）

契约引擎 Reply = `encoding/json` 序列化 protoc-gen-go 结构体后剥 base。三条
与手写面的固有差异：

1. **零值省略**：proto3 `omitempty` 使手写面恒出现的 `false/0/""/[]` 缺席
   （如 `admin.is_super=false`、空 `roles`、空 `children`）。处置二选一：
   前端解包层对 iam manage 族归一化缺省（推荐，随选项 1 的前端改造同批），
   或引擎 Reply 增 per-contract `emitDefaults`。
2. **雪花 id**：`uint64` 经 encoding/json 输出数字（JS 2^53 舍入），契约
   消息里 id 一律 `string` 十进制串（manage.proto 已按此）。
3. **json 键**：protoc-gen-go 的 json tag 取 proto 字段名——字段名写
   snake_case 即与手写面逐字一致（无需 json_name）。

### 9.3 排序约束（执行中核实）

- **file 群文件批须排在 presign 分支合并之后**：`feat/presign-direct-upload`
  把契约 JSON 迁到 `contracts-file/api/`、给 `FileService` 增 3 个直传 RPC、
  并新增成员面契约装配（`FileMemberContract` + member 门内挂载）——群文件批
  正需要这套落位与装配，叠其上做零冲突；抢先做则生成物与装配线必撞。
- **iam HTTP 切换须排在 IAM 业务桥退役之后**：`/manage/context` 头注释写明
  网关业务桥每请求服务间拉取本端点做新鲜授权（Cookie 由网关转发），正是
  `feat/bridge-retire-manage-token` 在退役的面；切换前先让桥改走 RPC 面。
- **治理 any-of 码进 RPC**：治理写面（roles/menus/permissions/admins）入 RPC
  时，把 `requireManage` 的码映射表同批写进各 RPC（授权在 RPC 权威执行，
  不依赖承载面——网关上收时无需再补）。

### 9.4 已落地批次

| 批 | 内容 | 落点 | 验证 |
|---|---|---|---|
| 前端前置 | `createIamFetch` 兼容平台统一信封与裸 JSON 双形态（从严判别：success 布尔 + data/code 键在 + 顶层键 ⊆ 信封四键；2xx 失败信封防御性抛错） | ppb-base@`a821dce`（iam-web / iam-manage-web / platform-manage-web 共用此唯一实现） | iam-fetch 21/21（新增 7 条先红后绿）；下游 iam-manage-web 287 用例、iam-web 37 用例全过，typecheck 0 |
| 1b RPC 面 | `iam.ManageService` 三读面：GetManageMe / GetManageContext / ListManageApplications（contracts-iam `proto/manage.proto`，13 消息；kitexstubs `iam/manageservice` + 别名层） | contracts-iam v0.2.0@`2e213a7`、kitexstubs v0.2.0@`315958f`、service-iam@`40988db` | 与手写 HTTP 面同库对拍（RPC 投影 = 手写 wire 同值子集）+ 八类准入码锁；突变去归属校验/投影漂移均必红；全量 19 包 ok |

1b 的准入链：`operator_id`（契约 operator）+ `auth_session_id`（契约 session）
→ `SessionService.ValidateOwnedByID`（新增，会话归属绑定）→
`ResolveManageAccess`（establish=true 仅 me/context）。码与手写面同：
401 IAM-2001 / 403 IAM-3003 / 400 IAM-1001。kitexstubs 生成配方已反推验证：
`kitex -module <kitexstubs 模块>` + go_package 临时改指 `<模块>/kitex_gen/iam`，
产物 import 行 `kitex_gen/iam` → `iam`，`*.pb.go` 换成别名文件。

### 9.5 批次状态（2026-11-24 收口后）

1. ~~**1c RPC 面按族扩**~~ ✅ 全部 42 法一次补齐（见 §9.6）。
2. ~~**桥改走 RPC**~~ ✅ 不再需要——IAM 业务桥已由并行线退役（iam@`727e7fb`），
   网关侧对 `/manage/context` 的每请求拉取随之消失。
3. ~~**HTTP 切换**~~ ✅ 45 条路由整体切换、手写层退役（见 §9.6）。
4. **file 群文件批**：已解锁（presign 分支并入带来 `contracts-file/api/` 与成员面
   契约装配），待开工——5 个 JSON 端点 + 车道保留。
5. **iam 第三方登录绑定端点族 4 条**（`federation_binding_http.go`）仍为手写——
   属并行在途线（第三方登录），待其落地后按同模式收口，届时 `manage_gate.go` 退役。
6. **iam 平台管理面契约上收**：现落 `service-iam/api/iam-manage-http.json`（与
   user-manage 契约同处），按 D1/D6「契约单一归属地」约定应迁
   `contracts-iam/api/`（随下一批 iam 契约变更一并做，避免单独发 tag）。

### 9.6 iam 批次完成实录（2026-11-24，决策「iam 只声明 http」）

**落地形态**（service-iam@`86f19e8`，26 文件 +3490/−2511）：

| 层 | 落点 | 说明 |
|---|---|---|
| 契约声明 | `service-iam/api/iam-manage-http.json` | 45 条路由；identity=manage；`emitUnpopulated: true`；政策一律 self（授权在 RPC）；`/manage/me` 另声明 `omitEmpty: [iam_menus, file_menus]` |
| RPC 契约 | contracts-iam `proto/manage.proto` v0.3.1；kitexstubs v0.3.2 | `iam.ManageService` 45 法 / 95 消息；治理码映射逐条平移自原 `requireManage` 表（见各法注释尾注） |
| RPC 实现 | `internal/transport/iam/manage_kitex*.go` | 准入链：(operator_id, auth_session_id) → `ValidateOwnedByID` → `ResolveManageAccess` → 治理码 any-of；码与原手写面同（401 IAM-2001 / 403 IAM-3003 / 403 IAM-3004 / 400 IAM-1001）；未映射错误落日志后出 IAM-5000 |
| HTTP 装配 | `internal/transport/iam/manage_contract_http.go` | 会话门（认证）→ 请求桥（请求体语义保真）→ servicehttp 引擎 → 本机回环 RPC；`/iam/api/v1/manage/` 前缀挂载（StripPrefix /iam） |
| 引擎增量 | servicehttp v0.2.2 / v0.2.3 | PATCH 入方法白名单；契约级 `emitUnpopulated`（零值不省略）；路由级 `omitEmpty`（声明的顶层键为空则不输出）——均为可选新增，既有 136 条契约路由零变化 |
| 退役 | `manage_http.go` / `manage_security_http.go` / `manage_oauth_http.go` / `manage_routes.go` / `manage_context_http.go` | 5 文件 2479 行（43 个端点 + 全部 DTO） |
| 留存手写 | `manage_gate.go` + `federation_binding_http.go` | 第三方登录绑定端点 4 条及其复用的准入门禁（见 §9.5 第 5 项） |

**请求桥保真的四条原手写层语义**（契约引擎默认行为与之不同，逐条对齐）：

1. 带体方法（POST/PUT/PATCH）空体 / 坏 JSON / 类型不符 / 超 8KB → 400 IAM-1001
   （引擎默认 400 SYSTEM-400）；
2. 全量替换端点的列表键（`menu_keys` / `role_ids` / `permission_codes`）缺席或
   null → 400（防误清空；空数组=清空）；
3. 请求体雪花 id 兼容旧 JSON 数字字面量（>2^53 按原文精确转十进制串）；
4. `allowed_scopes` 的「出现才替换」：repeated 字段过线缆后 nil/空不可分，以
   消息 presence（`ManageScopesUpdate`）表达——缺席/null=不改、[]=替换为空集。

**wire 保真差异闭环**（首轮回归 4 例，均为投影缺口，逐条补声明而非放宽断言）：

| 差异 | 处置 |
|---|---|
| context 菜单节点 `menu_icon` 原为 `json:",omitempty"`，零值投影下以空串出现 | proto 改 `optional string menu_icon`（未置即省略） |
| `/manage/me` 的 `iam_menus` / `file_menus`「非空才出现」，零值投影下恒为 `[]` | 引擎增路由级 `omitEmpty`（v0.2.3），契约逐键声明 |
| 一处测试直接按顶层键反序列化原始响应体 | 测试助手 `doManageRaw` 对成功体返回 data 原文（失败体原样） |

**验证**：

- service-iam 全量 20 包 ok / 0 FAIL；原约 4800 行管理面 e2e 仅改测试助手（解一层
  信封），断言零改动；
- 契约面专项 3 组（信封形状 / 零值投影 / omitEmpty；请求桥请求体语义与
  allowed_scopes presence；会话门与身份通道防伪造）+ RPC 面单测；
- 红突变三则各自必红：RPC 治理门禁失效、请求桥列表键保护失效、会话门 401 码漂移；
- **真实进程冒烟 49 步**（备用端口 + 临时库起服；生产装配线——契约面经本机回环
  RPC 打到自身 Kitex 口，`lsof` 实证；读面 21 条 + 写面全生命周期 + 错误路径 +
  门禁 + 未被影响的面；服务端日志零 panic）。

**消费方核查**（成功体由裸 JSON 变为信封）：

- 前端：iam-web / iam-manage-web / platform-manage-web / base-manage-web 全部经
  `createIamFetch`（ppb-base@`a821dce` 已支持双形态解包）——零改动；
- 网关：IAM 业务桥已退役，无服务间对 `/manage/context` 裸 JSON 的消费；
- 已过时、未改（知会）：`ppb-base/tools/manage-acceptance-next/run_acceptance.py`
  （2026-10-29 的验收 harness——仍读 biz_key 字段并走已退役的业务桥，改造前
  即失效；其 iam 平台管理面调用现还需解信封，建议退役或重写）；
  `ppb-base/tools/endpoint-audit`（`inventory/native_iam.go` 仍把这 45 条登记为
  「手写原生面」并引用已删文件行号，测试不红但清单已过时——属在册的
  「endpoint-audit 引用面刷新」待办）。

**冒烟顺带查出的既有缺陷**（未改，待处理）：`PlatformService.CreateRole` 查重只看
未删除行而删除是软删——「删角色后重建同名角色」撞唯一键返回 500 IAM-5000
（权限点 / 菜单的建删是否有同型问题未核）。
