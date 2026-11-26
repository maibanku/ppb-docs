# 接口文档设计：全量 OpenAPI 文档与管理端「接口文档」菜单

状态：设计待评审，2026-11-26。做法已由用户选定（下文方案二），细节是设计阶段的取舍，评审时请重点看第 9 节。

## 1. 要解决什么

平台的 HTTP 接口现在没有任何一份能在运行时查看的文档：

- 接口靠 proto 加契约 JSON 声明，代码里没有 Swagger 注解，也没有 OpenAPI 文件。
- 网关原来的 `/swagger` 页面和接口目录工具在 2026-11-13 网关透明化迁移时删除（ppb-gateway 提交 dc85817）。管理端 chat 插件里的隐藏页 `/chat/api-docs` 内嵌的就是它，现在是 404。
- 契约路由 273 条里 46 条的方法没有像样的说明：12 条完全没有注释，34 条的注释只是一个权限标签或一个分节标题。59 条手写路由没有机读的请求和返回说明。

用户要的结果：

1. 每个接口都有文档：路径、参数、请求、返回、权限。
2. 管理端侧边栏有一个「接口文档」菜单，有权限的人点开就能查。

## 2. 目标、非目标、反目标

目标：

- 一份 OpenAPI 3.0 文档覆盖全部 HTTP 接口：契约路由 273 条和手写路由 59 条。
- 文档和线上的实际行为一致。少数接口的鉴权、请求体或查询参数和「契约加 proto」推出来的不一样，这些差异要在文档里写对。
- 文档从契约和 proto 生成，不手写两份；契约改了重跑生成器即可。
- 生成器在接口缺说明时直接报错，缺文档不能再悄悄发生。
- 管理端有菜单、有页面，按权限可见，生产环境也能开着。

非目标：

- 字段级注释还缺的 418 个顶层字段（IAM 占 244），另开一批。
- 清理旧 `/swagger` 的残留（网关配置里的 `docs.enabled`、各管理端 vite 代理里的 `/swagger`、chat 插件的隐藏页 `/chat/api-docs`）。
- 每个服务在运行时自己生成文档（见方案三）。
- 内部 RPC 和邮件协议（SMTP、IMAP）不进这份文档。WebSocket 只在附录里列出报文类型。
- 邮件服务的手写路由覆盖测试。邮件现在没有手写路由，但有九条以上在途分支在改它，这批不碰；等它的 4 条流式接口落地时补。
- 页面里的「Try it out」。管理端在 IAM 登录模式下浏览器里没有管理令牌，试发请求会 401，所以页面只读。

反目标（做成这样算失败）：

- 文档匿名可读。
- 文档和实际接口对不上却没有报警。
- 管理端首屏加载明显变慢。

## 3. 现状事实

以下都在 2026-11-26 对照代码核对过，括号里是出处。

**接口怎么声明**

- HTTP 路由唯一声明地是契约 JSON：`contracts-*/api/*-http.json`（im 的三份在 `ppb-chat/service-im/api/`，iam 的两份在 `ppb-iam/service-iam/api/`）。每条路由有方法、路径、RPC、请求和响应消息名、参数绑定、权限策略。
- 字段和注释在 proto 里。proto 没有 HTTP 注解。
- 引擎 `ppb-base/platform-sdk/servicehttp` 负责挂载和绑定。请求体用 encoding/json 解码；响应有两种投影：没声明 `emitUnpopulated` 的契约零值字段不出现，声明了的走 protojson，字段齐全、64 位整数是十进制字符串。两种投影的键名都是 proto 里声明的字段名。
- `iam-manage-http.json` 的路径写的是 `/api/v1/manage/*`，服务端用 `http.StripPrefix("/iam")` 挂在 `/iam/api/v1/manage/` 下（`manage_contract_http.go` 的 `ManageContractPrefix`）。它和 im 的同路径路由不冲突。

**数量**

