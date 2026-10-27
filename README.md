# ppb-docs · 产品文档中心

所有产品的设计文档集中于此；**代码在各自独立仓库**，本文档中心不存放代码。

## 项目

| 项目 | 导航 | 代码仓库 | 状态 |
|---|---|---|---|
| AI 相机（camera） | [camera/README](camera/README.md) | ppb-chat（同级目录 `../ppb-chat`：camera-ios-app / server-camera / server-gateway / camera-manager-web） | 设计基线 V2.3，尚无通过工程验证的实现 |
| 统一认证中心（IAM） | [iam/README](iam/README.md) | ppb-base：server-iam / iam-web / iam-manage-web（规划） | 统一账号认证与平台授权设计 v0.4，58表SQL，待实施 |
| AI 衣柜（wardrobe） | [wardrobe/README](wardrobe/README.md) | 待建 | 需求基线 v1.1（PRD v1.0 + 37 条需求/用例） |

## 统一目录结构

每个项目目录遵循同一结构（以 camera 为参照实现）：

```
<project>/
  README.md    项目导航：阅读顺序、代码仓库指引、维护约定、版本记录
  PRD.md       需求基线：范围、原则、功能概要、数据边界、阶段与指标
  pr/          具体需求点/功能细则（camera 用 FS-xx 编号，wardrobe 用模块序号）
  ac/          验收标准：README 执行入口 + 00-验收总则与发布门槛 + 需求追踪矩阵 + 执行记录模板
  tech/        技术设计：技术大纲、界面/交互规范、数据库等专文
  adr/         决策与调整记录
  eval/        评估集（黄金集等，按需建设）
```

## 维护约定

- **单一事实源**：产品规则以 PRD 为准，技术契约以 tech/ 为准，验收口径以 ac/ 为准；ac/ 与导航只做索引和收拢，修改出处时同步，不复制正文制造第二份漂移源。
- **版本记录**：每个项目 README 底部维护版本表；跨项目的结构规范变更记录在本文件底部。
- **文档↔代码分仓**：文档改动在 ppb-docs 提交；引用代码仓库时写「仓库名 + 路径」，不写本仓库内相对路径。

## 版本

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.4 | 2026-10-27 | IAM统一用户/认证/平台授权，加入双单词字段规范及58表SQL |
| v0.3 | 2026-10-27 | 新增 IAM 设计基线：同仓独立认证服务、前端拆分、迁移与验收 |
| v0.2 | 2026-10-26 | camera 自 ppb-chat/docs 迁入；确立统一目录结构（README/PRD/pr/ac/tech/adr/eval） |
| v0.1 | 2026-10-26 | 建仓，wardrobe 需求基线 v1.1 入驻 |

