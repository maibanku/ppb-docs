# AI 相机 · 数据库专文（ppb_camera）

> V0.2 · 2026-11-03。本文件是 ppb_camera 库表结构的**权威参考**：DDL、唯一键、CHECK 约束、雪花节点号与双方言注意事项。GORM 实体（`ppb-chat/server-camera/internal/domain`）与本文件对齐，迁移经 `server-camera/cmd/migrate` 或 `cmd/server` 启动自动执行。表约束的业务语义详见[技术大纲](技术大纲.md) §6/§9；本文件只写"怎么落库"。
>
> V0.2 变更（T21 补录）：新增 sms_codes（T14 auth）与 template_versions/styles/strategy_versions/quota_compensations/feedback_tickets（T19 管理面）六表；templates/content_revisions 两表为更早内容域存量（DDL 见 `ppb-base/deploy/sql/ppb_camera/templates.sql`、`content_revisions.sql`，专文段落待补——存量缺口如实标注）。

## 通用约定

- **无物理外键**：经业务主键（biz_key）逻辑关联，对齐 ppb-chat 四服务迁移纪律。
- **主键**：全部表应用侧雪花发号（GORM `BeforeCreate` 钩子 → `server-pkg/dombase`，**camera 节点号 = 6**；user=1 im=2 mail=3 file=4 plugin=5）。显式赋过 id 的行尊重原值（seed/复制行场景）。
- **公共四柱列**：`create_time` / `update_time` / `deleted_flag` / `deleted_time`（dombase.BaseModel）。
- **业务主键前缀**：`subj_`（主体）/ `task_`（分析任务）/ `tpl_`（模板）/ `fbk_`（反馈）/ `tvr_`（模板版本）/ `styl_`（风格）/ `stg_`（策略链）/ `svr_`（策略版本）/ `cmp_`（补偿单）；额度桶/预留/事件行的 biz_key 无业务前缀约定（内部账本行）。付费桶批次键用 `pb_` 前缀（见下）。
- **起步态 SQLite / 目标态 MySQL**：AutoMigrate 服务 SQLite 起步态；MySQL 目标态以 deploy/sql 归档脚本为准，本文件 DDL 即归档基准。

## subjects（主体）

身份锚点：匿名与登录共用一行、同一 subject_id；绑定升级为登录主体时原地改 Kind（额度随行保持）。

```sql
CREATE TABLE subjects (
  subject_id       BIGINT UNSIGNED NOT NULL PRIMARY KEY,   -- 雪花（节点 6）
  subject_biz_key  VARCHAR(64)     NOT NULL UNIQUE,        -- subj_ 前缀
  create_time      DATETIME(3)     NOT NULL,
  update_time      DATETIME(3)     NOT NULL,
  deleted_flag     TINYINT         NOT NULL DEFAULT 0,
  deleted_time     DATETIME(3)     NULL,
  kind             INT             NOT NULL DEFAULT 1,     -- 1 匿名 2 登录
  phone_hash       VARCHAR(64)     NOT NULL DEFAULT '',    -- 手机号哈希（登录绑定判重）
  apple_sub        VARCHAR(128)    NOT NULL DEFAULT '',    -- Apple Sign-In sub
  bind_source      INT             NOT NULL DEFAULT 0,     -- 0 未绑定 1 手机 2 Apple
  bind_at          DATETIME(3)     NULL,
  status           INT             NOT NULL DEFAULT 1,     -- 1 正常 2 禁用
  INDEX idx_subject_phone (phone_hash),
  INDEX idx_subject_apple (apple_sub)
);
```

- `phone_hash` / `apple_sub` **只建普通索引**：MySQL 无部分索引，匿名行两列均为空串，全表唯一索引会被空串互撞；唯一性由绑定事务内"先查后插"保证（防重复绑定 CAM-4091，M2 落地）。

## quota_buckets（额度桶）