- 契约路由 273：im 88、iam 49、file 15、camera 29、mail 92。
- 手写路由 59：iam 44（会话面 15、成员登录链 3、第三方登录 6（含 GitHub 回调，路径是常量 `/iam/api/v1/federation/github/callback`）、登录方式绑定 9、OIDC 库端点 10、管理令牌换发 1）、file 14（上传下载 7、群文件 7）、im 的 `/ws` 1。
- 只在服务自己的端口上、不经网关的 HTTP 入口：im 的 `POST /im/rtc/webhook`（LiveKit 签名回调），以及 15 个系统端点（网关 `/ping`；iam 的 `/ping`、`/healthz`、`/metrics` 和 OIDC 库带的 `/ready`；im 的 `/healthz`、`/metrics`；file 的 `/ping`、`/metrics`；camera 和 mail 各有 `/ping`、`/healthz`、`/metrics`）。这些只在文档附录里列出。

**少数接口的线上行为和「契约加 proto」不一致**

纯按契约和 proto 生成会把这些写错，生成器自己发现不了：

- camera 主体面的契约整份标的是匿名，但 10 条里只有 `POST /api/v1/camera/guest-sessions`、`POST /api/v1/camera/auth/sms`、`POST /api/v1/camera/auth/apple`、`GET /api/v1/camera/templates` 是真匿名，其余 6 条要相机主体令牌（`service-camera/cmd/server/service_http_wire.go` 的 `cameraAnonWhitelist`）。
- `POST /api/v1/camera/auth/sms` 是一路由两阶段：请求体没有 `code` 走发码，有 `code` 走登录。契约只登记了发码。
- `PATCH /api/v1/manage/oauth-clients/{client_id}` 的 `allowed_scopes` 线上是 JSON 数组，proto 里是包装消息，由 IAM 的请求桥改写（`manage_contract_http.go` 的 `scopesWrap`）。
- IAM 三条全量替换路由的列表键必须在请求体里出现，缺席返回 400（同文件的 `manageRequiredBodyKeys`）。proto3 表达不了必填。
- im 的 `POST /api/v1/user/register` 和 `POST /api/v1/user/invitations/accept` 成功时响应的 `data` 里多一个 `token`（`service-im/cmd/server/member_mint_forward.go`，凭据签发成功才有）。
- 查询参数 `page`、`pageSize` 不在契约的绑定里，由服务端的分页桥注入：im 的 5 条列表路由（`GET /api/v1/manage/` 下的 `members`、`sessions`、`friends`、`friend-requests`、`audit/chat`，见 `service-im/cmd/server/manage_wire.go` 的 `nestedPageRoutes`）和 iam 的 `GET /api/v1/manage/audit/iam`。
- IAM 管理面的请求体里 `application_id`、`user_id` 两个键也接受 JSON 数字（兼容旧写法），proto 里是字符串。

**注释覆盖**

合格线：方法注释去掉权限标签（形如 `[iam.role.manage]`）和分节标题（形如 `---- 角色 ----`）之后必须有正文。

- 契约路由对应的方法 273 个，按这个口径缺说明 46 个：
  - iam 管理面 33 个，在 `contracts-iam/proto/manage.proto`。它们现在的注释只有行尾的权限标签。
  - im 11 个：`OrgCompatService` 的管理面 9 个（`CreateMember`、`UpdateMember`、`DeleteMember`、`EnableMember`、`AdminRevokeSession`、`AdminRevokeAllSessions`、`AdminForceUnfriend`、`AdminListFriendRequests`、`AdminSetPlatformSetting`）和成员面 2 个（`PutProfile`、`PutPreference`）。
  - iam 的 `AdminCompatService.AdminAuthz`（`GET /api/v1/manage/my-perms`）。
  - file 的 `FileService.AdminRestoreTakedown`。
- 不挂 HTTP 的内部 RPC 53 个，缺说明 3 个，都在 iam：`AdminCompatService.RbacVersion`、`IamService.ValidateSession`、`IamService.RevokeMemberSession`。
- 权限标签是机读的：iam 管理面 45 条路由在契约里写的策略一律是 `self`，真正的治理码只写在 proto 行尾的标签里（42 个方法有）和 Go 代码里。
- 手写路由的处理函数：iam 会话面、成员登录链、管理令牌换发、file 上传下载和群文件、im 的 `/ws` 都有文档注释；第三方登录 6 个和登录方式绑定 9 个处理函数没有，共 15 个。

