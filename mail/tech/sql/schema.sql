-- PPB Mail / ppb_mail 目标态表与视图 v0.2，2026-11-24
-- MySQL 8.0.16+。目标态全新建库，不是存量升级脚本。
-- 邮件正文不进本库：邮件存在 Dovecot 的 Maildir 目录；本库只有账号、配置、日志等元数据。
-- 主键应用侧雪花发号，无 AUTO_INCREMENT；接口里大整数按字符串传输。
-- 所有列名至少两个单词以_连接；create_time/update_time/deleted_flag 沿用平台约定。
-- InnoDB + utf8mb4_unicode_ci；地址和密钥类精确列使用 utf8mb4_bin。
-- 逻辑外键，由应用验证引用、同域和状态；不创建物理 FK。
-- 本库不使用软删：域、邮箱、别名等记录删除后，名称或地址必须可以重新分配，所以一律物理删除，
-- 历史由审计表保留。业务表仍带 deleted_flag 列以沿用平台约定，取值恒为 0；视图按该列过滤只是防御。
-- 过程、日志、临时表不带 update_time 和软删列，按保留期物理清理。
-- 第 4 节的视图给 Postfix 和 Dovecot 用只读账号查询，控制面不读视图。
-- 2026-11-24 已在 MySQL 8.0.45 的一次性容器里执行通过：建表建视图、样例数据断言、13 条负向约束测试，脚本在 verify/ 目录。
-- 这不等于生产迁移验收，见同目录 README。
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS `ppb_mail` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `ppb_mail`;

-- ============ 0. 系统级登记 ============