```sql
CREATE TABLE quota_buckets (
  quota_bucket_id     BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  quota_bucket_biz_key VARCHAR(64)    NOT NULL UNIQUE,
  create_time         DATETIME(3)     NOT NULL,
  update_time         DATETIME(3)     NOT NULL,
  deleted_flag        TINYINT         NOT NULL DEFAULT 0,
  deleted_time        DATETIME(3)     NULL,
  subject_id          VARCHAR(64)     NOT NULL,
  kind                INT             NOT NULL,           -- 1 免费月桶 2 付费额度包 3 会员订阅 4 运营补偿（T19）
  period_key          VARCHAR(32)     NOT NULL DEFAULT '',
  granted             INT             NOT NULL DEFAULT 0,
  available           INT             NOT NULL DEFAULT 0,
  reserved            INT             NOT NULL DEFAULT 0,
  spent               INT             NOT NULL DEFAULT 0,
  expires_at          DATETIME(3)     NOT NULL,
  UNIQUE KEY uk_bucket_subject_kind_period (subject_id, kind, period_key),
  CONSTRAINT chk_bucket_nonneg CHECK (
    available >= 0 AND reserved >= 0 AND spent >= 0 AND granted >= 0
  )
);
```

- **period_key 语义（2026-10-26 修正）**：免费桶 = UTC `YYYY-MM`；**付费包/订阅 = 购买批次键（`pb_` 前缀，一次购买一行）**；运营补偿桶（kind=4，T19）= 补偿单号（`cmp_` 前缀，复合唯一键下同主体多次补偿互不冲突；TTL 90 天——T19 自裁决值待产品终审）。旧口径"付费包 period_key 空串"会使同主体第二张付费包必撞 `uk_bucket_subject_kind_period`——批次键即消除该冲突，多张付费包天然并存。
- 非负约束由 CHECK 承载（gorm `check` 标签建表落地，GORM v1.31 起 `check:名字,条件` 语法）。

## analysis_tasks（分析任务）

```sql
CREATE TABLE analysis_tasks (
  analysis_task_id      BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  analysis_task_biz_key VARCHAR(64)     NOT NULL UNIQUE,   -- task_ 前缀
  create_time           DATETIME(3)     NOT NULL,
  update_time           DATETIME(3)     NOT NULL,
  deleted_flag          TINYINT         NOT NULL DEFAULT 0,
  deleted_time          DATETIME(3)     NULL,
  subject_id            VARCHAR(64)     NOT NULL,
  request_id            VARCHAR(64)     NOT NULL,
  payload_hash          VARCHAR(64)     NOT NULL,
  purpose_id            VARCHAR(64)     NULL,
  template_id           VARCHAR(64)     NULL,
  consent_version       VARCHAR(32)     NOT NULL,
  status                INT             NOT NULL,          -- 见下
  release_reason        INT             NOT NULL DEFAULT 0, -- 0 无 1 failed 2 cancelled 3 expired
  result_version        VARCHAR(64)     NULL,
  result_json           TEXT            NULL,
  deadline_at           DATETIME(3)     NOT NULL,
  committed_at          DATETIME(3)     NULL,
  released_at           DATETIME(3)     NULL,
  UNIQUE KEY uk_task_subject_request (subject_id, request_id),
  INDEX idx_task_sweep (status, deadline_at)
);
```

- **status 取值：`2 reserved / 3 running / 4 ready / 5 committed / 6 released`**（`1 created` 是受理前概念态，不落库——创建与预留在同一事务提交，持久行不见 created）。
- 状态迁移合法性（`reserved→running→ready→committed`，终态互斥不可逆）见 domain `analysis_task.go`，由状态条件更新强制。

## reservations（额度预留）

```sql
CREATE TABLE reservations (
  reservation_id      BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  reservation_biz_key VARCHAR(64)     NOT NULL UNIQUE,
  create_time         DATETIME(3)     NOT NULL,
  update_time         DATETIME(3)     NOT NULL,
  deleted_flag        TINYINT         NOT NULL DEFAULT 0,
  deleted_time        DATETIME(3)     NULL,
  task_id             VARCHAR(64)     NOT NULL UNIQUE,    -- 一任务一预留
  bucket_id           VARCHAR(64)     NOT NULL,
  amount              INT             NOT NULL DEFAULT 1,
  status              INT             NOT NULL,           -- 1 reserved 2 committed 3 released
  ended_at            DATETIME(3)     NULL,
  INDEX idx_rsv_bucket (bucket_id),
  CONSTRAINT chk_rsv_amount CHECK (amount = 1)
);
```