**管理端菜单怎么来**

- 菜单唯一来源是 IAM：`GET /iam/api/v1/manage/context?surface_key=…` 的 `menus`（`base-manage-web/src/core/menu-engine.ts`）。
- IAM 侧的菜单、权限码、内置角色在 `ppb-iam/service-iam/internal/platformadmin/registry/catalog.go` 里用 Go 代码声明，`cmd/migrate -seed-platform` 幂等落库。`deploy/scripts/start-all.sh` 第 241 行每次启动都会跑。
- 清单变更要递增 `CatalogVersion`，并同步 MySQL 镜像 `service-iam/docs/sql-archive/0005_platform_seed.sql`（重生成命令：`UPDATE_SQL_MIRROR=1 go test ./internal/platformadmin/registry -run TestSQLMirror_InSync`）。
- iam 域在 `platform` 入口下是反向投影进来的，所以 iam 的页面在统一后台里出现在「平台治理」根下。
- 前端页面在 `ppb-iam/iam-manage-web/src/plugin.ts`：路由名等于 `menu_key`，路径带 `/iam/` 前缀，守卫是 `canGov(permCode)`（超管或持对应 `iam.*` 码）。权限码常量在 `src/governance-perms.ts` 的 `IAM_PERMS`。

**IAM 的准入链**

- 手写管理端路由复用 `manage_gate.go` 的 `requireManageAny(w, r, establish, codes...)`：没有会话 401 `IAM-2001`，没有管理资格 403 `IAM-3003`，没有对应权限且不是超管 403 `IAM-3004`。

**部署和启动**

- 所有服务以 `ppb-base/deploy` 为工作目录启动。IAM 用 `-config config/iam.yaml`，网关用 `-config config/gateway.yaml -routes config/gateway-routes.yaml`。
- `gateway-routes.yaml` 是生成物：`start-all.sh` 每次启动网关前用 `tools/gen-routes` 重新生成，并提交入库。
- IAM 的配置解析是严格的：yaml 里出现代码不认识的字段会拒绝启动。

**两个会卡住实现的细节**

- `iam-manage-web` 的库构建是单文件（`vite.lib.config.ts` 里 `inlineDynamicImports: true`）。把 Swagger UI 作为依赖打进插件，会让后台首屏多加载约 1.4 MB。所以 Swagger UI 的静态文件不能进前端包。
- 独立 IAM 控制台（8241 端口）的 vite 代理键是 `/iam/api`。页面路由如果以 `/iam/api` 开头，刷新时页面请求会被转给网关而 404。所以菜单路径不能叫 `/iam/api-docs`。

## 4. 方案比较

**方案一：原样恢复网关的 `/swagger`。** 生成器产出文档，网关在 `docs.enabled` 打开时提供页面和 `doc.json`，管理端加菜单并内嵌。改动最小，但文档匿名可读；审计时记过「生产默认关闭」，生产上要么菜单打不开，要么接口面匿名可见。

**方案二：文档放在 IAM 的登录态后面。** 文档同样由生成器产出；由 IAM 提供文档，走它已有的管理端会话校验，并要求一个新权限码；网关不用改。生产也能开着，谁能看可以控制。代价是 IAM 要内嵌 Swagger UI 静态文件并多读一个文档文件。

**方案三：每个服务运行时自己生成文档，管理端汇总。** 文档永远和正在运行的服务一致。但要改公共 SDK、五个服务仓和网关，工作量是前两种的好几倍。

**用户选了方案二**（2026-11-26）。方案三留作以后的方向。

## 5. 总览

