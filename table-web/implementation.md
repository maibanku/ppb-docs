# ProTable 样式重构实施记录（table-web）

> 实施日期：2026-11-19 ~ 2026-11-20。本文为 table-web 规格族的交付记录：实际改动、增量 API、兼容说明、有意行为变更、已知取舍、环境限制与真实测试/构建结果。截图小节留占位（控制器补）。

## 1. 概述

- **任务来源**：`ppb-docs/table-web/` 规格族（00 检查清单 + 01 架构兼容 + 02 数据源 + 03 排序 + 04 筛选时间 + 05 自定义列 + 06 列属性 + 07 列设置偏好 + 08 选择工具栏 + 09 视觉布局 + 10 迁移任务 + 11 测试验收），计划 `plan-2026-11-19-protable-style-refactor.md`，执行 Task 1–12。
- **仓库/分支**：`ppb-base`（仓根 `/Users/pipi-ban/Desktop/code/vscode/ppb-base`），分支 `feat/protable-style-refactor`，**未推送**。
- **提交区间**：`main..HEAD` = `e330b74..e60914f`，共 13 个提交（分叉点 merge-base `46c2f17`）。改动 18 个文件，+5069/−115 行。
- **外部消费方**：`ppb-iam/iam-manage-web` 经 `file:` 源码链接 + vite 别名（`base-manage-web/exports` 直指 `ppb-base/base-manage-web/exports.ts`）直接吃到分支源码，本轮全量回归通过（详见 §8）。

## 2. 改动文件清单（每提交一句）

| 提交 | 说明 |
| --- | --- |
| `e330b74` style(protable): 设计令牌与图片风格骨架（spec 09） | `--pro-list-*` 设计令牌、三档密度类（compact/default/comfortable）、图片风格骨架 |
| `d2aec3c` types(protable): 列/筛选/表格增量类型与公开导出（spec 04/06） | `types/pro-table.ts` 增量类型 + `exports.ts` 直出 |
| `86f6bf6` feat(protable): 筛选静态控件注册与参数序列化（spec 04） | 11 种筛选控件、草稿/applied 两级、序列化口径 |
| `3f1557c` feat(protable): 远程选项/联动/校验（spec 04） | optionsLoader/dataLoader、dependsOn 清值、required/min-max/validate 校验 |
| `b1d26be` feat(protable): 时间快捷项与日历月钳制（spec 04） | DEFAULT_RANGE_SHORTCUTS（点击时计算）、disableFuture、maxSpanDays |
| `025f2e3` feat(protable): 筛选单行折叠与已生效计数（spec 04 折叠布局） | useFilterCollapse、v-show 隐藏不丢值、徽标 +N |
| `8c2afce` feat(protable): 排序三态映射与本地排序切片（spec 03） | 升/降/取消三态 → sort_by/sort_order、useProTableLocal 本地过滤/排序/切片 |
| `7f599da` feat(protable): 列属性白名单透传与新旧插槽协议（spec 05/06） | 列属性白名单、cell-{key}/header-{key} 新插槽、col-{key} 旧协议共存 |
| `adce84e` feat(protable): 选择模式/序号列/工具栏分区/分页开关（spec 08 + 06 整体） | selectionMode/single 隐藏全选、showIndex/indexMode、工具栏左右分区、showPagination |
| `edf4d5e` feat(protable): 列设置面板与偏好存储（spec 07） | ProTableColumnSettings 面板、useColumnPreferences（显隐/顺序/宽度/密度） |
| `3486cd5` feat(protable): 九宫格验收页与本地/游标模式（spec 11 矩阵） | `src/views/dev/TableShowcaseView.vue` + dev 路由 + 冒烟测试 |
| `ff23ce3` fix(protable): 筛选草稿同一 tick 连发不丢值（外部消费方回归） | iam 消费方验证发现：setField 以 props.modelValue 展开，同 tick 第二次 emit 丢前值；改本地镜像即时先行（Task 12） |
| `e60914f` feat(protable): 验收页转 DEV-only 公开路由（截图前置） | 验收页迁出 admin 锚点为顶层公开路由，仅 `import.meta.env.DEV` 注册（Task 12） |