## quota_events（额度事件流水）

```sql
CREATE TABLE quota_events (
  quota_event_id      BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  quota_event_biz_key VARCHAR(64)     NOT NULL UNIQUE,
  create_time         DATETIME(3)     NOT NULL,
  update_time         DATETIME(3)     NOT NULL,
  deleted_flag        TINYINT         NOT NULL DEFAULT 0,
  deleted_time        DATETIME(3)     NULL,
  task_id             VARCHAR(64)     NOT NULL,
  event_type          INT             NOT NULL,           -- 1 reserve 2 commit 3 release
  bucket_id           VARCHAR(64)     NOT NULL,
  amount              INT             NOT NULL DEFAULT 1,
  occur_at            DATETIME(3)     NOT NULL,
  UNIQUE KEY uk_qevent_task_type (task_id, event_type),
  INDEX idx_qevent_bucket (bucket_id),
  CONSTRAINT chk_qevent_amount CHECK (amount = 1)
);
```

- `UNIQUE(task_id, event_type)` 保证 reserve/commit/release 各至多一条；commit/release 互斥由"唯一键 + 任务状态条件更新"共同保证（技术大纲 §9.1）。

## sms_codes（短信验证码频控状态 · T14 auth）

一行一手机号（`phone_hash` HMAC 摘要唯一）；验证码不落明文（`code_hash` 同为 HMAC）。状态机：60s 重发冷却（`next_send_at`，冷却内 CAM-4292 带剩余秒数）、每日上限（`day_key` UTC 日键 + `sends_today`，超限 CAM-4293）、3 次错锁 60s（`wrong_count` 达 3 置 `lock_until` 并清零，锁内正码也拒）、消费即失效（`code_hash` 清空，单次有效）。并发安全由行锁（`SELECT ... FOR UPDATE`，repo/sms_repo.go）串行裁决同手机号并发发送/校验。不进 subjects/quota 结算链路。

```sql
CREATE TABLE sms_codes (
  sms_code_id   BIGINT UNSIGNED NOT NULL PRIMARY KEY, -- 雪花（节点 6）
  create_time   DATETIME(3)     NOT NULL,
  update_time   DATETIME(3)     NOT NULL,
  deleted_flag  TINYINT         NOT NULL DEFAULT 0,
  deleted_time  DATETIME(3)     NULL,
  phone_hash    VARCHAR(64)     NOT NULL,
  code_hash     VARCHAR(64)     NOT NULL DEFAULT '',
  expire_at     DATETIME(3)     NOT NULL,
  next_send_at  DATETIME(3)     NOT NULL,
  day_key       VARCHAR(10)     NOT NULL DEFAULT '',
  sends_today   INT             NOT NULL DEFAULT 0,
  wrong_count   INT             NOT NULL DEFAULT 0,
  lock_until    DATETIME(3)     NULL,
  UNIQUE KEY uk_sms_phone (phone_hash),
  CONSTRAINT chk_sms_sends_nonneg CHECK (sends_today >= 0),
  CONSTRAINT chk_sms_wrong_nonneg CHECK (wrong_count >= 0)
);
```

> **已知缺陷（2026-11-03 验收发现，D1）**：`RecordSend` 首次建行时以零值 `time.Time` 插入 `expire_at`/`next_send_at`（'0000-00-00'），MySQL 严格模式 Error 1292 拒绝 → 发码 CAM-9001。SQLite 接受零日期故单测全绿。修复方向：时间列改可空/哨兵值，或建行即写真实值。修复后本段注记删除。

## outbox_events（业务事件外寄）

复用 `server-pkg/outbox.Event`（与业务数据同事务写入，relay 发布 MQ），表结构以共享包为准，此处不重复。迁移顺序中排在业务表之后（`camera_migrate.go` migrateOrder）。

## templates / content_revisions（内容域 · 存量两表）

