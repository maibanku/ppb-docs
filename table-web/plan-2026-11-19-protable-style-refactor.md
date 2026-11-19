# ProTable 样式重构+增量能力 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 ppb-docs/table-web 规格 00–11，在现有 `base-manage-web` ProTable 上完成图片风格样式重构与增量能力（筛选控件/折叠/时间快捷项、排序、列属性/插槽、选择/序号/工具栏/分页开关、列设置与偏好），保留全部旧 API 与请求状态行为，九宫格验收并产出 implementation.md。

**Architecture:** 单组件增量改造——ProTable.vue 保持唯一公开入口；新增内部子组件 `src/components/pro-table/`（筛选区、列设置面板）与纯逻辑 composable/util（时间快捷项、折叠测量、列偏好）；类型在 `src/types/pro-table.ts` 上扩联合类型，旧形状全部兼容。不引入新依赖（Element Plus ~2.8.8 已含全部所需控件）。

**Tech Stack:** Vue 3.4 `<script setup>` + Element Plus ~2.8.8 + vitest/jsdom + vue-tsc + vite（库模式 build:lib）。

**Spec:** `/Users/pipi-ban/Desktop/code/vscode/ppb-docs/table-web/`（README.md 为入口，00–11 全部专题）。执行者每个任务前必须读 README + 对应专题文档。

## Global Constraints（每个任务隐含遵守）