-- 对外主机名与公网地址；全库只有一行，主键固定为 1。
-- 由控制面每次启动时按部署配置写入；线上页面只读，不提供修改接口
CREATE TABLE `mail_endpoint` (
  `mail_endpoint_id` BIGINT UNSIGNED NOT NULL COMMENT '固定为 1',
  `public_hostname` VARCHAR(253) COLLATE utf8mb4_bin NOT NULL COMMENT '对外主机名，小写；证书、MX、PTR 都指向它',
  `public_ip` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '公网 IPv4 或 IPv6 地址',
  `dns_check_status` TINYINT NOT NULL DEFAULT 0 COMMENT '全局检查项：0=未校验；1=全部通过；2=有未通过',
  `dns_check_detail` JSON NULL COMMENT '逐项结果数组，元素为 {item, status, message, time}',
  `dns_check_time` DATETIME NULL COMMENT '最近一次全局检查时间，UTC',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  PRIMARY KEY (`mail_endpoint_id`),
  CHECK (`mail_endpoint_id` = 1),
  CHECK (`dns_check_status` IN (0,1,2))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='对外主机名与公网地址';

-- ============ 1. 域名 ============

-- 邮件域；一个域一行。删除域时本行、它的 DKIM 密钥行和保留地址行一并物理删除。
-- “默认域至多一个”由生成列加唯一索引保证；“至少一个”由应用在切换默认域的同一事务里保证
CREATE TABLE `mail_domain` (
  `mail_domain_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `domain_name` VARCHAR(253) COLLATE utf8mb4_bin NOT NULL COMMENT '邮件域，小写',
  `default_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '默认域：0否 1是；全库至多一行',
  `domain_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=正常；2=停用',
  `dkim_selector` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '当前签名用的 DKIM 选择器；指向 DKIM 密钥表里 active_flag=1 的那一行',
  `default_slot` TINYINT GENERATED ALWAYS AS (IF(`default_flag` = 1, 1, NULL)) VIRTUAL COMMENT '由 default_flag 生成；配合唯一索引保证默认域至多一行',
  `dns_check_status` TINYINT NOT NULL DEFAULT 0 COMMENT '0=未校验；1=全部通过；2=有未通过',
  `dns_check_detail` JSON NULL COMMENT '逐项结果数组，元素为 {item, status, message, time}；检查项为 MX、SPF、DKIM、DMARC',
  `dns_check_time` DATETIME NULL COMMENT '最近一次 DNS 校验时间，UTC',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`mail_domain_id`),
  UNIQUE KEY `uk_mail_domain_name` (`domain_name`),
  UNIQUE KEY `uk_mail_domain_default` (`default_slot`),
  CHECK (`domain_status` IN (1,2)),
  CHECK (`dns_check_status` IN (0,1,2)),
  CHECK (`default_flag` IN (0,1)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='邮件域';

-- DKIM 密钥；轮换时新旧选择器并存
CREATE TABLE `mail_domain_dkim_key` (
  `dkim_key_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_domain_id` BIGINT UNSIGNED NOT NULL COMMENT '所属域',
  `dkim_selector` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '选择器',
  `dkim_key_path` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '私钥文件路径，位于密钥目录',
  `dkim_public_record` TEXT NOT NULL COMMENT '公钥 TXT 记录值',
  `active_flag` TINYINT NOT NULL DEFAULT 1 COMMENT '是否当前用于签名：0否 1是',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`dkim_key_id`),
  UNIQUE KEY `uk_mail_dkim_selector` (`mail_domain_id`, `dkim_selector`),
  CHECK (`active_flag` IN (0,1)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='DKIM 密钥';

-- ============ 2. 账号 ============

-- 邮箱账号；与 IAM 用户一一对应。
-- 状态只有正常、停用、待删除三种。“已删除”不是存储状态：彻底删除时本行和它的从属数据一并物理删除，
-- 此后该用户可以重新开通，原地址可以重新分配。最近登录两列由控制面在登录日志入库后回写。
CREATE TABLE `mail_account` (
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM 用户主键',
  `mail_domain_id` BIGINT UNSIGNED NOT NULL COMMENT '主地址所在域',
  `account_local` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '主地址的账号名，小写',
  `mail_address` VARCHAR(320) COLLATE utf8mb4_bin NOT NULL COMMENT '主地址，小写',
  `account_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=正常；2=停用；3=待删除',
  `admin_suspended_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '管理员单独停用：0否 1是',
  `iam_status` TINYINT NOT NULL DEFAULT 1 COMMENT '最近一次对账得到的 IAM 状态：1=正常；2=停用；3=注销',
  `password_hash` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '邮箱密码哈希，Dovecot 可验证的格式；自动开通且未设密码时，保存一段不可猜测随机串的哈希',
  `password_expire_time` DATETIME NULL COMMENT '临时密码过期时间；NULL=不过期',
  `password_changed_time` DATETIME NULL COMMENT '最近一次修改密码时间，UTC',
  `address_changed_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '用户是否已用掉一次修改主地址的机会：0否 1是',
  `outbound_perm` TINYINT NOT NULL DEFAULT 1 COMMENT '外发权限：1允许；0禁止',
  `quota_bytes` BIGINT NOT NULL COMMENT '容量配额，字节',
  `quota_warn_time` DATETIME NULL COMMENT '最近一次发送容量预警的时间，UTC；同一邮箱 7 天内只提醒一次',
  `last_login_time` DATETIME NULL COMMENT '最近一次标准客户端登录成功的时间，UTC；由登录日志采集回写，不含控制面的访问',
  `last_login_ip` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '最近一次标准客户端登录成功的客户端地址',
  `purge_time` DATETIME NULL COMMENT '待删除邮箱的彻底清除时间；NULL=不在待删除',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`mail_account_id`),
  UNIQUE KEY `uk_mail_account_user` (`user_id`),
  UNIQUE KEY `uk_mail_account_address` (`mail_address`),
  KEY `idx_mail_account_domain` (`mail_domain_id`, `account_status`),
  KEY `idx_mail_account_status` (`account_status`),
  KEY `idx_mail_account_purge` (`account_status`, `purge_time`),
  KEY `idx_mail_account_login` (`last_login_time`),
  CHECK (`account_status` IN (1,2,3)),
  CHECK (`iam_status` IN (1,2,3)),
  CHECK (`admin_suspended_flag` IN (0,1)),
  CHECK (`address_changed_flag` IN (0,1)),
  CHECK (`outbound_perm` IN (0,1)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='邮箱账号';

-- 邮箱密码历史，用于校验不与最近几次重复；每个邮箱只保留最近 3 行，多的删除
CREATE TABLE `mail_account_password_history` (
  `password_history_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属邮箱',
  `password_hash` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '历史密码哈希',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '写入时间，UTC',
  PRIMARY KEY (`password_history_id`),
  KEY `idx_mail_pwd_history_account` (`mail_account_id`, `create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='邮箱密码历史';

-- 别名；来信投到目标邮箱，也可作为发件地址
CREATE TABLE `mail_alias` (
  `mail_alias_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '目标邮箱',
  `alias_address` VARCHAR(320) COLLATE utf8mb4_bin NOT NULL COMMENT '别名地址，小写',
  `alias_source` TINYINT NOT NULL DEFAULT 1 COMMENT '来源：1=管理员；2=用户自助；3=修改主地址后保留',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`mail_alias_id`),
  UNIQUE KEY `uk_mail_alias_address` (`alias_address`),
  KEY `idx_mail_alias_account` (`mail_account_id`),
  CHECK (`alias_source` IN (1,2,3)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='邮箱别名';

-- 每个域的保留地址（postmaster、abuse）指向
CREATE TABLE `mail_system_alias` (
  `system_alias_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_domain_id` BIGINT UNSIGNED NOT NULL COMMENT '所属域',
  `alias_local` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '保留账号名：postmaster、abuse',
  `target_address` VARCHAR(320) COLLATE utf8mb4_bin NOT NULL COMMENT '指向的邮箱地址',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`system_alias_id`),
  UNIQUE KEY `uk_mail_system_alias` (`mail_domain_id`, `alias_local`),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='域保留地址';

-- 转发；每个邮箱最多一条
CREATE TABLE `mail_forward` (
  `mail_forward_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属邮箱',
  `forward_address` VARCHAR(320) COLLATE utf8mb4_bin NOT NULL COMMENT '转发目标地址，小写',
  `keep_copy_flag` TINYINT NOT NULL DEFAULT 1 COMMENT '是否在本邮箱保留副本：0否 1是',
  `enable_flag` TINYINT NOT NULL DEFAULT 1 COMMENT '是否启用：0否 1是',
  `verify_status` TINYINT NOT NULL DEFAULT 1 COMMENT '目标地址验证：1=待验证；2=已验证',
  `verify_token_hash` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '确认令牌的哈希；验证后清空',
  `verify_expire_time` DATETIME NULL COMMENT '确认链接过期时间，UTC',
  `forward_source` TINYINT NOT NULL DEFAULT 1 COMMENT '来源：1=用户自助；2=管理员设置（免验证）',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`mail_forward_id`),
  UNIQUE KEY `uk_mail_forward_account` (`mail_account_id`),
  CHECK (`keep_copy_flag` IN (0,1)),
  CHECK (`enable_flag` IN (0,1)),
  CHECK (`verify_status` IN (1,2)),
  CHECK (`forward_source` IN (1,2)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='邮箱转发';

-- 自动回复；每个邮箱最多一条
CREATE TABLE `mail_autoreply` (
  `autoreply_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属邮箱',
  `enable_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '是否启用：0否 1是',
  `start_time` DATETIME NULL COMMENT '开始时间，UTC；NULL=立即',
  `end_time` DATETIME NULL COMMENT '结束时间，UTC；NULL=不自动结束',
  `reply_subject` VARCHAR(256) NOT NULL COMMENT '自动回复主题',
  `reply_body` TEXT NOT NULL COMMENT '自动回复正文，纯文本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`autoreply_id`),
  UNIQUE KEY `uk_mail_autoreply_account` (`mail_account_id`),
  CHECK (`enable_flag` IN (0,1)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='自动回复';

-- 服务端过滤规则；condition_json 与 action_json 的结构由服务端校验
CREATE TABLE `mail_filter_rule` (
  `filter_rule_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属邮箱',
  `rule_order` INT NOT NULL COMMENT '执行顺序，小的在前',
  `rule_name` VARCHAR(64) NOT NULL COMMENT '规则名称',
  `enable_flag` TINYINT NOT NULL DEFAULT 1 COMMENT '是否启用：0否 1是',
  `condition_json` TEXT NOT NULL COMMENT '条件数组；服务端校验字段与取值',
  `action_json` TEXT NOT NULL COMMENT '动作对象；服务端校验字段与取值',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`filter_rule_id`),
  KEY `idx_mail_filter_account` (`mail_account_id`, `rule_order`),
  CHECK (`enable_flag` IN (0,1)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='服务端过滤规则';

-- 按账号的出站限额覆盖值；没有记录的账号用全局默认值
CREATE TABLE `mail_outbound_rule` (
  `outbound_rule_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属邮箱',
  `hourly_recipient_limit` INT NOT NULL COMMENT '每小时收件人数上限',
  `daily_recipient_limit` INT NOT NULL COMMENT '每天收件人数上限',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`outbound_rule_id`),
  UNIQUE KEY `uk_mail_outbound_account` (`mail_account_id`),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='出站限额覆盖';

-- 黑白名单；地址和域两类
CREATE TABLE `mail_blocklist` (
  `blocklist_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `list_type` TINYINT NOT NULL COMMENT '1=黑名单；2=白名单',
  `block_type` TINYINT NOT NULL COMMENT '1=发件人地址；2=发件域',
  `block_value` VARCHAR(253) COLLATE utf8mb4_bin NOT NULL COMMENT '地址或域名，小写',
  `block_remark` VARCHAR(255) NULL COMMENT '备注',
  `creator_admin_id` BIGINT UNSIGNED NOT NULL COMMENT '添加人的管理员用户主键',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`blocklist_id`),
  UNIQUE KEY `uk_mail_blocklist_value` (`list_type`, `block_type`, `block_value`),
  CHECK (`list_type` IN (1,2)),
  CHECK (`block_type` IN (1,2)),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='黑白名单';

-- 全局设置；服务端按键名和类型校验取值
CREATE TABLE `mail_setting` (
  `setting_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `setting_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '设置键',
  `setting_value` TEXT NOT NULL COMMENT '设置值，按类型序列化',
  `update_admin_id` BIGINT UNSIGNED NULL COMMENT '最近修改的管理员用户主键；初始化时为空',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '平台约定列；本库不使用软删，取值恒为 0',
  PRIMARY KEY (`setting_id`),
  UNIQUE KEY `uk_mail_setting_key` (`setting_key`),
  CHECK (`deleted_flag` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='全局设置';

-- ============ 3. 过程、日志、临时 ============

-- 发送前的附件暂存。过期后物理清理
CREATE TABLE `mail_attachment_temp` (
  `attachment_temp_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID；接口返回的附件标识由它生成',
  `owner_user_id` BIGINT UNSIGNED NOT NULL COMMENT '上传人',
  `file_name` VARCHAR(255) NOT NULL COMMENT '原文件名',
  `mime_type` VARCHAR(128) NOT NULL COMMENT '类型',
  `file_size` BIGINT NOT NULL COMMENT '字节数',
  `storage_path` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '控制面数据目录内的相对路径',
  `expire_time` DATETIME NOT NULL COMMENT '过期时间，UTC',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '上传时间，UTC',
  PRIMARY KEY (`attachment_temp_id`),
  KEY `idx_mail_att_temp_owner` (`owner_user_id`),
  KEY `idx_mail_att_temp_expire` (`expire_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='附件暂存';

-- 经 HTTP 接口移入已删除的邮件的原文件夹，供恢复使用。保留 30 天后物理清理
CREATE TABLE `mail_trash_origin` (
  `trash_origin_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `mail_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属邮箱',
  `folder_name` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '当前所在文件夹（已删除），API 使用的 UTF-8 名称',
  `uid_validity` BIGINT UNSIGNED NOT NULL COMMENT '文件夹有效性标识',
  `message_uid` BIGINT UNSIGNED NOT NULL COMMENT '邮件在文件夹内的唯一编号',
  `origin_folder` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '删除前所在文件夹',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '移入时间，UTC',
  PRIMARY KEY (`trash_origin_id`),
  UNIQUE KEY `uk_mail_trash_origin_msg` (`mail_account_id`, `folder_name`, `uid_validity`, `message_uid`),
  KEY `idx_mail_trash_origin_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='已删除邮件的原文件夹';

-- 成员接口写操作的幂等记录。过期后物理清理
CREATE TABLE `mail_idempotency` (
  `idempotency_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `owner_user_id` BIGINT UNSIGNED NOT NULL COMMENT '发起人',
  `idempotency_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '客户端提供的幂等键',
  `request_hash` CHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '请求内容的 SHA-256 十六进制',
  `response_body` MEDIUMTEXT NOT NULL COMMENT '第一次处理成功时的响应 JSON',
  `expire_time` DATETIME NOT NULL COMMENT '过期时间，UTC',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  PRIMARY KEY (`idempotency_id`),
  UNIQUE KEY `uk_mail_idempotency` (`owner_user_id`, `idempotency_key`),
  KEY `idx_mail_idempotency_expire` (`expire_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='成员接口幂等记录';

-- 投递日志；由采集器从 Postfix 日志生成。保留 180 天后物理清理
CREATE TABLE `mail_delivery_log` (
  `delivery_log_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `log_time` DATETIME NOT NULL COMMENT '日志时间，UTC',
  `mail_direction` TINYINT NOT NULL COMMENT '1=入站；2=出站',
  `queue_id` VARCHAR(32) COLLATE utf8mb4_bin NULL COMMENT 'Postfix 队列标识',
  `message_id` VARCHAR(255) COLLATE utf8mb4_bin NULL COMMENT '邮件追踪号',
  `sender_address` VARCHAR(320) COLLATE utf8mb4_bin NULL COMMENT '发件人',
  `recipient_address` VARCHAR(320) COLLATE utf8mb4_bin NULL COMMENT '收件人',
  `message_size` BIGINT NULL COMMENT '字节数',
  `delivery_status` TINYINT NOT NULL COMMENT '1=已投递；2=重试中；3=已退信；4=被拒收；5=因垃圾或病毒被拒收',
  `dsn_code` VARCHAR(32) NULL COMMENT '投递状态码，如 2.0.0、5.1.1',
  `bounce_reason` VARCHAR(512) NULL COMMENT '退信或拒收原因',
  `delay_ms` INT NULL COMMENT '从进入到处理的耗时，毫秒',
  `tls_flag` TINYINT NULL COMMENT '是否加密传输：0否 1是',
  `auth_account` VARCHAR(320) COLLATE utf8mb4_bin NULL COMMENT '出站时提交用的认证账号',
  `client_ip` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '客户端地址',
  `log_line_hash` CHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT '来源日志行的摘要，用于去重',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '入库时间，UTC',
  PRIMARY KEY (`delivery_log_id`),
  UNIQUE KEY `uk_mail_delivery_log_line` (`log_line_hash`),
  KEY `idx_mail_delivery_time` (`log_time`),
  KEY `idx_mail_delivery_rcpt` (`recipient_address`, `log_time`),
  KEY `idx_mail_delivery_sender` (`sender_address`, `log_time`),
  KEY `idx_mail_delivery_msgid` (`message_id`),
  CHECK (`mail_direction` IN (1,2)),
  CHECK (`delivery_status` IN (1,2,3,4,5))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='投递日志';

-- 登录日志；由采集器从 Dovecot 日志生成。保留 180 天后物理清理
CREATE TABLE `mail_auth_log` (
  `auth_log_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `log_time` DATETIME NOT NULL COMMENT '日志时间，UTC',
  `mail_address` VARCHAR(320) COLLATE utf8mb4_bin NULL COMMENT '登录用的邮箱地址',
  `protocol_type` TINYINT NOT NULL COMMENT '1=IMAP；2=POP3；3=SMTP 提交',
  `client_ip` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '客户端地址',
  `auth_result` TINYINT NOT NULL COMMENT '1=成功；2=失败',
  `fail_reason` VARCHAR(255) NULL COMMENT '失败原因',
  `log_line_hash` CHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT '来源日志行的摘要，用于去重',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '入库时间，UTC',
  PRIMARY KEY (`auth_log_id`),
  UNIQUE KEY `uk_mail_auth_log_line` (`log_line_hash`),
  KEY `idx_mail_auth_time` (`log_time`),
  KEY `idx_mail_auth_address` (`mail_address`, `log_time`),
  KEY `idx_mail_auth_ip` (`client_ip`, `log_time`),
  CHECK (`protocol_type` IN (1,2,3)),
  CHECK (`auth_result` IN (1,2))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='登录日志';

-- 垃圾评分记录；由采集器从 Rspamd 历史记录生成。保留 30 天后物理清理
CREATE TABLE `mail_filter_log` (
  `filter_log_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `log_time` DATETIME NOT NULL COMMENT '评分时间，UTC',
  `message_id` VARCHAR(255) COLLATE utf8mb4_bin NULL COMMENT '邮件追踪号',
  `sender_address` VARCHAR(320) COLLATE utf8mb4_bin NULL COMMENT '发件人',
  `rcpt_addresses` TEXT NULL COMMENT '收件人，逗号分隔',
  `spam_score` DECIMAL(6,2) NOT NULL COMMENT '评分',
  `spam_action` TINYINT NOT NULL COMMENT '1=正常投递；2=进垃圾邮件；3=拒收；4=灰名单',
  `hit_symbols` TEXT NULL COMMENT '命中的主要规则及其分值',
  `history_uniq` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT 'Rspamd 历史记录的标识，用于去重',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '入库时间，UTC',
  PRIMARY KEY (`filter_log_id`),
  UNIQUE KEY `uk_mail_filter_uniq` (`history_uniq`),
  KEY `idx_mail_filter_time` (`log_time`),
  KEY `idx_mail_filter_sender` (`sender_address`, `log_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='垃圾评分记录';

-- 管理操作审计，也记用户自助的写操作（修改主地址、别名、转发）；只追加不修改，保留 365 天后物理清理
CREATE TABLE `mail_admin_audit_log` (
  `admin_audit_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `admin_user_id` BIGINT UNSIGNED NOT NULL COMMENT '操作者的用户主键：管理员操作记管理员用户，用户自助操作记该用户',
  `actor_type` TINYINT NOT NULL DEFAULT 1 COMMENT '1=管理员操作；2=用户自助操作',
  `action_code` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '动作码，如 mailbox.reset_password',
  `target_type` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT '对象类型',
  `target_id` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '对象主键',
  `target_label` VARCHAR(255) NULL COMMENT '对象的展示名称',
  `before_json` TEXT NULL COMMENT '变更前的值',
  `after_json` TEXT NULL COMMENT '变更后的值',
  `client_ip` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '客户端地址',
  `result_flag` TINYINT NOT NULL COMMENT '1=成功；2=失败',
  `fail_reason` VARCHAR(255) NULL COMMENT '失败原因',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间，UTC',
  PRIMARY KEY (`admin_audit_id`),
  KEY `idx_mail_audit_time` (`create_time`),
  KEY `idx_mail_audit_admin` (`admin_user_id`, `create_time`),
  KEY `idx_mail_audit_action` (`action_code`, `create_time`),
  KEY `idx_mail_audit_target` (`target_type`, `target_id`),
  CHECK (`actor_type` IN (1,2))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='管理操作审计';

-- 账号对账的每次执行记录；保留 90 天
CREATE TABLE `mail_sync_run` (
  `sync_run_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `trigger_type` TINYINT NOT NULL COMMENT '1=定时；2=手动',
  `start_time` DATETIME NOT NULL COMMENT '开始时间，UTC',
  `end_time` DATETIME NULL COMMENT '结束时间，UTC；运行中为空',
  `scanned_count` INT NOT NULL DEFAULT 0 COMMENT '比对的账号数',
  `created_count` INT NOT NULL DEFAULT 0 COMMENT '新开通数',
  `updated_count` INT NOT NULL DEFAULT 0 COMMENT '状态更新数',
  `failed_count` INT NOT NULL DEFAULT 0 COMMENT '处理失败数',
  `error_message` TEXT NULL COMMENT '整体失败原因',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  PRIMARY KEY (`sync_run_id`),
  KEY `idx_mail_sync_start` (`start_time`),
  CHECK (`trigger_type` IN (1,2))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='账号对账记录';

-- 管理端的批量操作任务；在后台执行，页面轮询进度。保留 30 天
CREATE TABLE `mail_admin_batch` (
  `admin_batch_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花ID',
  `batch_action` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '动作码，与审计动作码相同，如 account.suspend',
  `batch_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=运行中；2=全部成功；3=部分失败；4=全部失败；5=中断',
  `request_admin_id` BIGINT UNSIGNED NOT NULL COMMENT '发起的管理员用户主键',
  `request_json` MEDIUMTEXT NOT NULL COMMENT '请求参数和对象清单；不含密码',
  `total_count` INT NOT NULL DEFAULT 0 COMMENT '对象总数',
  `done_count` INT NOT NULL DEFAULT 0 COMMENT '已处理数',
  `success_count` INT NOT NULL DEFAULT 0 COMMENT '成功数',
  `failed_count` INT NOT NULL DEFAULT 0 COMMENT '失败数',
  `result_json` MEDIUMTEXT NULL COMMENT '失败明细数组，元素为 {targetId, targetLabel, code, message}',
  `start_time` DATETIME NULL COMMENT '开始时间，UTC',
  `end_time` DATETIME NULL COMMENT '结束时间，UTC；未结束为空',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  PRIMARY KEY (`admin_batch_id`),
  KEY `idx_mail_admin_batch_time` (`create_time`),
  KEY `idx_mail_admin_batch_request` (`request_admin_id`, `create_time`),
  CHECK (`batch_status` IN (1,2,3,4,5))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='管理端批量操作任务';

-- 日志采集的断点；每个采集源一行，采集器不断更新
CREATE TABLE `mail_collector_checkpoint` (
  `checkpoint_source` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT '采集源：postfix、dovecot、rspamd_history',
  `file_identity` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '文件标识：文件首行的摘要；轮转或重建后变化。非文件源为空',
  `file_offset` BIGINT NOT NULL DEFAULT 0 COMMENT '文件源已读到的字节偏移',
  `last_line_hash` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '偏移处上一行的摘要，用来确认位置没变',
  `cursor_value` VARCHAR(255) COLLATE utf8mb4_bin NULL COMMENT '非文件源的游标，如 Rspamd 历史记录里最后一条的时间',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  PRIMARY KEY (`checkpoint_source`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='日志采集断点';

-- ============ 4. Dovecot 维护的表与只读视图 ============

-- 容量用量；由 Dovecot 配额插件读写，控制面只读。Dovecot 用单独的字典账号连库，只有本表的读写权限
CREATE TABLE `mail_quota_dict` (
  `quota_username` VARCHAR(320) COLLATE utf8mb4_bin NOT NULL COMMENT '邮箱地址',
  `quota_bytes` BIGINT NOT NULL DEFAULT 0 COMMENT '已用字节',
  `quota_messages` INT NOT NULL DEFAULT 0 COMMENT '邮件数',
  PRIMARY KEY (`quota_username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='容量用量（Dovecot 维护）';

-- Postfix：由本系统接收的域
CREATE OR REPLACE VIEW `v_mail_domain` AS
SELECT d.`domain_name` AS `domain`
FROM `mail_domain` d
WHERE d.`deleted_flag` = 0 AND d.`domain_status` = 1;

-- Postfix：状态正常的邮箱地址
CREATE OR REPLACE VIEW `v_mailbox` AS
SELECT a.`mail_address` AS `address`
FROM `mail_account` a
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
WHERE a.`deleted_flag` = 0 AND a.`account_status` = 1
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1;

-- Postfix：停用和待删除的邮箱，收信时拒绝并提示
CREATE OR REPLACE VIEW `v_mail_recipient_policy` AS
SELECT a.`mail_address` AS `address`, 'REJECT Mailbox disabled' AS `action`
FROM `mail_account` a
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
WHERE a.`deleted_flag` = 0 AND a.`account_status` IN (2, 3)
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1;

-- Postfix：别名、域保留地址、已验证的转发，解析成目标地址。
-- 目标邮箱所在域、别名自己所在的域，任一停用都不解析
CREATE OR REPLACE VIEW `v_mail_alias` AS
SELECT al.`alias_address` AS `address`, a.`mail_address` AS `goto`
FROM `mail_alias` al
JOIN `mail_account` a ON a.`mail_account_id` = al.`mail_account_id`
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
JOIN `mail_domain` ad ON ad.`domain_name` = SUBSTRING_INDEX(al.`alias_address`, '@', -1)
WHERE al.`deleted_flag` = 0 AND a.`deleted_flag` = 0 AND a.`account_status` = 1
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1
  AND ad.`deleted_flag` = 0 AND ad.`domain_status` = 1
UNION ALL
SELECT CONCAT(sa.`alias_local`, '@', d.`domain_name`) AS `address`, sa.`target_address` AS `goto`
FROM `mail_system_alias` sa
JOIN `mail_domain` d ON d.`mail_domain_id` = sa.`mail_domain_id`
WHERE sa.`deleted_flag` = 0 AND d.`deleted_flag` = 0 AND d.`domain_status` = 1
UNION ALL
SELECT a.`mail_address` AS `address`,
       CASE WHEN f.`keep_copy_flag` = 1 THEN CONCAT(a.`mail_address`, ',', f.`forward_address`) ELSE f.`forward_address` END AS `goto`
FROM `mail_forward` f
JOIN `mail_account` a ON a.`mail_account_id` = f.`mail_account_id`
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
WHERE f.`deleted_flag` = 0 AND f.`enable_flag` = 1 AND f.`verify_status` = 2
  AND a.`deleted_flag` = 0 AND a.`account_status` = 1
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1;

-- Postfix：登录账号允许使用的发件地址。别名所在域停用时，这个别名不能再作发件地址
CREATE OR REPLACE VIEW `v_mail_sender` AS
SELECT a.`mail_address` AS `login_name`, a.`mail_address` AS `address`
FROM `mail_account` a
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
WHERE a.`deleted_flag` = 0 AND a.`account_status` = 1
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1
UNION ALL
SELECT a.`mail_address` AS `login_name`, al.`alias_address` AS `address`
FROM `mail_alias` al
JOIN `mail_account` a ON a.`mail_account_id` = al.`mail_account_id`
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
JOIN `mail_domain` ad ON ad.`domain_name` = SUBSTRING_INDEX(al.`alias_address`, '@', -1)
WHERE al.`deleted_flag` = 0 AND a.`deleted_flag` = 0 AND a.`account_status` = 1
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1
  AND ad.`deleted_flag` = 0 AND ad.`domain_status` = 1;

-- Postfix：黑名单。白名单不在这里，由控制面渲染成 Rspamd 的映射文件
CREATE OR REPLACE VIEW `v_mail_blocklist` AS
SELECT b.`block_value` AS `address`, 'REJECT Sender blocked' AS `action`
FROM `mail_blocklist` b
WHERE b.`deleted_flag` = 0 AND b.`list_type` = 1;

-- Dovecot：用户信息
CREATE OR REPLACE VIEW `v_mail_dovecot_user` AS
SELECT a.`mail_address` AS `userid`,
       5000 AS `uid`,
       5000 AS `gid`,
       CONCAT('/var/vmail/', d.`domain_name`, '/', a.`account_local`) AS `home`,
       'maildir:~/Maildir' AS `mail`,
       CONCAT('*:bytes=', a.`quota_bytes`) AS `quota_rule`
FROM `mail_account` a
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
WHERE a.`deleted_flag` = 0 AND a.`account_status` = 1
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1;

-- Dovecot：密码哈希；临时密码过期后不再出现
CREATE OR REPLACE VIEW `v_mail_dovecot_passwd` AS
SELECT a.`mail_address` AS `userid`, a.`password_hash` AS `password`
FROM `mail_account` a
JOIN `mail_domain` d ON d.`mail_domain_id` = a.`mail_domain_id`
WHERE a.`deleted_flag` = 0 AND a.`account_status` = 1
  AND d.`deleted_flag` = 0 AND d.`domain_status` = 1
  AND (a.`password_expire_time` IS NULL OR a.`password_expire_time` > UTC_TIMESTAMP());

-- ============ 5. 数据库账号（不在本文件创建，这里只列权限） ============
-- mail_ctrl    控制面：本库全部表和视图的 SELECT、INSERT、UPDATE、DELETE； Dovecot 维护的容量用量表只给 SELECT
-- mail_reader  Postfix 与 Dovecot：只给 8 个视图的 SELECT，来源限制为邮件节点私有网段
-- mail_dict    Dovecot 配额插件：只给容量用量表的 SELECT、INSERT、UPDATE、DELETE
-- 三个账号的口令都在部署时生成，经环境变量注入，不写入任何文件
-- 示例（口令占位）：
-- CREATE USER 'mail_reader'@'%' IDENTIFIED BY '<部署时注入>';
-- GRANT SELECT ON ppb_mail.v_mail_domain TO 'mail_reader'@'%';   -- 逐个视图授权