主要落点文件：`src/components/ProTable.vue`（主组件 +727 行改动）、`src/components/pro-table/ProTableFilters.vue`（筛选子组件，新增 332 行）、`src/components/pro-table/ProTableColumnSettings.vue`（新增）、`src/types/pro-table.ts`（+259 行）、`exports.ts`（+29 行）、`src/composables/use-{filter-collapse,column-preferences,protable-local}.ts`、`src/utils/list-time-shortcuts.ts`、`src/views/dev/TableShowcaseView.vue`（+508 行）、`src/router/index.ts`、测试 7 个文件（pro-table.test.ts 63 例、table-showcase、pro-table-filters、use-filter-collapse、use-column-preferences、use-protable-local、list-time-shortcuts）。

## 3. 增量 API 清单（含默认值）

### 3.1 表级新 props（`types/pro-table.ts` ProTableProps，Task 2 类型 + 后续任务落实）

| prop | 类型/默认 | 说明 |
| --- | --- | --- |
| `selectionMode` | `'none' \| 'single' \| 'multiple'`；缺省由旧 `selectable` 布尔映射（true→multiple） | 选择模式；single 经 label-class-name + CSS 隐藏全选 |
| `rowSelectable` | `(row) => boolean`；无默认 | 行级可勾选谓词（透传选择列 selectable） |
| `showIndex` | `boolean`，默认 `false` | 序号列（选择列之后；关闭无空占位） |
| `indexMode` | `'page' \| 'continuous'`，默认 `'continuous'` | 跨页连续 (page−1)×pageSize+i+1；游标模式不伪造全局序号（自然退化为页内） |
| `indexMethod` | `(index, row) => string \| number`；无默认 | 自定义序号，优先于 indexMode |
| `showPagination` | `boolean`，默认 `true` | false 仅隐藏分页区不改变取数方式 |
| `density` | `'compact' \| 'default' \| 'comfortable'`，默认 `'default'` | 密度类 `pro-table--density-{x}` |
| `searchCollapse` | `boolean`，默认 `true` | 默认折叠单行 + 展开钮 + 已生效条件计数；false 恒展开 |
| `columnSettings` | `boolean \| ColumnSettingsOptions`，默认 `false` | true=会话内偏好（不落盘）；对象形式注入 `scope { userKey, pageKey, scopeKey?, version? }` 与 `storage`（getItem/setItem/removeItem，默认 localStorage） |

### 3.2 列级新属性（ProTableColumn）

`field`（取值字段，缺省取 key）、`align`/`headerAlign`（'left'|'center'|'right'，缺省按 alignPreset 推导，最终默认 left）、`alignPreset`（'text'→左 / 'number'→右 / 'status'→居中）、`fixed`（boolean|'left'|'right'，true 按 left）、`resizable`、`sortField`（远程排序字段映射，缺省 key）、`sortMethod`（本地比较函数，返回负/零/正）、`formatter`（**新形状** `(value, row, column, rowIndex) => string`，value 取自 field；旧 `format(row)` 兼容并存，优先级 cell 插槽 > formatter > format）、`overflow`（'ellipsis'|'wrap'，默认 'ellipsis'）、`tooltip`（默认仅 ellipsis 时启用，true 强制）、`emptyText`（单元格空值占位，默认 `'—'`）、`visible`（默认 true）、`hideable`（默认 true；false=必显列）、`className`/`headerClassName`（透传 el-table-column）、`children`（分组表头，叶子列参与取值/渲染/排序）。

### 3.3 筛选字段（SearchField 联合，11 种控件）

`type`：`input`（缺省）| `number` | `number-range` | `select` | `date` | `date-range` | `datetime` | `datetime-range` | `time` | `time-range` | `tree-select` | `cascader` | `custom`。
通用：`key`（唯一）、`label`、`defaultValue`、`order`（折叠排序权重，缺省声明序）、`span`（默认 1）、`minWidth`、`disabled`、`visible`（默认 true）、`paramsKey`（参数重命名，缺省 key）、`required`、`validate`（同步/异步，返回 string|null）、`serialize`（覆盖默认序列化全流程）、`dependsOn`（上级变化清值 + 作废远程选项缓存）。
控件专有：`trim`（input 默认 true）、`maxlength`、`clearable`；number 族 `min/max/step/precision` + range 的 `startKey/endKey`（必填拆键）；select `options`（静态）/`optionsLoader`（远程，首展加载缓存重试）/`multiple`/`filterable`/`labelKey`/`valueKey`；时间族 `valueFormat`（缺省 date='YYYY-MM-DD'，datetime/范围='YYYY-MM-DD HH:mm:ss'，time='HH:mm:ss'）、`displayFormat`、`shortcuts`（**默认 true**=默认集：今天/最近一周/最近一月/最近三月；数组自定义；false 关闭）、`disableFuture`、`maxSpanDays`；tree-select `data/dataLoader/multiple/checkStrictly`；cascader `options/optionsLoader/props`；custom `filter-{key}` 插槽（value/update/disabled 上下文）。