- **不新增依赖**；不改 lockfile；不 `git push`；不发布。
- **旧 API 全保留**（spec 01/02）：fetch/data/loading/error/currentPage/total、keywordSearch/search/searchDefaults/params、rowKey/selectable(布尔)/reserveSelection/selectionScope、defaultSort/fixedFoot、filters/toolbar/columns/col-{key}/actions 插槽、全部 emits 与 defineExpose(refresh/clearSelection/search/reset)、format(row)、字符串长 ID、startKey/endKey 拆分、分页参数、错误重试、useProTableLocal/useCursorAll 导出与游标语义、epoch 竞态守卫、末页回退、范围/账号变化清选择。
- **行为红线**（spec 02）：编辑筛选不请求；查询/重置/换页大小各只发一次请求；折叠/列显隐/列宽/密度变化绝不触发列表请求；隐藏分页≠拉全量；0 与 false 是有效条件与有效显示值，不当空。
- **样式**（spec 09）：只动 ProTable 作用域（scoped + `--pro-list-*` 变量挂 EP 变量），不写全局深选择器覆盖其他页面；密度行高 36/44/52、控件高 32/32/40；白底/浅灰表头/横纵细线/小圆角/右下分页。
- **工作区**：在 `/Users/pipi-ban/Desktop/code/vscode/ppb-base` 主检出建分支 `feat/protable-style-refactor`（**不用 worktree**——兄弟仓 vite alias 指 `file:../../ppb-base/base-manage-web` 源码，worktree 会令 iam/camera/file 外部消费方验证失效）。开工前 `git status` 确认干净；不覆盖用户改动。
- **命令**（在 `ppb-base/base-manage-web` 下）：`npm run test`、`npm run typecheck`（node 必须 v24.x）、`npm run build:lib`、`npm run build`。无 lint 脚本。
- 每个 Task 完成时全量 `npm run test` + `npm run typecheck` 必须绿（旧 16 个测试文件是兼容底线），然后提交（提交信息带 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`）。
- IME 守卫：回车提交仅在单行输入控件上，回调里过滤 `e.isComposing`。

## Review Focus（规格隐含、最易翻车的五类输入 → 已钉进对应任务测试）

1. **草稿 vs 已提交混淆**：输入中/折叠中不得发请求，翻页不带未提交草稿 → Task 3/6 测试。
2. **0/false/空值混同**：数字 0 筛选要提交、false 要显示、仅 null/undefined/'' 为空 → Task 3/8 测试。
3. **字符串长 ID 选择键**：19 位 ID 不得经 Number() 精度丢失，跨页选择按 rowKey 字符串集合 → Task 9 测试。
4. **偏好恢复带回过期元数据/权限列**：存储只存 key/顺序/显隐/宽/密度，恢复后必显列强制显示、权限列丢弃 → Task 10 测试。
5. **请求竞态与旧响应污染**：epoch 守卫在新筛选/排序/重置路径上一致生效 → Task 7 复测 + 既有 epoch 用例保持绿。

---

### Task 1: 设计令牌与视觉骨架（纯样式+结构类）

**Files:**
- Modify: `ppb-base/base-manage-web/src/components/ProTable.vue`（style 区重写 + template 区块 class 调整）
- Test: `ppb-base/base-manage-web/src/__tests__/pro-table.test.ts`（追加）

**Interfaces:**
- Produces: CSS 变量集 `--pro-list-bg/header-bg/border/text/muted/radius/padding/gap/control-height/font-size`（挂 `--el-*` 带回退，spec 09 建议值）；容器/分区 class：`pro-table`（白底卡片、圆角 4px、内边距 12px）、`pro-table__field`（标签+控件同框：左标签、右侧细分隔线、右控件）、`pro-table__toolbar-left/right`、表头浅灰（EP `--el-fill-color-light`）、el-table 开 border、`.pro-table__footer` 分页右对齐；密度类 `pro-table--density-{compact|default|comfortable}`（行高/控件高变量，本任务先落 CSS，density prop Task 10 接线）。
- 兼容：保留现有 `--list-*` 变量与 `[data-theme='dark']` 覆盖逻辑（并入新变量体系），保留 `pro-table--fixed-foot`。

- [ ] **Step 1: 写失败的结构测试**（追加到 pro-table.test.ts）
  - `视觉骨架：筛选字段渲染为标签内嵌同框结构` —— mount 带 1 个 search 字段，断言 `.pro-table__field` 存在且包含 label 文本与控件。
  - `视觉骨架：无内容时工具栏不占行` —— 无 batchActions/无 toolbar 插槽时断言 `.pro-table__toolbar` 不存在。
  - `视觉骨架：表格启用边框线` —— 断言 el-table 根含 `el-table--border` class。
- [ ] **Step 2: 跑测试确认新用例 FAIL、旧 7 用例 PASS**：`npm run test -- src/__tests__/pro-table.test.ts`
- [ ] **Step 3: 重写 style 区与 template 分区**：落 `--pro-list-*` 变量；筛选字段包 `.pro-table__field`（label + 竖分隔 + 控件，控件去自身外框用 `:deep()` 置空 wrapper box-shadow）；工具栏改左右两区 `v-if` 有内容才渲染；el-table 传 `border`；分页容器右对齐。表头/单元格/固定列遮罩用 EP 表格 CSS 变量（`--el-table-header-bg-color` 等）不动全局。
- [ ] **Step 4: `npm run test` 全量 + `npm run typecheck` 绿**
- [ ] **Step 5: Commit** `style(protable): 设计令牌与图片风格骨架（spec 09）`

### Task 2: 类型层扩展与导出（纯类型）

**Files:**
- Modify: `ppb-base/base-manage-web/src/types/pro-table.ts`
- Modify: `ppb-base/base-manage-web/exports.ts`（补新公开类型导出）

**Interfaces:**
- Produces（后续任务全部依赖，名字精确）：
  - `ProTableDensity = 'compact' | 'default' | 'comfortable'`；`ColumnAlign = 'left' | 'center' | 'right'`
  - `ProTableColumn` 增量字段：`field?`（默认=key）、`align?/headerAlign?`、`alignPreset?: 'text'|'number'|'status'`、`fixed?: 'left'|'right'|boolean`、`resolvable? resizable?: boolean`、`sortField?`、`sortMethod?: (a: TableRow, b: TableRow) => number`、`formatter?: (value: unknown, row: TableRow, column: ProTableColumn, rowIndex: number) => string`、`overflow?: 'ellipsis'|'wrap'`、`tooltip?: boolean`、`emptyText?: string`（默认 '—'）、`visible?/hideable?`（默认 true）、`className?/headerClassName?`、`children?: ProTableColumn[]`；保留 key/label/width/minWidth/sortable/format/clamp。
  - `SearchField` 改判别联合（base：key/label/type/defaultValue/placeholder/order/span/minWidth/disabled/visible/paramsKey/required/validate/serialize/startKey/endKey/options——后四项为旧形状兼容），成员：`input`(trim/maxlength/clearable)、`number`(min/max/step/precision)、`number-range`(同 number + startKey/endKey 必填语义)、`select`(options?/optionsLoader?/multiple?/filterable?/clearable?/labelKey?/valueKey?)、`date|date-range|datetime|datetime-range|time|time-range`(valueFormat?/displayFormat?/shortcuts?: boolean|Array<{key,label,getValue(now):[Date,Date]}>/disableFuture?/maxSpanDays?)、`tree-select`(data?/dataLoader?/multiple?/checkStrictly?)、`cascader`(options?/optionsLoader?/props?)、`custom`。
  - Props 增量：`selectionMode?: 'none'|'single'|'multiple'`（缺省时由旧 `selectable` 布尔映射 true→multiple/false→none）、`rowSelectable?: (row: TableRow) => boolean`、`showIndex?: boolean`、`indexMode?: 'page'|'continuous'`（默认 continuous）、`indexMethod?: (index: number, row: TableRow) => string|number`、`showPagination?: boolean`（默认 true）、`density?: ProTableDensity`（默认 'default'）、`searchCollapse?: boolean`（默认 true）、`columnSettings?: boolean | { storage?: {getItem/setItem/removeItem}; scope?: { userKey?: string; pageKey?: string; scopeKey?: string; version?: number } }`（默认 false）。
  - `sorts?: Array<{ field: string; order: 'asc'|'desc' }>` 类型预留（emit 载荷仍为现有单列形状；适配器只取第一项——多列为后续增强，不实现）。

- [ ] **Step 1: 扩写类型**（判别联合+注释标注旧兼容字段；不改任何运行时行为）
- [ ] **Step 2: `npm run typecheck` 绿 + `npm run test` 全量绿**（证明旧形状零破坏）
- [ ] **Step 3: exports.ts 补导出新类型**（ProTableDensity、ColumnAlign、ListPreference 等公开类型；组件与旧导出不动）
- [ ] **Step 4: `npm run build:lib` 绿**（库出口可编译）
- [ ] **Step 5: Commit** `types(protable): 列/筛选/表格增量类型与公开导出（spec 04/06）`

### Task 3: 筛选静态控件与序列化

**Files:**
- Create: `ppb-base/base-manage-web/src/components/pro-table/ProTableFilters.vue`（内部子组件，不进 exports）
- Modify: `ppb-base/base-manage-web/src/components/ProTable.vue`（筛选区改用子组件；keyword 输入并入）
- Test: `ppb-base/base-manage-web/src/__tests__/pro-table.test.ts`（追加 describe「筛选控件与序列化」）

**Interfaces:**
- Consumes: Task 1 的 `.pro-table__field` 结构与 class；Task 2 的 SearchField 联合。
- Produces: `ProTableFilters` props：`fields: SearchField[]`、`modelValue: Record<string, unknown>`（草稿）、`applied: Record<string, unknown>`、`disabled?: boolean`；emits：`update:modelValue`、`submit`、`reset`；插槽 `filter-{key}`（custom 型读写 modelValue）。ProTable 内部：草稿 ref（deep copy searchDefaults 初始化）、submitSearch 保持现有事件路径与"只发一次请求"语义。
- 控件映射（静态部分）：input→el-input、number→el-input-number、number-range→两个 el-input-number、select→el-select（options 静态）、date/date-range/datetime/datetime-range/time/time-range→el-date-picker/el-time-picker 对应 type、tree-select→el-tree-select（data 静态）、cascader→el-cascader（options 静态）、custom→插槽。远程 loader Task 4 接。

- [ ] **Step 1: 写失败测试**（每个控件一条 + 序列化规则，用 mount(ProTable) 真实走 submit）：
  - `渲染 input/number/select/date-range/tree-select/cascader 草稿值不触发请求`（fetch mock 断言 0 次调用）
  - `number 0 与 boolean false 是有效条件被提交`（params 含 0）
  - `空串/null/undefined/空数组不进 params`
  - `paramsKey 重命名与 startKey/endKey 范围拆分`（date-range 值按 valueFormat 拆两键）
  - `select multiple 序列化为逗号拼接`、`自定义 serialize 覆盖默认`
  - `input trim 生效`、`回车提交仅 input/number 触发且过滤 isComposing`
- [ ] **Step 2: 跑测试确认 FAIL**
- [ ] **Step 3: 实现 ProTableFilters.vue + ProTable.vue 接线**（草稿/已提交分离维持现状；keywordSearch 输入并入 fields 前置；#filters 插槽覆盖行为保留）
- [ ] **Step 4: 全量 test + typecheck 绿**
- [ ] **Step 5: Commit** `feat(protable): 筛选静态控件注册与参数序列化（spec 04）`

### Task 4: 远程选项、联动与校验

**Files:**
- Modify: `ppb-base/base-manage-web/src/components/pro-table/ProTableFilters.vue`
- Test: 同文件追加 describe「远程选项与校验」

**Interfaces:**
- Consumes: Task 3 全部。
- Produces: `optionsLoader?: () => Promise<Array<Record<string, unknown>>>` 行为——首次展开时加载、loading/error/重试态；字段 `dependsOn?: string[]`（加入 Task 2 类型的 base——本任务补）：依赖字段值变化时清空本字段草稿值并作废在途选项请求（epoch 计数守卫）；校验：required / number min-max / 范围 start≤end / maxSpanDays / `validate?(value, draft) => string | null | Promise<string|null>`（异步校验拿提交时草稿快照，await 期间草稿再变则放弃本次提交）。

- [ ] **Step 1: 写失败测试**：
  - `远程选项加载成功/失败重试/在途作废`（loader reject→error+重试按钮；两次加载竞态取后值）
  - `dependsOn 变化清空下级值与在途请求`
  - `required/min-max/起止顺序/maxSpanDays 校验失败零请求`
  - `异步校验期间草稿变化则不提交旧值`
- [ ] **Step 2: FAIL 确认 → Step 3: 实现**（loader 缓存到字段实例；校验错误显示在字段下方错误位，不阻塞其他字段）
- [ ] **Step 4: 全量绿 → Step 5: Commit** `feat(protable): 远程选项/联动/校验（spec 04）`

### Task 5: 时间快捷项（纯函数）

**Files:**
- Create: `ppb-base/base-manage-web/src/utils/list-time-shortcuts.ts`
- Create: `ppb-base/base-manage-web/src/utils/__tests__/list-time-shortcuts.test.ts`
- Modify: `ProTableFilters.vue`（date/datetime-range 控件接 shortcuts）

**Interfaces:**
- Produces: `todayRange(now)`=[业务日 00:00:00, now]；`lastDays(now, n)`=[now−n×24h, now]；`lastCalendarMonths(now, n)`=[日历月回退（月末钳制到目标月末日）, now]；`DEFAULT_RANGE_SHORTCUTS: Array<{key,label,getValue(now)}>`（今天/最近一周/最近一月/最近三月，点击时才调 getValue）；`toDatePairValue(range, valueFormat): [string, string]`。
- 接线：`shortcuts: true`（默认 true）时 date-range/datetime-range 显示 DEFAULT_RANGE_SHORTCUTS；`disableFuture` 传 EP disabled-date；秒级精度 valueFormat 'YYYY-MM-DD HH:mm:ss'。

- [ ] **Step 1: 写失败测试（固定时钟）**：
  - `今天=业务零点到当前秒`；`最近7天=滚动 168h`；`最近一月 3/31→2/28（非闰年）/2/29（闰年）钳制`；`最近三月跨年 2026-11-19→2026-08-19`；`快捷项每次点击重新计算（两次调用 now 不同结果不同）`
  - `月末 1/31 减一月→12/31 前一年`；`toDatePairValue 秒级格式`
- [ ] **Step 2: FAIL → Step 3: 实现**（日历月算法：目标月天数 = new Date(y, m+1, 0).getDate()，日取 min(原日, 目标月天数)）
- [ ] **Step 4: 全量绿 → Step 5: Commit** `feat(protable): 时间快捷项与日历月钳制（spec 04 时间规则）`

### Task 6: 筛选折叠布局（ResizeObserver）

**Files:**
- Create: `ppb-base/base-manage-web/src/composables/use-filter-collapse.ts`
- Create: `ppb-base/base-manage-web/src/composables/__tests__/use-filter-collapse.test.ts`
- Modify: `ProTableFilters.vue`、`ProTable.vue`

**Interfaces:**
- Produces: `useFilterCollapse({ container: Ref<HTMLElement|undefined>, fields: ComputedRef<SearchField[]>, applied: ComputedRef<Record<string, unknown>> })` → `{ collapsed, toggle, hiddenKeys: ComputedRef<Set<string>>, hiddenAppliedCount: ComputedRef<number>, canCollapse: ComputedRef<boolean> }`。
- 纯函数（单测主力）：`estimateFieldWidth(field): number`（label 字宽 + 控件类型基宽 + minWidth，span=2 记双倍）；`computeHiddenKeys(widths: number[], containerWidth: number, actionsWidth: number): number[]`（首行装不下即隐藏；查询/重置/展开始终可见，装不下时操作区独立成行）。
- 布局：字段按 order 稳定排序；隐藏用 `v-show`（不卸载不丢值）；全部装得下 canCollapse=false 无展开钮；收起时显示 hiddenAppliedCount（仅已生效条件，不含纯草稿）；折叠/展开零请求。

- [ ] **Step 1: 写失败测试**：
  - `窄容器隐藏次行字段且 v-show 不卸载（值保留）`
  - `展开收起 fetch 调用次数不变`
  - `hiddenAppliedCount 只数已生效条件`
  - `全部装得下无展开按钮`
  - `span=2 宽度翻倍`、`order 排序稳定`
- [ ] **Step 2: FAIL → Step 3: 实现**（jsdom 下 mock ResizeObserver；真容器宽度由 observer 传入纯函数）
- [ ] **Step 4: 全量绿 → Step 5: Commit** `feat(protable): 筛选单行折叠与已生效计数（spec 04 折叠布局）`

### Task 7: 排序三态、字段映射与本地排序

**Files:**
- Modify: `ppb-base/base-manage-web/src/components/ProTable.vue`
- Modify: `ppb-base/base-manage-web/src/composables/use-protable-local.ts`
- Test: pro-table.test.ts、use-protable-local.test.ts 各追加

**Interfaces:**
- Consumes: Task 2 的 sortField/sortMethod/sorts 类型。
- Produces: 远程排序参数映射 `{prop: column.sortField ?? column.key, order}`（三态升→降→取消走 el-table 原生）；排序变化回第一页且保留 appliedFilters；重置恢复 defaultSort；`useProtableLocal` 增可选参 `sort?: ComputedRef<{field: string; order: 'asc'|'desc'|null} | null>` 与 `columns?: ComputedRef<ProTableColumn[] | undefined>`——在 computed 内排序后切片（空值恒末尾、稳定、数值/时间/locale 文本比较、不改源数组）；无 sortable 列无排序入口（原生默认即无）。
- 现状核对：先读现有 sort-change 处理是否已回第一页/清草稿；只改规格要求差异，并保持既有 sort-change 事件载荷形状不变。

- [ ] **Step 1: 写失败测试**：
  - `排序参数用 sortField 映射且三态第三态清排序参数`
  - `排序变化回第一页且 appliedFilters 保留`
  - `重置恢复 defaultSort`
  - `本地排序：空值末尾/稳定/数值比较/切片引用稳定/源数组不变`（use-protable-local）
- [ ] **Step 2: FAIL → Step 3: 实现**（local 比较器：null/undefined→末尾；Number 有效数值比较；可解析 Date 比较；其余 localeCompare）
- [ ] **Step 4: 全量绿 → Step 5: Commit** `feat(protable): 排序三态映射与本地排序切片（spec 03）`

### Task 8: 列属性渲染与插槽协议

**Files:**
- Modify: `ppb-base/base-manage-web/src/components/ProTable.vue`
- Test: pro-table.test.ts 追加 describe「列属性与插槽」

**Interfaces:**
- Consumes: Task 2 全部列类型字段。
- Produces: el-table-column 透传白名单：align/headerAlign（未设 align 时按 alignPreset：number→right、status→center、默认 left）、width/minWidth、fixed、resizable、show-overflow-tooltip（overflow='ellipsis'||tooltip）、class-name/header-class-name；children 递归分组（仅叶子列参与 format/slot/排序）；渲染优先级 `cell-{key}` 插槽 > formatter > format(row)（旧） > 原值/emptyText；`col-{key}` 与 `cell-{key}` 同名共存时新优先 + import.meta.env.DEV console.warn，只渲染一次；新插槽：`header-{key}`（排序控件留在外层不丢）、`row-actions`（旧 `actions` 别名保留）、`expand`（展开状态按 rowKey 集合存，数据/范围变化清无效 key）、`empty`/`error`（error 插槽上下文含 retry=现有 refresh 语义）；空值=仅 null/undefined（0/false 正常显示）；时间列未设 minWidth 时默认 165。
- 兼容：旧 format(row)、clamp、动态插槽 `col-${column.key}` 行为原样。

- [ ] **Step 1: 写失败测试**：
  - `cell 插槽优先于 formatter/format 且 col- 兼容单次渲染`、`两者同存 DEV 警告`
  - `alignPreset number 右对齐 status 居中 默认左`
  - `0/false 不算空值，null/undefined 显示 emptyText '—'`
  - `children 分组仅叶子列取值`
  - `expand 展开行数据变化清失效 key`
  - `header 插槽存在时列仍可排序`
- [ ] **Step 2: FAIL → Step 3: 实现**
- [ ] **Step 4: 全量绿 → Step 5: Commit** `feat(protable): 列属性白名单透传与新旧插槽协议（spec 05/06）`

### Task 9: 选择模式、序号列、工具栏左右区与分页开关

**Files:**
- Modify: `ppb-base/base-manage-web/src/components/ProTable.vue`
- Test: pro-table.test.ts 追加 describe「选择/序号/工具栏/分页」

**Interfaces:**
- Consumes: Task 2 props。
- Produces: selectionMode（含 selectable 布尔映射）；single 无全选框（EP selection 列 `hide-select-all`? 用列头渲染空处理）且 selection-change 载荷 ≤1 行；rowSelectable 传 el-table-column selectable；选择列最左、序号列随后、独立开关无空占位（v-if）；indexMode continuous=`(page-1)*pageSize+i+1`，page=`i+1`，游标模式（total 未知）禁止伪连续编号（useCursorAll 场景降级 page 模式，控制台 DEV 提示）；提交新筛选/重置/排序默认清选择（reserveSelection=true 时跨页保留语义原样并在 implementation.md 注差异）；19 位字符串 ID 跨页选择不丢（selection keys 全程字符串集合，禁 Number()）；工具栏左区=`toolbar-left` 插槽+batchActions，右区=aux 插槽+列设置入口（Task 10 挂），空则整行不渲染（Task 1 已建 class）；showPagination=false 时 `.pro-table__footer` 不渲染零留白、分页事件与状态逻辑不动。

- [ ] **Step 1: 写失败测试**：
  - `single 无全选且只保留最后选中一行`
  - `showIndex continuous 连续编号跨页正确`
  - `游标模式序号不伪造全局位置`
  - `查询/重置后清空选择`
  - `19 位 ID 字符串跨页选择精度不丢`
  - `showPagination=false 无 footer 元素且不发额外请求`
  - `toolbar 空内容无 toolbar 行`（若 Task 1 已覆盖则保留回归）
- [ ] **Step 2: FAIL → Step 3: 实现**
- [ ] **Step 4: 全量绿 → Step 5: Commit** `feat(protable): 选择模式/序号列/工具栏分区/分页开关（spec 08 + 06 整体）`

### Task 10: 列设置面板与偏好存储

**Files:**
- Create: `ppb-base/base-manage-web/src/components/pro-table/ProTableColumnSettings.vue`
- Create: `ppb-base/base-manage-web/src/composables/use-column-preferences.ts`
- Create: `ppb-base/base-manage-web/src/composables/__tests__/use-column-preferences.test.ts`
- Modify: `ProTable.vue`（工具栏右区挂入口；density 接线到 Task 1 密度类）

**Interfaces:**
- Consumes: Task 2 `columnSettings` prop 与 ProTableColumn；Task 9 工具栏右区。
- Produces: `ListPreference { version: number; columns: Array<{key; visible?; width?}>; density?: ProTableDensity }`（exports.ts 已在 Task 2 导出类型）；`useColumnPreferences({ columns: ComputedRef<ProTableColumn[]>, scope: {userKey?; pageKey?; scopeKey?; version} | null, storage })` → `{ resolvedColumns, visibleKeys, setColumnVisible(key,v), moveColumn(key,dir), setColumnWidth(key,w), setDensity(d), resetDefault() }`。
- 恢复算法（spec 07 六步，按序实现并测试）：允许列集（visible 定义+权限 hasPerm 过滤）→ 校验存储（版本/类型/重复 key/宽度范围，损坏回退默认不抛错）→ 按存储顺序恢复仍存在叶子列（尊重分组/固定边界：选择/序号/操作列不参与排序）→ 新列按默认序补入、必显（hideable=false）强制显示、已删列丢弃 → 元数据（label/formatter/slots/权限）一律用最新定义 → 应用后面板与表格同步；恢复默认=清 scope 存储。
- 存储 key：`['pro-table-pref', userKey, pageKey, scopeKey, version].filter(Boolean).join(':')`；无 pageKey → session-only 不落盘；storage 默认 `window.localStorage`，setItem 抛错降级本次会话可用（不白屏）。
- 面板：工具栏右「列设置」popover——每可隐藏列 checkbox、上移/下移、宽度 el-input-number（可空）、密度三选、恢复默认按钮；必显列 checkbox 禁用；权限列不出现；手写未注册列（#columns 插槽列）不出现。任何偏好变化零请求；宽度拖拽（列 resizable）结束后写回 setColumnWidth。
- density prop 与偏好 density 合并优先级：最近一次修改者生效（组件内单一 source：偏好解析结果覆盖 prop 初始值，用户切换更新两者）。

- [ ] **Step 1: 写失败测试**：
  - `隔离：不同 userKey/pageKey/scopeKey 互不串`、`损坏 JSON 回退默认`
  - `宽度越界/重复 key 丢弃该项`
  - `删列/加列合并：新列按默认序补入、已删列忽略`
  - `必显列强制显示、权限列不出现且不被恢复`
  - `恢复默认清存储`
  - `偏好变化 fetch 零调用`
  - `storage 写失败降级不抛错`
- [ ] **Step 2: FAIL → Step 3: 实现（算法按上面六步逐条对应测试）**
- [ ] **Step 4: 全量绿 + typecheck → Step 5: Commit** `feat(protable): 列设置面板与偏好存储（spec 07）`

### Task 11: 九宫格验收页（dev-only 路由 + mock 数据）

**Files:**
- Create: `ppb-base/base-manage-web/src/views/dev/TableShowcaseView.vue`
- Modify: `ppb-base/base-manage-web/src/router/index.ts`（admin 锚点下加 `/dev/table-showcase` 路由，无服务端菜单项即不进生产菜单——菜单唯一来源是服务端目录）
- Test: `ppb-base/base-manage-web/src/__tests__/table-showcase.test.ts`（轻冒烟）

**Interfaces:**
- Consumes: Task 1–10 全部能力。
- Produces: 确定性 mock fetch（无后端，data-testid 标注 combo-1..9）；九种组合按 spec 11 矩阵（1 基础关选择关分页 / 2 筛选无分页 / 3 筛选+页码分页 / 4 筛选+多选+序号+分页 / 5 工具栏+多选+批量 / 6 多类型筛选+展开收起 / 7 自定义单元格表头+排序 / 8 列设置+展开行 / 9 完整组合+展开行）；另附「本地全集」与「游标模式」两个区块（useProTableLocal / useCursorAll）；mock 数据含 19 位字符串 ID、长文本、0/false 值、跨月时间、多状态枚举。
- 页面仅注册路由不进菜单；不加生产入口。

- [ ] **Step 1: 写冒烟测试**（路由可渲染、九个 combo 容器存在、无控制台错误）
- [ ] **Step 2: FAIL → Step 3: 实现页面与路由**
- [ ] **Step 4: `npm run test` + `npm run typecheck` + `npm run build` 全绿（build 含 app 打包确认路由无冲突）**
- [ ] **Step 5: Commit** `feat(protable): 九宫格验收页与本地/游标模式（spec 11 矩阵）`

### Task 12: 回归、外部消费方、截图与交付记录

**Files:**
- Modify: `ppb-docs/table-web/implementation.md`（新建）
- Create: `ppb-docs/table-web/screenshots/*.png`
- Test: 全部既有测试

**Interfaces:**
- Consumes: 全部前置任务。

- [ ] **Step 1: 底座全量验证**：`cd ppb-base/base-manage-web && npm run test && npm run typecheck && npm run build:lib && npm run build`——记录真实输出摘要。
- [ ] **Step 2: 外部消费方**：`cd ppb-iam/iam-manage-web && npm run test && npm run typecheck && npm run build`（file: 源码链接直接吃到分支改动）；记录用户管理页受样式影响的目测结论。
- [ ] **Step 3: 浏览器实测截图**：起 `npm run dev`（:8210），逐 combo 截图 1–9 + 窄容器 768/375、筛选展开态、fixedFoot 滚动、固定列、错误/空态、密度切换、暗色主题；存 `ppb-docs/table-web/screenshots/`；截图不露真实用户数据（mock 页天然满足；IAM 页只截样式不截数据或打码）。
- [ ] **Step 4: 写 implementation.md**：实际改动文件清单、增量 API（含默认值与兼容映射）、旧接口兼容说明、示例入口路由、截图索引、测试/构建真实结果、未完成项与后续增强（多列排序、查询方案、URL 记忆、虚拟滚动、服务端偏好）。
- [ ] **Step 5: Commit（ppb-docs 仓）** `docs(table-web): ProTable 样式重构实施记录与九宫格截图`；ppb-base 分支最后 rebase 检查 + 汇总。不推送。

---

## Self-Review 记录

- 规格覆盖：00→Task 1/9/10；01/02→全局约束；03→Task 7；04→Task 3/4/5/6；05/06→Task 8/9；07→Task 10；08→Task 9；09→Task 1/12；10→任务顺序本身；11→Task 11/12。gap 检查：spec 05 的 summary 插槽与 spec 06 的 stripe/height/maxHeight/row-click 透传为**低频透传项**——Task 8 透传白名单含 class/align/width 类，事件类（row-click/dblclick/expand-change）与 border/stripe 由 el-table 原生属性在 Task 8 一并加入白名单（el-table 已支持，零成本）；summary 插槽列入 implementation.md「后续增强」（九宫格无 summary 组合，非本轮完成条件）。
- 类型一致：selectionMode/rowSelectable/showIndex/indexMode/indexMethod/showPagination/density/searchCollapse/columnSettings/paramsKey/dependsOn/sortField/sortMethod/alignPreset/emptyText/hideable/children/ListPreference/DEFAULT_RANGE_SHORTCUTS/useFilterCollapse/useColumnPreferences 在各任务间名字已对齐。
- 比例：计划长度 ≈ 规格 1/3，无转录体。