早于本专文 V0.1 的内容域存量表（模板主表 + 全局 revision 游标），T19 后 templates 增 `status`（0 草稿/1 复核中/2 已发布/3 已下架，客户端只下发 2/3）与 `submitted_by`（发布双人审批锚）列。DDL 以 `deploy/sql/ppb_camera/templates.sql` + `incremental/20261102_01_admin_t19.sql` 归档为准——**专文完整段落待补（存量缺口，已如实标注）**。

## 管理面五表（T19）

### template_versions（模板版本链）

每次保存草稿/发布通过落一行**不可变**内容快照——版本 diff 的对比素材（PRD §6.2）。行不更新不删除（审计事实）；`version_no` 模板内自增（同模板唯一），与客户端增量协议的 `templates.revision`（全局游标）分属两套版本语义。

```sql
CREATE TABLE template_versions (
  template_version_id      BIGINT UNSIGNED NOT NULL PRIMARY KEY, -- 雪花（节点 6）
  template_version_biz_key VARCHAR(64)    NOT NULL UNIQUE,       -- tvr_ 前缀
  create_time              DATETIME(3)    NOT NULL,
  update_time              DATETIME(3)    NOT NULL,
  deleted_flag             TINYINT        NOT NULL DEFAULT 0,
  deleted_time             DATETIME(3)    NULL,
  template_biz_key         VARCHAR(64)    NOT NULL,               -- 所属模板（逻辑引用）
  version_no               BIGINT         NOT NULL,               -- 模板内自增序号（1 起）
  purpose_id               VARCHAR(64)    NOT NULL,
  name                     VARCHAR(128)   NOT NULL,
  difficulty               INT            NOT NULL DEFAULT 1,
  scene_tags               VARCHAR(512)   NOT NULL DEFAULT '',
  pose_template_id         VARCHAR(64)    NOT NULL DEFAULT '',
  asset_hashes             VARCHAR(2048)  NOT NULL DEFAULT '',
  status                   INT            NOT NULL,               -- 0 草稿稿本 2 发布定本
  author_actor             VARCHAR(64)    NOT NULL DEFAULT '',    -- 保存操作者
  reviewer_actor           VARCHAR(64)    NOT NULL DEFAULT '',    -- 发布审批人（草稿空）
  note                     VARCHAR(512)   NOT NULL DEFAULT '',
  UNIQUE KEY uk_tvr_tpl_no (template_biz_key, version_no),
  CONSTRAINT chk_tvr_nonneg CHECK (version_no >= 1),
  CONSTRAINT chk_tvr_difficulty CHECK (difficulty BETWEEN 1 AND 3),
  CONSTRAINT chk_tvr_status CHECK (status IN (0, 2))
);
```

### styles（风格记录）

PRD §6.3：V1 6 风格随 App 版本发布，后台只记录版本与上下架标记；撤回=发 App 补丁版本（本表标记仅运营事实留痕，不驱动客户端行为）。内容/预览样片不在本表承载。迁移幂等种子 6 行（自然/清透/胶片/黑白/暖阳/冷调，`styl_` 固定键，OnConflict 不覆盖运营标记）。

```sql
CREATE TABLE styles (
  style_id        BIGINT UNSIGNED NOT NULL PRIMARY KEY, -- 雪花（节点 6）
  style_biz_key   VARCHAR(64)    NOT NULL UNIQUE,       -- styl_ 前缀（种子固定键）
  create_time     DATETIME(3)    NOT NULL,
  update_time     DATETIME(3)    NOT NULL,
  deleted_flag    TINYINT        NOT NULL DEFAULT 0,
  deleted_time    DATETIME(3)    NULL,
  name            VARCHAR(128)   NOT NULL,
  version         VARCHAR(64)    NOT NULL DEFAULT '',   -- 随 App 发布的版本（记录性）
  status          INT            NOT NULL DEFAULT 1,    -- 1 上架 2 下架撤回标记
  note            VARCHAR(512)   NOT NULL DEFAULT '',
  CONSTRAINT chk_style_status CHECK (status IN (1, 2))
);
```

