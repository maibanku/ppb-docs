# ppb-docs · 产品文档中心

产品设计、架构决策和验收集中于此，运行代码在对应代码仓库。2026-11-18 新增跨仓目录改造设计，代码迁移和新模块发布尚未执行。

## 本次架构改造入口

优先阅读 [architecture/README](architecture/README.md)，按顺序核对现状、目标目录、模块边界、迁移计划和验收。

后续本地实施使用 [Claude Code 执行提示词](architecture/implementation/CLAUDE_CODE_PROMPT.md)，实际结果写入 [实施进度](architecture/implementation/PROGRESS.md)。

目标为八个仓库，计划新建 ppb-iam、ppb-gateway、ppb-file。公共框架放在 ppb-base/go-framework，目录名至少两个单词。IAM、网关、File、IM、Camera 后端分别迁入目标 service-* 目录。此处记录目标结构，现有代码位置见下表。

## 项目

| 项目 | 文档导航 | 本次静态核对的代码位置 | 本轮目标 |
|---|---|---|---|
| 跨仓架构 | [architecture/README](architecture/README.md) | 五个现有仓库，快照见现状文档 | 八仓、远程按需依赖、独立构建和交付 |
| 网关 | [gateway/README](gateway/README.md) | ppb-base/server-gateway | ppb-gateway/service-gateway，保持透明 HTTP／WS 代理 |
| 统一认证与用户 | [iam/README](iam/README.md) | ppb-base/server-iam、iam-web、iam-manage-web | ppb-iam/service-iam 与两个前端 |
| 文件平台 | [file/README](file/README.md) | ppb-base/server-file、file-manage-web | ppb-file/service-file 与管理端 |
| 聊天 | [通话专题](chat/calls/README.md) | 后端 ppb-base/server-im，客户端和管理端在 ppb-chat | ppb-chat/service-im |
| AI 相机 | [camera/README](camera/README.md) | 后端 ppb-base/server-camera，iOS／管理端在 ppb-camera | ppb-camera/service-camera |
| AI 衣橱 | [wardrobe/README](wardrobe/README.md) | ppb-wardrobe，Go 后端在 wardrobe-manage-web/server | 保留现有工程路径，本次不自动接入统一身份和文件 |
| ID 与删除字段 | [数据库变更](database/2026-11-14-id-only/README.md) | 当前源码和专项迁移记录 | 按当前证据核对，避免恢复历史字段 |

服务源码存在与完整业务、数据迁移或生产验收通过是不同状态。历史完成记录按其日期和 SHA 使用，后续实施先核对实际仓库和环境。

## 文档组织

产品目录通常包含 README、PRD、pr、ac、tech、adr 和 eval。architecture 是跨产品工程设计入口，额外包含 implementation 下的执行提示词与进度，不重排各产品已有需求和 SQL 文档。

~~~text
architecture/
  README.md
  00-现状与架构决策.md
  01-目标目录结构.md
  02-模块边界与服务调用.md
  03-版本发布与迁移计划.md
  04-验收标准.md
  implementation/
    CLAUDE_CODE_PROMPT.md
    PROGRESS.md
~~~

## 维护约定

- 产品规则以对应 PRD／pr 为准，技术和数据契约按 tech 与当前专项决策核对，验收用 ac 或对应架构验收矩阵。
- 本轮仓库、目录、模块和交付决策以 architecture 为准。旧执行提示词作为历史记录，不覆盖新的迁移范围。
- 修改事实出处后同步导航和执行入口，避免复制出多份漂移正文。
- 文档改动在 ppb-docs 提交。代码引用写仓库名、路径和必要 SHA。
- 凭据、个人环境地址和运行数据不作为文档示例。未执行的验证明确标记。

## 版本

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.6 | 2026-11-18 | 新增八仓目录改造、go-framework、按领域协议和 SDK、独立构建及 Claude Code 交接 |
| v0.5 | 2026-10-27 | 新增file独立文件平台：前后端、多业务引用、标识决策、大文件视频与常用API |
| v0.4 | 2026-10-27 | IAM统一用户/认证/平台授权，加入双单词字段规范及58表SQL |
| v0.3 | 2026-10-27 | 新增 IAM 设计基线：同仓独立认证服务、前端拆分、迁移与验收 |
| v0.2 | 2026-10-26 | camera 自 ppb-chat/docs 迁入；确立统一目录结构（README/PRD/pr/ac/tech/adr/eval） |
| v0.1 | 2026-10-26 | 建仓，wardrobe 需求基线 v1.1 入驻 |