### 3.4 插槽与事件

新插槽：`cell-{key}`（上下文 value/row/column/index）、`header-{key}`（上下文含实时排序态）、`toolbar`、`toolbar-left`（上下文 selected/clear）、`filter-{key}`、`columns`（手写列，恒渲染于配置列之前）。保留：`filters`（覆盖整条筛选区）、`expand`、`empty`、`error`、`actions`/`row-actions`、旧 `col-{key}`（与新 cell- 同列共存时仅渲染 cell- 并 DEV 警告）。
新事件：`sort-change`（{prop, order}，三态 null=取消）；透传白名单：`row-click`/`row-dblclick`/`expand-change`（el-table 原生语义转发）。保留：`selection-change`、`page-change`、`page-size-change`、`search`、`reset`、`refresh`。

### 3.5 composables 与工具（exports.ts 实际新增）

| 导出 | 说明 |
| --- | --- |
| `useProTableLocal`（+`DEFAULT_PROTABLE_PAGE_SIZE`=20） | 本地全集受控模式：过滤→排序→切片，源数组不变；sort-change→置排序 ref + 回首页由调用方接线（见 §10） |
| `useColumnPreferences`（+`preferenceStorageKey`、`ListPreference`、`PreferenceStorageLike`） | 列偏好解析/持久化（显隐/顺序/宽度/密度），storage 注入口径，scope 命名键含 version |
| `useFilterCollapse`（**组件内部用，未进 exports.ts**） | 折叠测量（宽度估算 + ResizeObserver） |
| `DEFAULT_RANGE_SHORTCUTS` / `todayRange` / `lastDays` / `lastCalendarMonths`（utils/list-time-shortcuts，**未进 exports.ts**） | 快捷项默认集与工厂 |
| `leafColumnsOf`（use-protable-local 模块导出，未进包出口） | children 展平取叶子列 |

包出口增量（exports.ts diff）：18 个新类型（§3.1–3.3 所列联合成员 + `ProTableDensity`、`ColumnAlign`、`ProTableSort`、`ColumnSettings*`）+ `useProTableLocal`/`useColumnPreferences` 值导出。既有 `useCursorAll`、`ProTable`/`SearchField` 等出口不变。

## 4. 旧接口兼容说明

- `selectable` 布尔 → `selectionMode` 映射（true→multiple），显式 selectionMode 优先；`format(row)` 旧格式化与新 `formatter(value,...)` 并存，渲染优先级 cell 插槽 > formatter > format。
- 旧 `col-{key}` 插槽继续可用；与 `cell-{key}` 同时存在仅渲染 cell-（DEV 警告提示迁移）。
- 旧 `SearchField` 静态 `options`、`startKey`/`endKey` 拆键照旧支持；旧 keyword 独立输入并入字段流首位（key 仍为 `keyword`，请求参数名不变）。
- el-table 原生属性（border/stripe/height 等）与事件经白名单透传，未新造语义。
- 偏好/列设置为**增量开关**（columnSettings 默认 false），既有消费者零视觉零行为变化。

## 5. 行为变更清单（有意为之）

