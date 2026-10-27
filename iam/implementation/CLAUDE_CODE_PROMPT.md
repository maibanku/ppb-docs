# Claude Code · PPB IAM 跨仓实施提示词

你是本地工作目录中的实现负责人。用户已授权按照 ppb-docs/iam 改造 PPB，要求新建独立分支、实际编码、运行检查，边写边提交。请执行工作，不要停留在方案、骨架、TODO 或生成待执行提示词。

## 1. 仓库与启动

当前目录是四个仓库共同的父目录：ppb-docs、ppb-base、ppb-chat、ppb-camera。先确认目录和 git remote 对应 maibanku 的同名仓库，读取每个仓库适用的 AGENTS.md、CLAUDE.md、.claude/rules 及 README；不要假定附加目录自动加载全部规则。

本次默认统一分支名：`feat/iam-v0.4`。若启动指令明确给出其他feat/分支，以启动指令为准；四个仓库必须同名，包括 ppb-docs。

- 已有本地目标分支：检查当前分支和工作区再切换，不重置已有进度。
- 远程有目标分支而本地没有：fetch 后建立跟踪分支。
- 本地/远程均没有：从最新 origin/main 新建目标分支。
- 发现非目标分支上的用户修改时，保留原样，使用独立 worktree 或停止该仓库切换并明确阻塞；不能 stash/reset/clean 掩盖改动。
- 不得在 main 直接实现，不得 force push，不自动合并或部署生产。bootstrap 不负责提交代码；提交由你按下面规则完成。

启动后先在 ppb-docs/iam/implementation/progress.md 记录四仓库起点 SHA、工具版本、基线结果和第一条纵向实现路线，立即提交该计划检查点，然后继续实现。

## 2. 边写边提交（硬性要求）

每完成一个可独立解释、可验证的小步骤，在对应仓库检查 diff、执行相关检查、选择具体文件 git add，再 git commit。不要等全部 IAM 做完才提交，不要把无关修改混入。

示例提交粒度：

1. `chore(iam): establish implementation baseline and migration checklist`
2. `feat(iam): add account models and migration verification`
3. `feat(iam): implement registration and credential verification`
4. `feat(iam): implement authorization code and PKCE exchange`
5. `feat(authz): derive admin permissions from role menu assignments`
6. `feat(admin): use IAM login and permission snapshot`
7. `feat(chat): integrate IAM account and workspace initialization`
8. `feat(camera): integrate IAM session and account bootstrap`
9. `test(iam): verify revocation and cross-repository integration`

每次提交前：查看 status/diff，检查密钥/凭证未入库，执行与该步骤匹配的构建或测试。检查失败先修复，不提交声称通过的假记录。若只做未可运行的基础阶段，明确其性质和下一步，不把空骨架当成功能。

每个可运行阶段通过后，分别推送到各仓库同名功能分支，首次 `git push -u origin feat/iam-v0.4`，后续正常 push。网络/凭据失败保留本地提交并记录，不强推、不转而提交 main。跨仓不存在原子提交：按“新增兼容契约/提供方 → 消费方 → 联调记录”排序，文档记录相互匹配 SHA。

progress.md 在每个阶段更新：需求编号、改动文件、各仓库分支/提交 SHA、实际命令/结果、迁移状态、遗留与下一步。不把该记录所属提交本身的 SHA 递归写进同一提交；最终交付报告记录最后一组 SHA。每个阶段结束提交并同步进度文档。

## 3. 单一事实源与现状核查

按顺序阅读：

1. ppb-docs/iam/README.md、PRD.md、adr/架构决策.md。
2. pr/01-认证与应用接入.md、pr/02-前端与交互.md、pr/03-平台角色菜单权限.md。
3. tech/技术大纲.md、tech/数据模型.md、tech/注册与登录流程.md、tech/迁移计划.md。
4. tech/sql/schema.sql、tech/字段字典.md、tech/字段命名调整.md。
5. ac/ 全部验收规则与 eval/SQL设计验证记录.md。

文档中的58表DDL是目标态，不是存量升级脚本，也不代表完整业务实现。先核对最新代码，不用旧聊天描述替代实际代码。发现设计冲突，先在 ADR 记录最小修订并同步 SQL/字典/验收，再继续；不能静默改变业务边界。

已核查工程落点（仍须重新确认）：

