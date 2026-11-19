# 05 自定义列与插槽

更新：2026-11-19。状态：待实施规范。执行前先读 [README](./README.md)，本文不代表功能已实现。

> 本轮范围：在现有 ProTable 上增量实现本专题能力，保留旧公开 API 与请求状态；下述目标命名为示意，不要求引入独立列表组件或现有状态逻辑。以 [00 调整清单](./00-style-refactor-checklist.md) 为总范围。

### 插槽协议

提供 `cell-{key}`、`header-{key}`、`columns`、`row-actions`、`expand`、`empty`、`loading`、`error`、`summary`。单元格上下文统一包含 row、column、rowIndex、value；操作区额外提供 refresh。

自定义单元格不丢失列宽、对齐、固定、排序能力；自定义表头仍保留键盘可操作的排序入口及方向提示。配置列与手写列可混用；明确手写列插入位置，避免重复 key。手写列默认由业务维护，不纳入列设置，除非显式注册列元数据。

## 插槽及作用域

| 插槽 | 上下文/用途 |
| --- | --- |
| cell-{key} | row、column、rowIndex、value；头像、状态、链接、业务开关 |
| header-{key} | column、sort 状态；帮助提示、单位说明，排序入口留在外层 |
| columns | 手写列、特殊分组；记录与配置列的前后位置 |
| row-actions | row、rowIndex、refresh；页面处理领域操作 |
| expand | row、rowIndex；详情、子表、审核记录 |
| empty / loading / error | 当前状态；error 提供 retry，重试只调用现有状态逻辑 |
| summary | 当前数据及汇总上下文；标明当前页还是全量汇总 |
| ProTable 内容区域（后续扩展） | controller 及当前 rows；本轮不要求整体替换表格 |
| 现有 filters/toolbar 等区域插槽 | 替换组合区域，仍使用同一状态源 |

渲染优先级：匹配的 cell 插槽 > formatter > 原始值/空值占位。columns 手写列由业务自行定义渲染，不再次包装生成重复列。旧 col-{key} 在 ProTable 内映射到新 cell-{key}，只渲染一次；新旧同名入口同时存在时新插槽优先并提示开发者，不重复显示。

## 使用示意

以下为目标组件示例，实施时同步更新为真实 API：

```vue
<ProDataTable :rows="rows" :columns="columns" row-key="user_id">
  <template #cell-user_status="{ row, value }">
    <UserStatusSwitch :user="row" :status="value" @changed="refresh" />
  </template>
  <template #header-create_time>创建时间（业务时区）</template>
  <template #row-actions="{ row }">
    <el-button link @click="openDetail(row)">详情</el-button>
  </template>
</ProDataTable>
```

UserStatusSwitch 仅示意业务组件，是否抽取按现有业务结构决定；禁止将 IAM 状态操作塞入通用表格。

## 复杂列与范围

分组表头 children 递归渲染，只有叶子列参与值格式化和排序。父组可见性由允许展示的叶子列决定，空组不显示。合并单元格和树表等若透传底层能力必须补兼容示例；不在本轮重新实现引擎。展开行状态按 rowKey 保存，数据/范围变化清除不存在的 key；异步详情由业务处理自己的缓存和错误。

## 验收

配置列与手写列混用、重复 key 检查、旧插槽兼容；自定义列保留 align/width/fixed/sort；操作插槽刷新只发一次请求；空态、加载态、错误态与重试互斥且语义清楚。

---

返回 [文档入口](./README.md)；执行及交付要求见 [迁移计划](./10-migration-and-claude-task.md)。