1. **样式统一**：全部列表页走 `--pro-list-*` 令牌（控件高、边框、圆角、密度三档），视觉与图片风格对齐；行高 22px 基线（见 §6 第 10 条的 +1px 系统性偏差）。
2. **`shortcuts` 默认 true**：date-range/datetime-range 缺省带快捷项默认集（今天/最近一周/一月/三月，点击时计算不落缓存）。
3. **筛选折叠默认开**（searchCollapse=true）：超出首行的字段 v-show 隐藏（不卸载不丢值），展开/收起零请求，收起态展开钮带已生效条件计数徽标。
4. **reset 按钮 pending 禁用**：请求/校验进行中锁定查询（转 loading）与重置；筛选控件不禁用（草稿仍可编辑）。
5. **number min/max 从控件钳制改为提交时校验**：EP 控件会改写越界值使控件级校验不可达（详见 §6 第 7 条）；越界在提交时报错、零请求。
6. **空 keyword 从参数中省略**（原为 `keyword: undefined`，JSON 序列化等价；显式键省略使断言口径更干净）。
7. 排序三态（升→降→取消）映射 `sort_by/sort_order`，取消态两键均不带；本地排序 NaN/Infinity 降级文本比较（§6 第 3 条）。
8. 编辑筛选不请求；查询才快照为已生效条件（翻页/排序沿用已生效条件）。

## 6. 已知取舍与消费者注意项（逐条如实收录）

1. **reserveSelection 豁免三处不一致**：受控 reset 无条件清选择；受控排序本轮豁免 reserve；changeSize 无条件清。默认（非 reserve）查询/重置/排序均清。
2. **cascader 单选默认 emitPath:true 时序列化原始路径数组**（组合 6 用 emitPath:false 规避）；**paramsKey 与 startKey/endKey 并存时 paramsKey 被忽略**（拆键分支先行）；**空 keyword 从参数中省略**（原 keyword:undefined，JSON 等价）。
3. **sortMethod 方向契约为本轮新定**（升序语义、desc 取反）；**defaultSort.prop 指向不存在列时 sort_by 仍透传**（旧语义，箭头正确不显示）；NaN/Infinity 值本地排序降级文本比较。
4. **EP 2.8.8 发现**：headerClassName 为**死 prop**（th 类实际走 class-name/label-class-name）；single 模式全选隐藏经 label-class-name+CSS 实现；aria-sort 由组件内 MutationObserver 同步。
5. **徽标纯空格输入边缘**：折叠徽标 +1 但请求参数无该键（serialize trim），口径分歧属边缘可接受。
6. **Enter 隐式表单提交与 keyup.enter 双路径理论并存**（既有结构，中止逻辑兜底）——截图轮 GUI 冒烟核查项。
7. **number min/max 提交时校验**（非控件钳制）：EP 控件会改写越界值使控件级校验不可达，故移到提交路径。
8. **列无权限概念**：spec 07 权限列过滤今日无对象（列定义无 perm 字段）；收口点在 useColumnPreferences 的 allowedLeaf（后续增强挂点）。
9. **columnSettings=true 无 scope=会话内偏好**（不落盘，仍可完整操作）；settingsConfig 为 setup 期捕获（响应式变更不追踪）。
10. **密度 comfortable 分页控件未达 40px**（Task 1 遗留，GUI 校准项）；**行高 22px 基线 vs EP 23px line-height 系统性 +1px**（37/45/53 实际值）。
11. **本地排序回首页由调用方接线**（useProtableLocal 注释明确；showcase block-local 已示范 sort-change→置排序 ref+resetToFirstPage）。
12. （Task 12 补充）**筛选草稿同一 tick 连发曾丢值，已修复**：`ff23ce3` 前 setField 以 props.modelValue 展开，父级重渲染未回流时第二次同步 emit 覆盖第一次的值（iam UsersView 既有交互口径暴露）；现本地镜像即时先行、父级回流后重同步。消费者无感知，回归测试 `pro-table-filters.test.ts` 在库。

## 7. 环境限制（非本轮引入，已留证）

1. **`standalone-entry.test.ts` 采集失败**：`Failed to resolve import "chat-manage-web/plugin"`——独立台壳（entry/standalone-plugins.ts）直引跨仓源码，本检出无 ppb-chat-wt worktree。干净 HEAD（edf4d5e stash 复跑，Task 11 台账）同样失败，收集到 0 个测试用例，与本分支无关。
2. **`npm run build` 既有失败**：同因——standalone 壳 main.ts/standalone-plugins.ts 跨仓 camera/chat 源码（本分支复现错误头：`[vite:load-fallback] Could not load .../ppb-chat-wt/chat-manage-web/src/plugin.ts ... ENOENT`，Build failed in 133ms）。**SSR 构建替代证据**（Task 11 报告）：`vite build --ssr src/router/index.ts` 成功，路由图全量编译含懒加载块 TableShowcaseView。不修（六仓分家后的环境问题）。
3. 一次性 vitest 全量轮曾出现**卸载后 debounce doLayout 的 rAF 未捕获异常**（环境 teardown 后计时器竞态）：279 用例本身全过；同分支复跑与干净 HEAD 复跑均不复现，判定为 EP/测试环境竞态噪声，非用例失败。