- ppb-base/server-user：现有账号/组织/管理员服务；不存在名为 ppb-user 的服务目录。
- ppb-base/server-gateway、server-pkg/authzport、internalauth、idl：网关与共享安全契约。
- ppb-base/server-im：聊天服务；server-camera：相机服务。它们不在对应客户端仓库。
- ppb-base/base-manage-web：Vue3 管理底座，已存在登录、分域权限、菜单和插件机制。
- ppb-chat/chat-manage-web 和 ppb-camera/camera-manager-web：通过相邻目录 file: 依赖底座，必须同目录联调。
- ppb-chat/chat-client：wxWidgets C++ 客户端；chat-desktop：Tauri/Vue 客户端，不能遗漏其一。
- ppb-camera/camera-ios-app：iOS App，AccountKit/NetworkKit 等包需按实际依赖接入。
- go.mod、package.json、构建配置和 tools/ci.sh 是工具链与检查命令依据，不凭空升级版本。

## 4. 最新目标架构

在 ppb-base 内新增独立 Go module server-iam，独立 ppb_iam 库、配置、镜像和部署入口。内部模块：account/profile/identity/credential/authentication/federation/oauthserver/session/application/platformauthz/audit。

通用用户、公共资料、认证和平台管理授权归 IAM；不再长期保留第二套平台用户主体。server-user 分阶段迁移退役。chat组织、成员、部门、邀请、组织角色迁入 server-im/ppb_im；camera/wardrobe业务扩展各自保存。wardrobe本次只对齐已设计契约与SQL，不凭空创建完整衣橱业务。

现有 user_id 和 user_biz_key、消息/文件/订单归属尽量保持。平台管理员从统一用户取得管理资格，密码只存统一凭证。独立旧管理员与成员即使同邮箱也不能自动合并，需受控确权/审核与映射报告。

## 5. 数据与迁移

- 全部新SQL列名至少两个单词，以 _ 连接；主键/业务键采用实体前缀，公共列 create_time/update_time/deleted_flag/deleted_time。
- 沿用雪花主键（不得临时改自增）、业务键、InnoDB/utf8mb4_unicode_ci、身份等精确字段 bin 排序、逻辑关联与KV风格。
- profile保存固定资料；个人可增长开关放各域 preference KV；user_setting是全局配置。密码/MFA/授权事实不放随意KV。
- 不直接运行目标schema覆盖旧ppb_user或现有业务库。提供迁移版本、回填、冲突检查、switch_check、演练与回退。同库约束和跨库幂等由真实实现保障。
- 实施阶段按范围创建需要的表，但对已声明支持的功能必须闭环，不能建58张空表就宣称完成。
- 删除/撤权必须检查 deleted_flag、状态、有效期、授权版本及关联有效性。关系唯一键与软删恢复一致。
- 保留邮箱/邮件签名/文件关联等现存能力；邮件业务字段迁回邮件域，不得因IAM重构丢弃。

## 6. 平台角色、菜单与按钮

platform_admins（含is_super）→ platform_admin_roles → platform_roles → platform_role_menus → platform_menus → platform_menu_permissions → platform_permissions。

这是唯一普通授权路径，不另建 platform_role_permissions 双权威，也不逐人复制菜单。菜单包含目录、页面、按钮、隐藏操作；关联映射表示选中节点实际授予的API权限。多角色并集，同应用域限制。

新按钮默认不授予既有角色；页面不自动带全部按钮；补目录祖先只为展示；按钮需有效页面；停用/删除祖先阻断子树；is_hidden仅展示控制。服务端仍验证API权限与资源范围。

权限变化更新应用/角色/个人授权版本并可靠使缓存失效；同角色下所有管理员同步生效。菜单/权限映射修改本身防越权和自我提权。最后有效超管/组织owner撤销串行保护。

保留既有治理操作仅超管的安全语义，迁移时明确比较与审核；不要因为获得菜单就放开原治理门。平台超管不自动访问私人照片/聊天内容。

## 7. 认证协议与端到端纵向实现

使用维护中的标准协议库并记录版本/许可证，先验证适配，再实现 OIDC 授权码+PKCE S256、Discovery、JWKS、ID token、UserInfo、刷新轮换和撤销。不要自制简陋JWT登录替代OIDC。

事务绑定发起方，校验state/nonce/PKCE/issuer/audience/签名/回调/client/scope/过期；授权码单次消费；刷新重放撤销族；密钥轮换可验证。ID Token不是业务API凭证。公开客户端无secret。上游第三方与下游授权事务隔离。

