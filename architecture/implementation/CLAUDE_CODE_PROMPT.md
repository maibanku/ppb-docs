# Claude Code · PPB 跨仓目录与公共模块改造

这是后续实施入口。当前文档提交只完成设计与交接，代码迁移、模块发布、新建仓库和运行验收均待执行。用户在本地指示实施本任务后，按以下范围推进并维护真实进度。

## 任务目标

把当前 ppb-base 中的服务按本次架构决策迁入对应产品仓。公共框架、领域契约、平台 SDK 和后台底座由 ppb-base 按需发布。新电脑只检出某个业务仓后，可以通过已发布的远程依赖构建，并连接或拉取所需运行服务。

优先交付可构建、可验证的纵向阶段。沿用已有代码、测试和接口规则，保持现有业务与身份兼容。实现中的不确定事实要用代码和实际结果核对，记录证据后再下结论。

## 先读这些文档

1. architecture/README.md。
2. architecture/00-现状与架构决策.md。
3. architecture/01-目标目录结构.md。
4. architecture/02-模块边界与服务调用.md。
5. architecture/03-版本发布与迁移计划.md。
6. architecture/04-验收标准.md。
7. architecture/implementation/PROGRESS.md。
8. 当前阶段相关的 IAM、网关、文件和产品文档，以及 database/2026-11-14-id-only 下的现有记录。

目录、module 路径和发布方式采用本轮架构。产品规则采用对应产品定义，实际状态由源码与运行结果核对。旧 IAM v0.4 提示词和旧网关任务按其历史范围使用，不能再次创建已退役服务、恢复旧 biz_key／deleted_time，或把旧四仓工作区当新任务的必需拓扑。

## 工作区和授权边界

- 本地父目录可命名 ppb，每个 Git 仓库各自管理。先读取用户启动指令及各仓适用的 AGENTS.md、CLAUDE.md、.claude/rules 和 README。
- 枚举真实 remote、分支、HEAD 和工作区。保留已有修改；有冲突时采用隔离 worktree 或其他可回退方式继续。
- 仅初始化当前阶段需要的仓库。新服务仓目标是 maibanku/ppb-iam、ppb-gateway、ppb-file，创建前查存在状态和权限。新建私有服务仓的动作应在用户本次实施授权内；权限不足时记录具体阻塞并完成其他独立工作。
- 建议实施分支为 refactor/ppb-repository-layout，用户指定分支时采用用户指令。已有分支和进度先对账，再继续。
- 小步提交到对应仓的实施分支，检查完成后正常推送。主分支合并、发布到生产及破坏性 DDL 按实际授权执行。
- 本地 go.work 只作为开发便利。正式构建、远程模块验证和镜像构建关闭工作区，避免意外引用本机未提交代码。

## 已确定的落点

| 当前来源 | 目标 |
|---|---|
| ppb-base/server-iam | ppb-iam/service-iam |
| ppb-base/iam-web、iam-manage-web | ppb-iam 同名目录 |
| ppb-base/server-gateway | ppb-gateway/service-gateway |
| ppb-base/server-file、file-manage-web | ppb-file/service-file、file-manage-web |
| ppb-base/server-im | ppb-chat/service-im |
| ppb-base/server-camera | ppb-camera/service-camera |
| ppb-base/server-pkg、idl | 逐包归入 go-framework、contracts、platform-sdk 或业务 |
| 平台门户及公共底座 | 保留在 ppb-base |
| Wardrobe 后端 | 保留 wardrobe-manage-web/server |

轻量框架 module 为 github.com/maibanku/ppb-base/go-framework。IAM／File SDK 分别是 platform-sdk/iam、platform-sdk/file 下的独立 module。协议、驱动也按实际领域或重量分模块，禁止统一根模块自动引入全部能力。

目录树的 user-compat 是现有 user.proto 的兼容落点。IAM 和 IM 同时承接其不同方法，迁移前逐项核对真实 owner。refaccess 回调契约放 contracts/file。生成代码只有一份权威注册，避免同名 descriptor 并存。

## 执行步骤

### P0 建立基线