## 8. 测试与构建真实结果（本轮实际命令与输出摘要）

### 8.1 底座 ppb-base/base-manage-web（分支 HEAD=e60914f）

| 命令 | 结果 |
| --- | --- |
| `npm run test` | **280/280 通过**（23 文件：22 绿 + standalone-entry 采集失败 0 例既有）；较基线 279 +1（新增 pro-table-filters 回归） |
| `npm run typecheck` | **绿**（vue-tsc 双 tsconfig，exit 0） |
| `npm run build:lib` | **绿**：`dist-lib/base-manage-web.css 41.21 kB (gzip 8.09)`、`base-manage-web.js 187.14 kB (gzip 52.63)`；54 个 d.ts 检查、12 个重写 |
| `npm run build` | **既有失败复现**（§7.2，错误头已录）；不修 |

### 8.2 外部消费方 ppb-iam/iam-manage-web（file: 链接直吃分支源码）

| 命令 | 结果 |
| --- | --- |
| `npm run test` | 首轮 **286/287**：`UsersView.test.ts「查询=带筛选回第 1 页」`失败（请求参数缺 `status: 2`）——**确认为本分支引入**（§6.12 丢值缺陷），修复（`ff23ce3`）后复跑 **287/287 全绿**（39 文件） |
| `npm run typecheck` | **绿**（exit 0） |
| `npm run build` | **绿**（✓ built in 3.48s；仅 chunk>1024kB 既有建议性警告） |

失败归因方法：iam 仓禁改文件、ppb-base 禁切 main，故以「最小复现在 ppb-base 内重建（同交互口径丢 status）+ 旧实现 `v-model` 直改共享对象无此竞态的 git 对照」完成因果确认，修复落在底座侧后 iam 全量复跑验证。

### 8.3 路由调整验证

`table-showcase.test.ts` 改判：顶层单层 matched、`resolve().path === '/dev/table-showcase'`、`meta.public === true`、`vi.stubEnv('DEV', false)` 下 `createBaseRouter()` 不注册该路由。2/2 绿（先红后绿）。

## 9. 示例入口

- dev server：`cd ppb-base/base-manage-web && npm run dev`（:8210）。
- 验收页：**`/dev/table-showcase`**（顶层公开路由，仅 DEV 注册——dev server 无后端、免 iam context 守卫可直开；生产构建不注册，且菜单唯一来源是服务端 context 目录，**生产零入口**）。
- 页面内容：spec 11 九组合（combo-1..9，data-testid 稳定）+ 本地全集（block-local）/游标（block-cursor）两区块，确定性 mock 236 行（无后端、无真实用户数据）。

## 10. 未完成项与后续增强

- 多列排序；查询方案保存（命名方案 CRUD）；URL 条件记忆（分享/回跳还原）；虚拟滚动（大表）。
- 通用编辑表（表单↔表格联动）；summary 合计行插槽与 loading 骨架插槽（spec 05 低频项，九宫格无该组合，列后续）。
- 服务端偏好同步（当前仅本地 storage 注入）；权限列过滤（列无 perm 概念，收口点 useColumnPreferences allowedLeaf）。
- badge 纯空格边缘（§6.5 口径统一）；密度 comfortable 分页控件 40px 校准（§6.10）；行高 +1px 系统性偏差与 EP 对齐评估。
- Enter 双路径 GUI 冒烟核查（§6.6，截图轮）。

## 11. 截图

（占位：由控制器在截图轮补 combo 1–9、窄容器 768/375、筛选展开态、fixedFoot 滚动、固定列、错误/空态、密度切换、暗色主题；存 `ppb-docs/table-web/screenshots/`。）