```
契约 JSON（12 份）──┐
proto ──protoc──► 描述符 ──┼─► tools/gen_openapi.py ──► ppb-base/deploy/config/api-docs.json（入库）
手写路由说明文件（JSON）──┘         ▲
                                    │ start-all.sh 每次启动前重跑；失败只告警
                                    ▼
                        IAM 读文件（按修改时间缓存）
                                    │
              浏览器 ◄──网关 /iam/* 透传──┤ GET /iam/api/v1/manage/api-docs            页面（Swagger UI）
                                        ├─ GET /iam/api/v1/manage/api-docs.json       文档
                                        └─ GET /iam/api/v1/manage/api-docs/assets/{文件} 静态资源
                                   三个都过 requireManageAny(…, "iam.api-docs.read")

管理端：iam-manage-web 加一条路由 /iam/openapi（iframe 内嵌上面的页面）
        IAM 菜单清单加一页「接口文档」，挂在「平台治理」下
```

## 6. 设计

### 6.1 生成器

位置：`ppb-base/tools/gen_openapi.py`，输入清单 `ppb-base/tools/gen_openapi.manifest.json`，测试 `ppb-base/tools/gen_openapi_test.py`。

- Python 标准库写，不依赖任何 pip 包。描述符自己解码（只需字段名、类型、注释等少量信息）。额外要求本机有 `protoc`，用来把 proto 编译成描述符。
- 用法：`python3 tools/gen_openapi.py --root <工作区根> --out <输出文件>`；`--check` 只比对，和盘上的文件不一致就退出码 1。
- 根目录是 ppb-base 的上一级，清单里的路径都相对它写（`ppb-chat/contracts-im/proto` 这种）。
- 清单里每个服务一条：proto 目录、契约文件列表（每个文件带面、鉴权方式、挂载前缀）、手写路由说明文件、逐条覆盖（见下文）。
- 和 `deploy/route-manifest.yaml` 交叉核对：那里列出的契约文件必须都在本清单里，缺了就报错并点名。两个清单以后都要维护，这一条是防漏。

生成规则（基本规则已在原型上验证过，原型产物通过官方 OpenAPI 3.0 schema 校验；逐条覆盖、合格说明、权限标签是审阅之后加的，还没实现）：

- 每条契约路由一个操作。`operationId` 是 `包名.服务名.方法名`；`tags` 是「服务 · 面」。
- `summary` 和 `description` 取 proto 里方法的注释。去掉权限标签和分节标题之后必须有正文，否则报错。行尾权限标签里的码解析成扩展字段 `x-ppb-perms`（竖线分隔的几个码是「任一命中」，原样列出）。
- 路径参数来自路径模板，类型取绑定里的 `kind`（`string`、`positive32`、`positive64`）；其余绑定是查询参数。参数说明取请求消息里对应字段的注释。
- `POST`、`PUT`、`PATCH` 带 JSON 请求体，schema 由 proto 消息生成，顶层 `base` 字段去掉。响应是成功信封，`data` 的 schema 由响应消息生成，同样去掉 `base`。另有 `default` 响应是失败信封。
- 两种投影分别生成：默认契约零值省略；`emitUnpopulated` 契约响应字段齐全、64 位整数是字符串、枚举是名字。iam 两份契约投影不同，带 `__plain` 后缀的是 encoding/json 那一种。
- 鉴权：成员面是成员令牌，管理面是管理令牌，`iam-manage-http.json` 是 IAM 会话 Cookie。匿名面不要求。相机主体面按逐条覆盖写（见下文）。
- 扩展字段 `x-ppb-*` 带上 RPC 名、契约文件、权限策略、审计动作等契约里的信息。
- 附录（扩展字段，不是 OpenAPI 标准内容）：各服务系统端点、网关前缀族、WebSocket 报文类型。
- 产物不含时间戳，同样的输入产出逐字节相同的文件，`--check` 才可靠。

**逐条覆盖。** 第 3 节列的那几类差异，靠清单里每个服务的 `overrides` 段修正。键是「方法加路径」，可以改这些：

