# 06 列属性与表格整体属性

更新：2026-11-19。状态：待实施规范。执行前先读 [README](./README.md)，本文不代表功能已实现。

> 本轮范围：在现有 ProTable 上增量实现本专题能力，保留旧公开 API 与请求状态；下述目标命名为示意，不要求引入独立列表组件或现有状态逻辑。以 [00 调整清单](./00-style-refactor-checklist.md) 为总范围。

### 列协议

采用泛型 `ListColumn<T>`，key 是稳定列 ID，field 默认取 key；旧 ProTableColumn 与 format(row) 通过适配器保留。

| 属性 | 规则 |
| --- | --- |
| key / field / label | 列标识、数据字段和显示名分离 |
| align / headerAlign | left/center/right，表头默认跟随列 |
| width / minWidth | number/string；明确宽度优先，最小宽度约束自动分配 |
| fixed / resizable | left/right/不固定，列宽调整事件 |
| sortable / sortField / sortMethod | 排序开关、后端白名单映射、本地比较函数 |
| formatter | 接收 value、row、column、rowIndex；0/false 不能当空值 |
| overflow / clamp / tooltip / emptyText | 省略、换行、多行截断及空值规则 |
| visible / hideable | 当前展示与用户能否隐藏分离；权限禁止列不能被偏好恢复 |
| className / headerClassName | 单元格及表头样式 |
| children | 分组表头，叶子列参与数据渲染和排序 |

默认文字左对齐、数值右对齐、状态与序号居中，页面可覆盖。时间列默认不换行并提供足够最小宽度。保留现有 clamp 与原生 title 行为。

### 表格整体能力

选择 none/single/multiple、可选择行谓词、序号开关、边框、斑马纹、密度、height/maxHeight/fill、行点击/双击/高亮、展开行与自定义汇总。本轮不实现通用编辑表、虚拟滚动或新的树表引擎；必要时透传已验证的底层能力，并保留 custom body 扩展。

## 列属性默认值与限制

| 属性 | 默认或限制 |
| --- | --- |
| key | 必填且同表唯一，偏好保存使用它而不是 label |
| field | 默认 key；嵌套路径只有实现明确支持时开放 |
| label | 标题；自定义表头仍保留可访问名称 |
| align | 默认 left；数值/状态类型可提供显式预设 |
| headerAlign | 跟随 align |
| width | 未设置自动；number 按底层像素约定 |
| minWidth | 按列类型预设，仍允许页面覆盖；无效值开发环境提示 |
| fixed | 默认不固定，系统选择列在左、操作列按配置固定右 |
| resizable | 可配置；底层仅支持边框模式拖动时写明限制 |
| sortable | 默认 false；后端能力不足时禁用 |
| overflow | 默认单行省略；clamp>0 时使用多行截断 |
| tooltip | 超长时显示，避免短内容也重复弹出 |
| emptyText | 默认 —，仅 null/undefined/约定空字符串视为空 |
| visible / hideable | 默认 true；权限允许集合先于用户偏好 |
| children | 非叶子列禁用 field/formatter/sort 等无效组合 |

固定宽度和最小宽度的最终行为需按现有 Element Plus 版本验证；不接受给底层不支持的 CSS 单位后悄悄失效。多个固定列测试横向滚动和边框衔接。slot 列内容布局由业务负责，容器仍遵守列属性。

## 表格整体协议

补充属性：border、stripe、density、height、maxHeight、fill、rowKey、selection、selectable、reserveOnPageChange、showIndex、indexMode、indexMethod、highlightCurrentRow、rowClassName、summaryMethod。事件覆盖 selection-change、sort-change、column-resize、row-click、row-dblclick、expand-change。

不要无限制 v-bind 任意 props 到 DOM 或底层表格，采用明确定义的透传对象和事件清单；包装层与底层处理同名属性时有清晰优先级。高度自然模式与填充模式不能同时传入互相冲突的强制尺寸。

## 验收

left/center/right、headerAlign、width/minWidth、固定左右列、拖动、长文本/多行/tooltip、0/false/空值、分组叶子列；选择列/序号/操作列关闭时不存在空白占位；默认主题与密度一致。

---

返回 [文档入口](./README.md)；执行及交付要求见 [迁移计划](./10-migration-and-claude-task.md)。
