# 01 现有 ProTable 改造范围与兼容

更新：2026-11-19。状态：待执行说明，尚未修改组件代码。

## 范围修正

用户确认本轮以现有 ProTable 样式重构为主。此前“拆基础组件、引入 ProList/useProList、统一数据源”的方案不再是本轮任务，不作为交付条件。仅当样式实现确有需要时可抽内部展示片段，不能要求消费者迁移到新架构。

## 主要修改位置

路径相对 `/Users/pipi-ban/Desktop/code/vscode`：

- `ppb-base/base-manage-web/src/components/ProTable.vue`：DOM 分区、列属性透传、筛选布局、边框及局部样式。
- `ppb-base/base-manage-web/src/types/pro-table.ts`：增量列属性、筛选配置、序号/分页/列设置配置。
- 底座现有样式目录：公共变量和组件局部皮肤，按仓库惯例组织。
- `ppb-base/base-manage-web/exports.ts`：仅在有新增公开类型时补导出。
- 实际试点页面：最小接入调整，不批量重写业务页面。

## 保持兼容

保留 fetch/data/search/searchDefaults/params、rowKey/selectable/reserveSelection/selectionScope、defaultSort、fixedFoot；保留 filters/toolbar/columns/col-{key}/actions 插槽、现有事件与 expose 方法。旧 format(row)、字符串长 ID、日期范围拆分、分页参数和错误提示继续可用。

样式统一是本轮有意变更；业务交互默认值保持，新增能力可按配置开启。不要为了视觉统一改变权限、确认文案、写接口或用户状态机。不要删除 useProTableLocal/useCursorAll 导出或改变游标降级行为。

开工先检查适用 AGENTS.md、git 状态和真实消费者；文档类型示例不作为强制重命名现有公开 API 的理由。
