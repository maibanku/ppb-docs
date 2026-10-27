# PPB IAM · 文档导航

> v0.4 · 2026-10-27 · 自研Go方案与目标态SQL；服务未实现，未完成MySQL实例、迁移或协议验收。

[返回文档中心](../README.md)

当前方案：ppb-base 同仓独立 server-iam，内部合并通用用户、公共资料、认证与平台管理授权；聊天组织和成员关系放 server-im，camera/wardrobe 管业务扩展。MaxKey仅为产品形态参考，不接入其运行时。

## 阅读顺序

1. [PRD](PRD.md)：最新范围、主体与服务职责。
2. [认证与应用接入](pr/01-认证与应用接入.md)、[前端与交互](pr/02-前端与交互.md)。
3. [平台角色菜单权限](pr/03-平台角色菜单权限.md)：角色分配页面按钮、批量生效。
4. [技术大纲](tech/技术大纲.md)、[数据模型](tech/数据模型.md)。
5. [SQL入口](tech/sql/README.md)、[完整SQL](tech/sql/schema.sql)、[字段字典](tech/字段字典.md)、[命名调整](tech/字段命名调整.md)。
6. [注册与登录流程](tech/注册与登录流程.md)、[迁移计划](tech/迁移计划.md)。
7. [验收入口](ac/README.md)、[架构决策](adr/架构决策.md)、[设计验证记录](eval/SQL设计验证记录.md)。

## 工程和依据

代码目标仓库：[maibanku/ppb-base](https://github.com/maibanku/ppb-base)。拟建 server-iam、iam-web、iam-manage-web、idl/iam；已有 server-user 逐步迁移退役，不再作为通用资料独立服务。

现状代码分析基于本会话核查提交 18cd1c9be4331beee4836667066c295a09185e29；本轮另外读取仓库 deploy/sql/user、身份凭证、角色、会话、菜单种子、outbox及存储规范。实施前复核最新代码，本文不宣称仓库代码已按新设计改造。

## 维护约定

产品规则以PRD/pr为准，技术契约以tech为准，物理列以schema.sql为准；字典/命名表由SQL设计生成。所有SQL列至少两个单词snake_case，OIDC对外标准字段不改名。文档和SQL同步维护，旧v0.1方案由本版替代。其他业务文档须在实际接入时分别更新，不能默认为已迁移。

## 版本

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.4 | 2026-10-27 | 统一user/IAM、平台角色菜单按钮、业务分库、58表SQL及至少双单词字段命名 |
| v0.1 | 2026-10-27 | 自研认证中心、独立前端与迁移方案初稿；职责边界已被v0.4替代 |
