# PPB IAM · 文档导航

> 2026-11-18 更新。server-iam 及认证前端已在源码中存在；本轮目标是拆入 ppb-iam，工程迁移尚未执行。历史设计和运行验收按各自日期、SHA 核对。

[返回文档中心](../README.md)

本轮目录目标为 ppb-iam/service-iam、iam-web、iam-manage-web，先读 [跨仓架构入口](../architecture/README.md) 与 [新的 Claude Code 提示词](../architecture/implementation/CLAUDE_CODE_PROMPT.md)。统一用户、公共资料、认证和平台授权继续归 IAM，聊天组织和成员归 Chat，各产品管理业务扩展。当前源码仍位于 ppb-base；MaxKey 为产品形态参考。

## 阅读顺序

1. [PRD](PRD.md)：最新范围、主体与服务职责。
2. [认证与应用接入](pr/01-认证与应用接入.md)、[前端与交互](pr/02-前端与交互.md)。
3. [平台角色菜单权限](pr/03-平台角色菜单权限.md)：角色分配页面按钮、批量生效。
4. [技术大纲](tech/技术大纲.md)、[数据模型](tech/数据模型.md)。
5. [SQL入口](tech/sql/README.md)、[完整SQL](tech/sql/schema.sql)、[字段字典](tech/字段字典.md)、[命名调整](tech/字段命名调整.md)。
6. [注册与登录流程](tech/注册与登录流程.md)、[迁移计划](tech/迁移计划.md)。
7. [验收入口](ac/README.md)、[架构决策](adr/架构决策.md)、[设计验证记录](eval/SQL设计验证记录.md)。

8. 本次迁仓使用 [跨仓执行提示词](../architecture/implementation/CLAUDE_CODE_PROMPT.md) 与 [实施进度](../architecture/implementation/PROGRESS.md)。原 [IAM v0.4 实施入口](implementation/README.md)、[历史提示词](implementation/CLAUDE_CODE_PROMPT.md) 和 [历史准备状态](implementation/执行状态.md) 按原任务范围阅读。

## 工程和依据

当前代码仓为 [maibanku/ppb-base](https://github.com/maibanku/ppb-base)，目录为 server-iam、iam-web、iam-manage-web。目标为独立 ppb-iam 仓，协议和 SDK 留在 ppb-base 按领域发版。最新静态起点与限制见 [现状核对](../architecture/00-现状与架构决策.md)。

以下为 v0.4 历史分析依据，不能替代本轮现状核对。原代码分析基于提交 18cd1c9be4331beee4836667066c295a09185e29；本轮另外读取仓库 deploy/sql/user、身份凭证、角色、会话、菜单种子、outbox及存储规范。实施前复核最新代码，本文不宣称仓库代码已按新设计改造。

## 维护约定

产品规则以PRD/pr为准，技术契约以tech为准，物理列以schema.sql为准；字典/命名表由SQL设计生成。所有SQL列至少两个单词snake_case，OIDC对外标准字段不改名。文档和SQL同步维护，旧v0.1方案由本版替代。其他业务文档须在实际接入时分别更新，不能默认为已迁移。

## 版本

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.5 | 2026-11-18 | 更新独立 ppb-iam 目标和跨仓执行入口，保留历史产品设计 |
| v0.4 | 2026-10-27 | 统一user/IAM、平台角色菜单按钮、业务分库、58表SQL及至少双单词字段命名 |
| v0.1 | 2026-10-27 | 自研认证中心、独立前端与迁移方案初稿；职责边界已被v0.4替代 |
