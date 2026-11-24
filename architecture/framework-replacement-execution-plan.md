# 框架替代改造执行计划（obs 内核化 + dbmigrate 标准化）

> 日期：2026-11-24 · 依据：`framework-replacement-assessment.md`（评估定稿）
> 核验更新：obs 实测**已是 Prometheus 0.0.4 文本协议**（自研实现），服务侧直接
> 指标调用点仅 5 处 + obs.Wrap 中间件 7 处——替代价值降级为「内核换库背书」，
> 工作量同步缩小；dbmigrate 评估不变。

## 批次一：dbmigrate → golang-migrate（主项，~2 批次）

### 现状
四服务 Go 代码内迁移（启动即迁移、幂等）：im 260 / iam 196 / camera 163 /
file 104 行，共 723 行——无版本工具、无 inspect/diff/回滚，四份各自漂移。

### 步骤（每服务同构，先 camera 试点再推其余三家）

1. 引依赖：`golang-migrate/migrate/v4`（库模式 + CLI 两种形态都用）
2. **基线导出**：每服务从现库 dump 当前 schema 为 `migrations/000001_baseline.up.sql`
   （down 为 `DROP` 全集）；基线之上首个增量即走 migrate 版本链
3. 存量迁移代码退役：`dbmigrate.Migrate/VerifySchema` 调用点改为
   `migrate.Up(dsn, migrations)`（库模式保留「启动即迁移」语义）；
   VerifySchema 语义并入基线校验（migrate 的 dirty 检查 + version 表）
4. CLI 工具就位：`migrate -path migrations -db <dsn> {up,down,version,inspect}`，
   开发态可 diff/回滚
5. 测试：各服务迁移测试改为基于 migrations 目录（goose 风格文件测试）；
   全量测试 + 冒烟

### 风险与回退
- 基线导出必须与现库逐表 diff 为零（sqldump 对拍门禁）
- 回退 = 保留旧 dbmigrate 代码一个版本周期（feature 分支开关）

## 批次二：obs 内核换 prometheus client_golang（可选，1 批次，降级项）

### 核验后的重新定性
obs 已输出 `text/plain; version=0.0.4`（Prometheus 标准线缆）——**Grafana
本就能直连**，原评估「无生态」不成立。剩余收益：库背书（直方图分位数
正确性、边界处理）+ 维护卸载。API 面（Counter/Histogram/FuncGauge/
Registry）与调用面（5 直接 + 7 Wrap）都小。

### 步骤（内部换核，API 与线缆零变化）
1. obs 包内部：自研 Registry/Counter/Histogram 实现 → 包装
   prometheus client 的同名类型（`promauto` 注册）
2. 对外 API 签名不变（Counter.Add/Inc、Histogram.Observe、FuncGauge）——
   调用点零改动；/metrics 由 promhttp.Handler 替换自定义 handler
3. 对拍验收：替换前后 /metrics 输出 diff（同标签集、同值；promhttp 的
   HELP/TYPE 行可能格式微差——Grafana 无感）

### 判定建议
低优先：收益薄（线缆已标准）。若做，随任一服务批次搭车；不单开。

## 决策后置项（不在本计划执行）

- **阶段 4 契约网关 APISIX vs 自研**：单端口阶段 4 开工时决策（评估见
  framework-replacement-assessment §二.3）
- **契约生成器注解化**：随 HTTP 面收敛计划批次落地（external-api §7.5）

## 验收总账

- [ ] 四服务 migrations 目录就位，CLI up/down/version 实测过
- [ ] 基线 diff 门禁零差异；全量测试 + 四家冒烟绿
- [ ] （若做批次二）/metrics 对拍通过
- [ ] 旧 dbmigrate 代码删除（保留一个版本的回退窗口后）