- `security`：鉴权方式。
- `required_body_keys`：请求体里必须出现的键。
- `request_patch`、`response_patch`：对生成的请求体或响应做增补或改写，例如把某个字段从对象改成数组，或给 `data` 加一个字段。
- `extra_params`：不在绑定里、由服务端注入的查询参数。
- `description`：补充说明，例如两阶段、兼容旧写法。

每条覆盖都必须命中一条现存的路由，命中不到就报错。首批写进清单的是第 3 节列出的全部差异：

1. camera 主体面 6 条改成要相机主体令牌（文档里新增一种鉴权方式 `cameraSubject`）。
2. `POST /api/v1/camera/auth/sms` 补两阶段说明和带 `code` 时的返回。
3. `PATCH /api/v1/manage/oauth-clients/{client_id}` 的 `allowed_scopes` 改成数组。
4. 三条全量替换路由的必填列表键。
5. im 两条注册类接口的响应 `data` 加上 `token`，说明签发失败时没有。
6. 6 条列表路由加查询参数 `page`、`pageSize`。
7. IAM 管理面的说明里写一句：`application_id`、`user_id` 也接受 JSON 数字。

生成器在这些情况下报错退出：

- 某条契约路由对应的方法没有合格说明（去掉权限标签和分节标题后没有正文）。
- 逐条覆盖没有命中任何一条路由。
- 手写说明文件里某个操作缺 `summary` 或缺 `responses`。
- `$ref` 指向不存在的 schema，`operationId` 重复，路径参数没声明。
- 同一个「方法加路径」在契约和手写说明里重复出现。
- 清单里的目录或文件不存在。

### 6.2 手写路由说明文件

这些路由没有契约，也没有 proto 消息，只能对着代码写。格式是 OpenAPI 片段的 JSON（`paths` 加可选的 `components.schemas`），生成器合并进主文档，并给每个操作标上 `x-ppb-source: handwritten`。

位置放在各服务仓的契约 JSON 旁边：

| 文件 | 覆盖 | 条数 |
|---|---|---|
| `ppb-iam/service-iam/api/iam-handwritten-api-docs.json` | 会话面、成员登录链、第三方登录（含 GitHub 回调）、登录方式绑定、OIDC 端点、管理令牌换发 | 44 |
| `ppb-file/contracts-file/api/file-handwritten-api-docs.json` | 上传下载、群文件 | 14 |
| `ppb-chat/service-im/api/im-handwritten-api-docs.json` | `/ws` 握手 | 1 |

每个操作必须有 `summary`、`responses`、`x-ppb-code`（代码出处）。请求和返回的字段、错误码要读处理函数和它调用的服务代码来写，不凭名字猜。OIDC 的 10 个端点是第三方库的默认端点，只写用途和标准参数，响应引用 OIDC 规范。

防漂移：每个服务仓加一个 Go 测试，一边扫代码里手写注册的路由，一边读说明文件，断言两边一一对应。路由加了没写文档、文档写了路由已删，测试都红。这些测试跟着各服务仓的 CI 跑。

两样东西不进说明文件、只在附录里列出：im 的 `POST /im/rtc/webhook`（只在 im 自己的端口上，im 的覆盖测试里显式豁免它），以及 IAM 的业务桥前缀 `/iam/api/v1/business/manage/*`。后者的用处是说明管理端在 IAM 登录模式下实际是怎么到达各个管理接口的：后台用 Cookie 调这个前缀下的路径，IAM 的业务桥换成管理令牌再转给对应的服务。

### 6.3 产物与启动脚本

- 产物 `ppb-base/deploy/config/api-docs.json` 提交入库，口径同 `gateway-routes.yaml`。
- `start-all.sh` 在启动 IAM 之前加一步生成，命令是 `python3 tools/gen_openapi.py --root <工作区根> --out config/api-docs.json`。失败只打印告警、不拦启动，IAM 沿用已入库的旧文件。
- `README.md`（`deploy/config/` 下）补一行说明这个文件是什么、怎么重生成。

### 6.4 IAM 提供文档

新增一个子包 `service-iam/internal/transport/iam/apidocs/`，对外一个注册函数。装配点在 `boot_wire.go`，紧跟 `MountManageContract` 之后。

