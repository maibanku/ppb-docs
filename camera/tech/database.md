# AI 相机 · 数据库专文（ppb_camera）

> V0.1 · 2026-10-26。本文件是 ppb_camera 库表结构的**权威参考**：DDL、唯一键、CHECK 约束、雪花节点号与双方言注意事项。GORM 实体（`ppb-chat/server-camera/internal/domain/model.go`、`subject.go`）与本文件对齐，迁移经 `server-camera/cmd/migrate` 或 `cmd/server` 启动自动执行。表约束的业务语义详见[技术大纲](技术大纲.md) §6/§9；本文件只写"怎么落库"。

## 通用约定

- **无物理外键**：经业务主键（biz_key）逻辑关联，对齐 ppb-chat 四服务迁移纪律。
- **主键**：全部表应用侧雪花发号（GORM `BeforeCreate` 钩子 → `server-pkg/dombase`，**camera 节点号 = 6**；user=1 im=2 mail=3 file=4 plugin=5）。显式赋过 id 的行尊重原值（seed/复制行场景）。
- **公共四柱列**：`create_time` / `update_time` / `deleted_flag` / `deleted_time`（dombase.BaseModel）。
- **业务主键前缀**：`subj_`（主体）/ `task_`（分析任务）/ `tpl_`（模板）/ `fbk_`（反馈）；额度桶/预留/事件行的 biz_key 无业务前缀约定（内部账本行）。付费桶批次键用 `pb_` 前缀（见下）。
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
  kind                INT             NOT NULL,           -- 1 免费月桶 2 付费额度包 3 会员订阅
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

- **period_key 语义（2026-10-26 修正）**：免费桶 = UTC `YYYY-MM`；**付费包/订阅 = 购买批次键（`pb_` 前缀，一次购买一行）**。旧口径"付费包 period_key 空串"会使同主体第二张付费包必撞 `uk_bucket_subject_kind_period`——批次键即消除该冲突，多张付费包天然并存。
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

## outbox_events（业务事件外寄）

复用 `server-pkg/outbox.Event`（与业务数据同事务写入，relay 发布 MQ），表结构以共享包为准，此处不重复。迁移顺序中排在业务表之后（`camera_migrate.go` migrateOrder）。

## 双方言注意事项

| 事项 | SQLite 起步态 | MySQL 目标态 |
|---|---|---|
| 建表 | GORM AutoMigrate（`cmd/migrate` / 启动自动） | deploy/sql 归档脚本（以本文件为基准） |
| CHECK 约束 | 建表即生效（gorm check 标签）；**AutoMigrate 不向已存在表补 CHECK**，旧起步库需重建后生效 | 8.0.16+ 强制执行 |
| 索引名 | 库级全局唯一（复合唯一索引以 `uk_*` 命名落地） | 表级隔离，同名无冲突 |
| 连接 | 单写者：busy_timeout 5000 + WAL + 连接池限 1（server-pkg/database） | 连接池 25/10/30min |
| 行锁语义 | 池层序列化近似 | `SELECT ... FOR UPDATE`（M2 并发结算集成测试覆盖） |

## 启动校验（VerifySchema）

`repo.VerifySchema` fail-fast 校验：六表存在 + 关键列（quota_buckets 四计数列）+ 命名索引（`uk_bucket_subject_kind_period` / `uk_task_subject_request` / `idx_task_sweep` / `idx_rsv_bucket` / `uk_qevent_task_type` / `idx_qevent_bucket`）。CHECK 的**执行行为**无法经 Migrator 探测，由 `camera_migrate_test.go` 单测覆盖（负值插入必须报错）。