记录工具版本、每仓 SHA、适用规则、当前可用 Go 模块、主要接口、依赖和已知故障。执行与当前阶段有关的基线检查。只读核对数据结构，避免将目标 SQL 直接覆盖现有库。

在 PROGRESS.md 记录第一组结果、计划和明确的阻塞，提交检查点。随后完成在当前授权和环境内可执行的后续阶段。

### P1 基础模块

先迁移真正通用的 logx、requestid、ID 转换、错误和健康能力。gRPC、GORM、Redis、RabbitMQ、Outbox 使用独立适配模块，迁入相关现有测试。

核心模块不得导入业务 Proto 或 SDK。遇到 servicehttp 的协议绑定先保持在服务接入层，再提取通用机制。RPC 重试、ID 发号节点、缓存和事件持久化行为保持可验证。

### P2 契约与客户端

更新 go_package、Buf 配置和所有消费方 imports，保留 protobuf package、RPC 全名、字段编号及实际线面语义。识别 common.proto 中的业务类型，分批整理，避免一次拆所有协议。

按同一规范实现 IAM 和 File 客户端，检查网络、gRPC、业务错误和成功回执。重点核对 RegisterFileMeta 的业务失败、零 ID、错误 ID 和并发重复请求。ValidateSession 区分身份无效和服务不可用。

使用真实远程版本验证消费方。尚未发布的示例标签不能写为已可使用。依赖发布先于消费升级，已发布 Tag 不覆盖。

### P3 到 P7 服务与前端迁移

按迁移计划分批提取网关、前端、IAM、Camera、IM 和 File。保持提供方兼容后再升级消费方。

- 网关只持有通用代理和路由配置。把同仓扫描改为发布清单输入，已启用服务缺清单必须报错。
- IAM 保留账号、会话、平台授权及现有成员登录／业务桥，保持 issuer、回调、Cookie、签名密钥、用户 ID 和 subject 兼容。
- SDK 连接按服务初始化，实例退出统一关闭。内部凭据、权限和业务访问验证继续有效。
- File 和 IM 分别维护自己的数据。回调是受控接口，不允许依赖业务内部包或跨库读取。
- 前端底座发布库与演示双产物，业务管理端发布插件与独立应用。清理 file: 和跨仓 src／Vite alias，完整平台业务装配归 platform-manage-web。
- 迁移 SQL、配置、任务、测试和脚本。镜像只需要当前仓源码和已发布依赖。

记录同名旧路径和新路径的存在状态。目标仓完成独立构建和回归后，再在原仓移除相关实现并更新部署引用，避免留下两个业务写入权威。

### P8 集成与回退

用干净检出、临时空模块缓存和 GOWORK=off 验证服务。前端从发布包安装并构建。按验收矩阵执行 OIDC、权限、WS、文件、故障和数据回归。

集成环境记录完整的镜像、路由、前端和公共依赖版本。可运行上一组兼容制品回退。未执行的真机、压力、数据库或生产验证如实标记，不代填通过。

## 检查与提交

- 采用仓库现有工具版本和检查命令。当前 go.mod 声明 Go 1.26.0，部分旧 Docker 模板默认 Go 1.25，先核对和对齐实际构建条件，避免顺带无依据升级。
- 每个实际 Go 模块分别 build、test，必要时 vet；根模块测试不会自动覆盖嵌套模块。
- 新测试只针对现有测试未覆盖的明确风险，如 SDK 业务失败回执、路由漏生成、权限拒绝和重复引用。
- 文档变更检查链接、结构和路径；代码生成检查漂移和协议兼容；前端检查类型、测试、构建及发布产物。
- 提交前逐个查看 diff，排除凭据、运行数据和构建产物。优先在临时副本保留来源历史，禁止改写原仓主分支历史。
- 每完成一个可独立解释且验证过的步骤，提交具体文件，并把分支、SHA、检查和遗留写入进度。跨仓组合记录实际匹配版本。

## 阶段报告

报告包含已完成的目录／依赖调整、涉及仓库和提交、实际执行命令及结果、未完成的验收编号、具体阻塞、回退依据和下一步。当前数据、接口和运行行为有矛盾时先列出证据及影响范围，继续完成不依赖该矛盾的工作。