Web由后端处理回调和业务会话，HttpOnly/Secure Cookie与CSRF/Origin保护，禁止通过URL或localStorage传长期凭证。现存Bearer接入可兼容过渡，但不能绕过IAM策略或将IAM token塞进旧HS256解析器。

新增 iam-web 独立认证/账户门户、iam-manage-web 认证及平台授权后台；尽量复用现有Vue/设计规范。调整 base-manage-web 统一登录、角色勾选树、按钮权限和菜单快照；同步chat/camera插件入口与依赖，不复制三套底座。

普通平台注册创建统一主体/身份/profile，按方式写密码或外部绑定；不创建管理员。camera首次进入按user_id幂等开通业务账号，失败重试不删除IAM主体、不重复送额度。chat通过加入/邀请建立组织成员，切换组织重新检查资格。

接入两个chat客户端和camera iOS：使用系统浏览器/受控回调及PKCE，安全保存凭证，处理取消/超时/重放/重启/退出。开发环境明确可测回调，不把单个演示按钮当客户端完成。

区分IAM会话、授权、管理会话、业务会话。全局停用与退出可靠传播到HTTP和已有WS；单应用退出不误踢其他应用；撤管理员不注销普通账号。MFA/高权限再认证必须在生产管理入口完成。高权限依赖失败拒绝，不自动回退旧密码。

## 8. 实施顺序与完成定义

阶段0：四仓基线、工具版本、调用图与迁移清单；创建/确认分支并提交检查点。

阶段1：server-iam 可启动、账户/凭证/profile持久化、注册登录和迁移验证；真实数据库/SQLite开发适配；健康检查、配置fail-fast、受控首超管初始化。提交并测试。

阶段2：OIDC提供方与业务接入端、门户、后台会话/MFA，先跑通一个管理入口完整链路；正确处理失败。提交并测试。

阶段3：平台角色菜单按钮权威替换、管理页面/按钮与网关/服务端一致；两管理员同角色批量授权/撤销回归。提交并测试。

阶段4：聊天组织数据与角色迁server-im，两个chat客户端、chat后台接入；camera账号、iOS和后台接入；跨仓file依赖构建通过。按仓分步提交。

阶段5：迁移演练、数据归属与权限集合对比、全局退出/撤权/WS/故障恢复联调、发布回退文档。仅在调用方/数据迁移全部达标后退役server-user，否则保留有期限的兼容层并明确未完成。

每阶段均要实际改代码。可自主处理可逆实现选择，长任务保持检查点并持续到完成。真实依赖/凭据缺失时只阻塞依赖部分，继续独立可做工作；禁止伪造运行结果或宣称所有功能完成。

## 9. 验证要求

使用仓库既有工具链与锁文件，先跑基线。Go对变更模块运行build/vet/test，IDL修改从权威源生成，不手改生成桩。Vue各工程实际typecheck/test/build，检查跨仓file依赖。C++/Rust按工程配置编译测试，Swift包与Xcode真机构建分别报告；没有macOS不能声称iOS集成通过。

数据库实际运行MySQL迁移与约束验证，SQLite兼容测试不能代替。覆盖注册并发/身份冲突/改密/恢复、协议负例、管理员资格隔离、分域与跨组织越权、按钮/祖先/软删、同角色两管理员同步变化、缓存故障、HTTP/WS撤销、密码迁移与回退不复活旧凭证。

按 ac/G1–G6 记录证据和需求追踪。文档当前SQL验证记录只证明静态/兼容结构，不是现有工程测试。失败先修复，无法测试写明原因、命令和未验证范围。

## 10. 交付与续做

输出四仓分支、起点/最终SHA、逐阶段提交、已推送/仅本地状态、改动与测试、数据库迁移/回退步骤、如何启动联调、未完成清单。最终如工具和认证可用，可创建各仓互相链接的draft PR；不合并main或执行生产迁移。

中断后先读progress.md和git log/status，从最后验证过的检查点续做，不重新注册用户或重建已有分支。不要重写无关模块、第三方库和锁文件。

所有Key只通过本机安全环境或凭据管理注入，禁止输出/提交；不修改用户现有模型供应商配置。使用智谱等代理时以用户已有配置为准，不猜测模型名、兼容端点或计费方式。

现在开始执行：核查四仓分支和基线，提交阶段0，随后实现第一个真实可测试纵向闭环，持续推进后续阶段。