配置加一个键 `api_docs_file`：接口文档文件路径，相对进程工作目录。默认值 `config/api-docs.json`，空串表示不提供。`deploy/config/iam.yaml` 不用改（走默认值）；`service-iam/env/iam-prod.template.yaml` 里写上并说明。这个文件不存在不算配置错误，`-check-config` 不检查它。

三个端点，都只接受 GET，都先过 `requireManageAny(w, r, false, "iam.api-docs.read")`：

| 路径 | 返回 | 缓存 |
|---|---|---|
| `/iam/api/v1/manage/api-docs` | HTML 页面 | 不缓存 |
| `/iam/api/v1/manage/api-docs.json` | OpenAPI 文档原文，`application/json` | 不缓存 |
| `/iam/api/v1/manage/api-docs/assets/{文件}` | Swagger UI 静态文件，白名单两个 | 私有缓存一天 |

行为：

- 文档文件每次请求检查修改时间，变了才重读。
- 文件路径为空、文件不存在或不是合法 JSON：404 `IAM-1007`，提示「接口文档未生成，请运行 ppb-base/deploy/scripts/start-all.sh」。错误信息里不带服务器路径。
- 静态文件只认白名单里的名字，其余 404。
- 网关对 `/iam/*` 是整段透传（`transparent.go` 的 `IAMPassthrough`），网关不用改。网关会加 `X-Frame-Options: SAMEORIGIN`，后台页面和它是同源，可以内嵌。

静态文件：Swagger UI 5.17.14 的 `swagger-ui.css` 和 `swagger-ui-bundle.js` 连同许可证文件（Apache-2.0）放进 `apidocs/static/`，用 `go:embed` 内嵌。页面用基础布局，不需要 standalone 预设。不从外网加载任何东西。

页面配置：打开过滤框，显示扩展字段，按标签和路径字母序排列，关闭「Try it out」，页面、文档和静态资源之间用相对地址。

### 6.5 权限与菜单（IAM 清单）

`catalog.go` 的 iam 域加：

- 权限码 `iam.api-docs.read`，名称「接口文档读取」。
- 页面节点：`SurfaceKey` 为 iam，父节点是根 `iam`，`MenuKey` 为 `iam.openapi`，名称「接口文档」，`RouteKey` 为 `/iam/openapi`，排序 6（排在「审计管理」之后），图标用一个 Element Plus 里存在的名字，勾选时授予 `iam.api-docs.read`。
- 内置角色 `iam_admin` 和 `iam_auditor` 都勾选这一页。`iam_auditor` 的约定是「全部页面只读」，现有测试断言它的页面数等于全部页面数。

配套改动：

- `CatalogVersion` 递增。
- 重新生成 `0005_platform_seed.sql`。
- 更新 `catalog_test.go` 里的数量和清单：iam 权限码 30 变 31，页面 13 变 14，`wantIamCodes`、`iamTreePages` 加新条目。

菜单路径是 `/iam/openapi` 而不是 `/iam/api-docs`，原因见第 3 节。已有环境跑一次 `migrate-iam -seed-platform` 就能看到菜单（`start-all.sh` 会自动跑）。

### 6.6 管理端页面（iam-manage-web）

- `IAM_PERMS` 加 `apiDocsRead: 'iam.api-docs.read'`。
- `plugin.ts` 加一条路由：路径 `/iam/openapi`，路由名 `iam.openapi`，标题「接口文档」，守卫用新权限码，`noCache` 为真（每次进来都重新加载，文档可能已经变了）。
- 新页面 `views/ApiDocsView.vue`：一行工具栏（说明文字、「新窗口打开」指向页面地址、「下载 JSON」指向文档地址）加一个铺满内容区的 iframe，地址是 `/iam/api/v1/manage/api-docs`。写法参照 chat 插件现有的 `ApiDocsView.vue`。
- 前提：后台页面和网关同源。开发态靠 vite 代理；部署态靠反向代理把后台静态站点和网关放在同一个域名下。现在的拓扑就是这样。
- 开发态不需要改代理：统一后台的代理键是 `/iam`，独立 IAM 控制台是 `/iam/api`，都覆盖这三个端点。
- 测试：`plugin-exports.test.ts` 和 `plugin.test.ts` 里的 13 改 14；新页面的测试断言 iframe 地址和两个链接。

