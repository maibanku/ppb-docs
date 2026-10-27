# File · 独立文件平台
> 设计基线 v0.1 · 2026-10-27。拟实施设计，不代表接口已上线、SQL已在生产执行或性能已验证。

文件平台服务 chat、camera、wardrobe、mail 和独立文件工作台。文件服务掌握字节、存储位置、传输、技术保护与清理；业务服务掌握用途、映射、业务权限、权益和发布规则；媒体 Worker 负责异步处理。

## 阅读顺序
1. [PRD](PRD.md)：范围、职责和阶段。
2. [功能细则](pr/01-功能与职责.md)、[独立前端](tech/前端设计.md)、[后端架构](tech/后端架构.md)。
3. [标识选型](adr/001-文件标识与业务边界.md)、[数据模型](tech/数据模型.md)、[SQL基线](tech/sql/README.md)。
4. [接口契约](tech/接口契约.md)、[OpenAPI](tech/api/openapi.yaml)、[业务接入与一致性](tech/业务接入与一致性.md)。
5. [大文件与视频](tech/大文件与视频.md)、[迁移计划](tech/迁移计划.md)。
6. [验收入口](ac/README.md)、[发布门槛](ac/00-验收总则与发布门槛.md)、[追踪矩阵](ac/需求追踪矩阵.md)、[执行记录](eval/设计验证记录.md)。

## 冻结决策
- 跨服务及业务映射使用 `file_biz_key`；新键为 `file_` + UUIDv4去连字符的小写32位hex。保留存量键，不按新格式改写历史键。不新增等价 `fileuuid` 字段。
- 文件库内部使用雪花 `file_id`；所有API中大整数ID用字符串。业务键不是下载密码。
- 独立部署前后端，不意味着立即迁移新仓库：首期在 ppb-base 演进 server-file，并规划 file-web、file-manage-web、file-worker 独立构建和部署。
- 业务附件不因“上传者”身份自动可下载；业务服务授权，文件服务验证受限凭证。独立工作台只管理 file_console 应用的个人资源。
- 大文件直传对象存储；视频 Worker 异步处理。引用解绑、回收站保护、配额与GC使用一致定义。

## 工程落点
`ppb-base/server-file`、`file-web`、`file-manage-web`、`file-worker`、`idl/file/v2`、`deploy/sql/ppb_file/v2` 为规划落点；媒体元数据建议独立 ppb_media 库。文档仓不承载运行代码。

## 版本
|版本|日期|内容|
|---|---|---|
|v0.1|2026-10-27|独立前后端、多业务映射、标识决策、MySQL目标SQL、常用API/OpenAPI、大文件视频及验收|