### strategy_versions（AI 策略版本链）

提示词与场景参数的版本链（PRD §6.4）。`strategy_key` 聚合多版本（`version_no` 链内唯一）；同链至多一行 `status=3` 生效中（激活/回滚由管理面事务让位保证）；激活双人复核（操作者≠author_actor，同人 CAM-4032）。V1 管理面不建模灰度链（分发器未建不虚构灰度态；`scene_params` 承载灰度参数供后续接入）。`scene_params` 服务端校验为合法 JSON 对象。

```sql
CREATE TABLE strategy_versions (
  strategy_version_id      BIGINT UNSIGNED NOT NULL PRIMARY KEY, -- 雪花（节点 6）
  strategy_version_biz_key VARCHAR(64)    NOT NULL UNIQUE,       -- svr_ 前缀
  create_time              DATETIME(3)    NOT NULL,
  update_time              DATETIME(3)    NOT NULL,
  deleted_flag             TINYINT        NOT NULL DEFAULT 0,
  deleted_time             DATETIME(3)    NULL,
  strategy_key             VARCHAR(64)    NOT NULL,               -- stg_ 前缀链标识
  version_no               BIGINT         NOT NULL,               -- 链内自增（1 起）
  prompt                   VARCHAR(8192)  NOT NULL,
  scene_params             VARCHAR(4096)  NOT NULL,               -- JSON 对象
  status                   INT            NOT NULL DEFAULT 1,    -- 1 草稿 2 复核中 3 生效中 4 已废弃
  author_actor             VARCHAR(64)    NOT NULL DEFAULT '',
  reviewer_actor           VARCHAR(64)    NOT NULL DEFAULT '',
  note                     VARCHAR(512)   NOT NULL DEFAULT '',
  activated_at             DATETIME(3)    NULL,
  UNIQUE KEY uk_svr_key_no (strategy_key, version_no),
  CONSTRAINT chk_svr_nonneg CHECK (version_no >= 1),
  CONSTRAINT chk_svr_status CHECK (status IN (1, 2, 3, 4))
);
```

### quota_compensations（额度补偿单）

申请人发起 → 另一名持 `camera.compensation.write` 操作者审批（PRD §6.5 双人红线，同人 CAM-4032）。通过即同事务向 quota_buckets 发放 kind=4 补偿桶（`period_key`=补偿单号，TTL 90 天——T19 自裁决值）；终态重复审批幂等（`bucket_biz_key` 为发放锚，条件状态更新保证至多发放一次）。

```sql
CREATE TABLE quota_compensations (
  compensation_id        BIGINT UNSIGNED NOT NULL PRIMARY KEY, -- 雪花（节点 6）
  compensation_biz_key   VARCHAR(64)    NOT NULL UNIQUE,       -- cmp_ 前缀
  create_time            DATETIME(3)    NOT NULL,
  update_time            DATETIME(3)    NOT NULL,
  deleted_flag           TINYINT        NOT NULL DEFAULT 0,
  deleted_time           DATETIME(3)    NULL,
  subject_biz_key        VARCHAR(64)    NOT NULL,               -- 被补偿主体（逻辑引用）
  amount                 INT            NOT NULL,               -- 1..1000
  reason                 VARCHAR(512)   NOT NULL,
  status                 INT            NOT NULL DEFAULT 1,     -- 1 待审批 2 已通过 3 已拒绝
  applicant_actor        VARCHAR(64)    NOT NULL,
  approver_actor         VARCHAR(64)    NOT NULL DEFAULT '',
  review_note            VARCHAR(512)   NOT NULL DEFAULT '',
  bucket_biz_key         VARCHAR(64)    NOT NULL DEFAULT '',    -- 发放锚（未通过空）
  reviewed_at            DATETIME(3)    NULL,
  INDEX idx_cmp_subject (subject_biz_key),
  CONSTRAINT chk_cmp_amount CHECK (amount BETWEEN 1 AND 1000),
  CONSTRAINT chk_cmp_status CHECK (status IN (1, 2, 3))
);
```

### feedback_tickets（反馈工单）