统一后台的壳（`platform-manage-web`）不用改，它已经注册了 iam 插件。

### 6.7 补接口注释

契约 proto（只加注释，不改字段；加完用 buf 重新生成，生成物的 diff 应该只有注释）。要补的是第 3 节按合格线数出来的 46 个方法：

- `ppb-iam/contracts-iam/proto/manage.proto`：33 个只有权限标签的方法。补正文时保留行尾的标签。
- `ppb-chat/contracts-im/proto/orgcompat.proto`：`OrgCompatService` 的 11 个，管理面 9 个、成员面 2 个。
- `ppb-iam/contracts-iam/proto/admincompat.proto`：`AdminAuthz`、`RbacVersion`。
- `ppb-iam/contracts-iam/proto/iam.proto`：`ValidateSession`、`RevokeMemberSession`。
- `ppb-file/contracts-file/proto/`：`AdminRestoreTakedown`。

手写处理函数：`ppb-iam` 的 `federation_http.go` 和 `federation_binding_http.go` 里 15 个处理函数补文档注释，写法照 `iam_http.go` 的处理函数。

注释内容要求：一句话说这个接口做什么，有必要时写清前置条件和副作用。不写实现细节。

## 7. 涉及的仓库和文件

| 仓库 | 分支 | 改动 |
|---|---|---|
| ppb-base | `feat/api-docs` | 新增生成器、清单、测试；新增产物 `deploy/config/api-docs.json`；`start-all.sh` 加一步；`deploy/config/README.md` 补说明 |
| ppb-iam | `feat/api-docs` | 配置键；文档端点子包和静态文件；菜单清单、SQL 镜像和测试；手写说明文件和覆盖测试；`iam-manage-web` 的路由、页面和测试；三份 proto 的注释和生成物；15 个处理函数的注释；生产配置模板 |
| ppb-chat | `feat/api-docs` | `orgcompat.proto` 的注释和生成物；`/ws` 的说明文件和覆盖测试 |
| ppb-file | `feat/api-docs` | proto 注释和生成物；手写说明文件和覆盖测试 |
| ppb-docs | `feat/api-docs` | 本文 |

ppb-gateway 和 ppb-mail 不改。

邮件接入有几条在途分支（`feat/mail-integration`、`fix/notify-mail-gaps`）还没合入，会碰到同一批文件：iam 的 `catalog.go`、`boot_wire.go`、`admincompat.proto`，base 的 `start-all.sh`。本设计的改动都是新增的行，合入时解一次冲突。按在途分支当前的 diff 看，改动位置不重叠：`admincompat.proto` 在途改的是第 102 到 117 行（推送记录的消息），本设计改第 50 到 51 行的注释；`boot_wire.go` 在途改的是第 7 到 118 行和第 354 到 371 行，本设计在第 292 行之后加装配。在途分支还在继续变，合入时以实际 diff 为准。

## 8. 验证

每个仓库合入前：

- ppb-base：`python3 -m unittest tools/gen_openapi_test.py`；`python3 tools/gen_openapi.py --check` 退出码 0；`bash -n deploy/scripts/start-all.sh`。
- ppb-iam：`GOWORK=off go build ./... && GOWORK=off go vet ./... && GOWORK=off go test -timeout 120s ./...`（在 `service-iam` 下）；SQL 镜像测试不加环境变量直接跑也通过；`iam-manage-web` 下 `npm run typecheck && npm test && npm run build:lib`；`buf generate` 之后 `git diff --exit-code`。
- ppb-chat、ppb-file：各自的 `go test`、buf 重生成后 diff 为空、覆盖测试通过。

文档本身：