客户端 SubmitFeedback 的落库目标（T14 留 CAM-0001 未接线锚——接线前工单源为空，管理面如实空列表）。线性流转 1 待处理→2 处理中→3 已解决（跳级/回退 CAM-4095）；截图附件不进本表（PRD §6.5 授权客服独立通道），仅 `has_screenshot` 授权标记。

```sql
CREATE TABLE feedback_tickets (
  feedback_ticket_id  BIGINT UNSIGNED NOT NULL PRIMARY KEY, -- 雪花（节点 6）
  feedback_biz_key    VARCHAR(64)    NOT NULL UNIQUE,       -- fbk_ 前缀
  create_time         DATETIME(3)    NOT NULL,
  update_time         DATETIME(3)    NOT NULL,
  deleted_flag        TINYINT        NOT NULL DEFAULT 0,
  deleted_time        DATETIME(3)    NULL,
  subject_biz_key     VARCHAR(64)    NOT NULL,
  kind                INT            NOT NULL,               -- 1 建议不准 2 闪退 3 其他
  content             VARCHAR(4096)  NOT NULL,
  app_version         VARCHAR(64)    NOT NULL DEFAULT '',
  status              INT            NOT NULL DEFAULT 1,     -- 1 待处理 2 处理中 3 已解决
  handler_actor       VARCHAR(64)    NOT NULL DEFAULT '',
  has_screenshot      TINYINT        NOT NULL DEFAULT 0,
  resolution_note     VARCHAR(512)   NOT NULL DEFAULT '',
  INDEX idx_fbk_subject (subject_biz_key),
  CONSTRAINT chk_fbk_kind CHECK (kind BETWEEN 1 AND 3),
  CONSTRAINT chk_fbk_status CHECK (status IN (1, 2, 3))
);
```

## 双方言注意事项

| 事项 | SQLite 起步态 | MySQL 目标态 |
|---|---|---|
| 建表 | GORM AutoMigrate（`cmd/migrate` / 启动自动） | deploy/sql 归档脚本（以本文件为基准） |
| CHECK 约束 | 建表即生效（gorm check 标签）；**AutoMigrate 不向已存在表补 CHECK**，旧起步库需重建后生效 | 8.0.16+ 强制执行 |
| 索引名 | 库级全局唯一（复合唯一索引以 `uk_*` 命名落地） | 表级隔离，同名无冲突 |
| 连接 | 单写者：busy_timeout 5000 + WAL + 连接池限 1（server-pkg/database） | 连接池 25/10/30min |
| 行锁语义 | 池层序列化近似 | `SELECT ... FOR UPDATE`（M2 并发结算集成测试覆盖） |

## 启动校验（VerifySchema）

`repo.VerifySchema` fail-fast 校验（`camera_migrate.go` schemaChecks，随 T14/T19 扩至全表）：**14 表存在**（subjects/quota_buckets/analysis_tasks/reservations/quota_events/sms_codes/templates/content_revisions/template_versions/styles/strategy_versions/quota_compensations/feedback_tickets/outbox_events）+ 关键列（quota_buckets 四计数列、sms_codes 八状态列、templates 状态/审批列、各管理表审计列）+ 命名索引（`uk_bucket_subject_kind_period` / `uk_task_subject_request` / `idx_task_sweep` / `idx_rsv_bucket` / `uk_qevent_task_type` / `idx_qevent_bucket` / `idx_tpl_revision` / `uk_tvr_tpl_no` / `uk_svr_key_no` / `idx_cmp_subject` / `idx_fbk_subject`），缺失项汇总为单个 error。CHECK 的**执行行为**无法经 Migrator 探测，由单测覆盖（负值/非法状态插入必须报错）。

## 存量库增量迁移

MySQL 存量库升级走 `deploy/sql/ppb_camera/incremental/`（如 `20261102_01_admin_t19.sql`：templates 加列守卫 ALTER、chk_tpl_status 放宽、styles 种子 INSERT IGNORE）；SQLite 起步态由 AutoMigrate 建表，二者与本文 DDL 语义对齐（AutoMigrate 不向已存在表补 CHECK——旧起步库需重建后生效）。