- 用官方 OpenAPI 3.0 schema 校验一次，0 错误，结果记进实施进度。
- 操作数等于契约路由数加手写路由数（按主检出现状是 273 加 59）。
- 每个操作的 `summary` 去掉权限标签和分节标题后非空。
- 第 3 节列的每一处差异，在生成的文档里都能看到对应的修正。

端点（由 iam 的集成测试覆盖，用现有的 sqlite 临时库夹具）：

- 没有会话：401 `IAM-2001`。
- 有会话但不是平台管理员：403 `IAM-3003`。
- 是管理员但没有 `iam.api-docs.read`：403 `IAM-3004`。
- 超管，或持有该权限码：三个端点都 200。
- 文件不存在：404 `IAM-1007`，错误信息里没有服务器路径。
- 静态文件白名单之外的名字：404。

管理端：在统一后台用超管登录，「平台治理」下出现「接口文档」，点开能看到全部标签；没有该权限的角色看不到这个菜单。

最后两项目前只能人工做。在跑的开发栈是别的会话在用的，重启 IAM 之前要先征得同意。

## 9. 设计阶段替你做的取舍

评审时请逐条看，不同意直接改：

1. 文档产物放 `ppb-base/deploy/config/api-docs.json` 并入库；`start-all.sh` 每次启动前重新生成，失败只告警不拦启动。
2. 生成器用 Python 标准库写，额外只要求本机有 `protoc`；输入清单是 `tools/gen_openapi.manifest.json`。
3. 手写路由的说明用 JSON（OpenAPI 片段），放在各服务仓的契约 JSON 旁边；每个服务仓加一个测试保证代码和说明一一对应。
4. IAM 提供三个端点（页面、文档、静态资源），都走现有管理端会话门加新权限码 `iam.api-docs.read`。
5. Swagger UI 的静态文件随源码放进 ppb-iam 并内嵌进二进制，体积增加约 1.6 MB，不从外网加载。
6. 页面只读，关闭「Try it out」。
7. 菜单放在「平台治理」下，路径 `/iam/openapi`；内置角色 `iam_admin` 和 `iam_auditor` 默认勾选；超管直接可见。
8. 配置键 `api_docs_file` 默认 `config/api-docs.json`；不改 `deploy/config/iam.yaml`，只在生产模板里写说明。
9. 生成器在「契约路由对应的方法没有合格说明」时报错，逼着以后新增接口必须写说明。
10. 设计文档放在 `ppb-docs/architecture/api-docs-design.md`。
11. 线上行为和「契约加 proto」不一致的接口，用清单里的逐条覆盖修正，首批覆盖第 3 节列的 7 类差异。不改契约和代码去迁就文档。
12. 注释的合格线：去掉权限标签和分节标题后必须有正文。按这个口径要补的方法是 46 个，比最初说的 12 个多 34 个，多的都在 iam 的 `manage.proto`。
13. proto 行尾权限标签里的码写进文档的扩展字段 `x-ppb-perms`。iam 管理面在契约里写的策略一律是 `self`，没有这一步文档里就看不到这些接口真正的权限码。
14. im 的 `/im/rtc/webhook` 和 IAM 业务桥只在附录里列出，不算操作。手写路由按代码数是 59 条：iam 44 条，比我最初说的 43 条多一条 GitHub 回调。
15. 邮件服务的覆盖测试这批不做，等它的流式接口落地时补。

## 10. 风险

- IAM 二进制增加约 1.6 MB。
- 手写路由的说明是人写的，覆盖测试只保证「有没有」，不保证「对不对」。实现时每一条都要读处理函数确认。
- `api_docs_file` 的默认值只对「以 deploy 为工作目录启动」这种部署形态成立；别的部署要显式配置，否则页面显示未生成。
- 合入时和在途分支有冲突，见第 7 节。

## 11. 留给实施者

- 描述符解码器的写法和测试数据。
- 扫描手写路由的正则和各服务仓覆盖测试的组织方式。
- 页面的具体样式和 Swagger UI 的其余选项。
- 图标：优先 `Notebook`，不存在就换一个 Element Plus 里有的。
- 提交怎么拆分。
