-- PPB IAM / 平台授权 / 业务用户表设计 v0.4，2026-10-27
-- MySQL 8.0.16+；参考ppb-base deploy/sql和存储建模规范；目标态全新建库，不是升级脚本。
-- 所有列名至少两个单词以_连接；表名兼容既有user；OIDC对外字段保持协议标准。
-- 统一user/认证/公共资料/平台授权归server-iam；聊天组织归server-im；扩展归业务服务。
-- 雪花ID+表专属biz_key；关联存ID；create_time/update_time/deleted_flag/deleted_time。
-- InnoDB + utf8mb4_unicode_ci；精确身份/code/subject列使用utf8mb4_bin。
-- 逻辑外键，由应用验证引用/同域/状态和并发；不跨库JOIN，不创建物理FK。
-- 字段化固定资料，个人开关KV；TEXT JSON须服务端校验schema；状态码见COMMENT。
-- 无AUTO_INCREMENT、DROP或默认账号密码。种子小ID为全新环境保留区，导入旧数据需先审查。
-- 范围只覆盖账号认证授权和业务用户；不包含消息/作品/衣物/支付/额度等业务实体。
-- 已完成静态与SQLite兼容结构验证，未做MySQL实例/协议/生产迁移验收。
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
SET time_zone = '+00:00';


CREATE DATABASE IF NOT EXISTS `ppb_iam` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `ppb_iam`;

-- 统一用户主体；平台管理和普通业务共用
CREATE TABLE `user` (
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `user_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；3=deleted；全局状态',
  `security_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '全局撤权版本',
  `disabled_at` DATETIME NULL COMMENT '全局停用时间',
  `last_login_at` DATETIME NULL COMMENT '最近认证成功时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `uk_biz_key` (`user_biz_key`),
  KEY `idx_status` (`user_status`),
  CHECK (`user_status` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='统一用户主体；平台管理和普通业务共用';


-- 公共资料；业务覆盖资料放业务库
CREATE TABLE `user_profile` (
  `user_profile_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `user_profile_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '全局用户',
  `user_nickname` VARCHAR(128) NOT NULL COMMENT '公共昵称',
  `avatar_file_key` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '头像文件业务键',
  `language_code` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL DEFAULT 'zh-CN' COMMENT '语言',
  `time_zone` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL DEFAULT 'Asia/Shanghai' COMMENT '时区',
  `profile_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '资料事件版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`user_profile_id`),
  UNIQUE KEY `uk_biz_key` (`user_profile_biz_key`),
  UNIQUE KEY `uk_user_id` (`user_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='公共资料；业务覆盖资料放业务库';


-- 登录标识；规范化值按类型制定，注销后默认保留占用
CREATE TABLE `user_identities` (
  `user_identity_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `user_identity_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '全局用户',
  `identity_type` TINYINT NOT NULL COMMENT '1=username；2=email；3=phone；4=employee_code（namespace=组织域）；标识类型',
  `identity_namespace` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL DEFAULT 'global' COMMENT '登录命名空间',
  `normalized_value` VARCHAR(254) COLLATE utf8mb4_bin NOT NULL COMMENT '服务端规范化登录值，非展示副本',
  `verified_at` DATETIME NULL COMMENT '确权时间',
  `identity_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；3=retired；标识状态',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`user_identity_id`),
  UNIQUE KEY `uk_biz_key` (`user_identity_biz_key`),
  UNIQUE KEY `uk_identity_type_namespace_normalized_value` (`identity_type`,`identity_namespace`,`normalized_value`),
  KEY `idx_user_id` (`user_id`),
  CHECK (`identity_type` IN (1,2,3,4)),
  CHECK (`identity_status` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='登录标识；规范化值按类型制定，注销后默认保留占用';


-- 密码凭证；停用或升级原行，历史在审计记录
CREATE TABLE `user_credentials` (
  `user_credential_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `user_credential_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '全局用户',
  `credential_type` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL DEFAULT 'password' COMMENT '凭证类型',
  `password_hash` VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '不可逆密码哈希，包含算法参数',
  `credential_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '密码版本',
  `password_fail_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '失败次数',
  `lock_until` DATETIME NULL COMMENT '锁定截止时间',
  `changed_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '最近改密',
  `revoked_at` DATETIME NULL COMMENT '凭证吊销时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`user_credential_id`),
  UNIQUE KEY `uk_biz_key` (`user_credential_biz_key`),
  UNIQUE KEY `uk_user_id_credential_type` (`user_id`,`credential_type`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='密码凭证；停用或升级原行，历史在审计记录';


-- 上游第三方身份源；不是下游客户端
CREATE TABLE `identity_providers` (
  `identity_provider_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `identity_provider_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `provider_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '配置唯一键',
  `display_name` VARCHAR(128) NOT NULL COMMENT '显示名称',
  `protocol_type` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT '协议类型',
  `issuer_uri` VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '可信发行者完整地址',
  `client_id` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '上游客户端ID',
  `secret_ref` VARCHAR(255) COLLATE utf8mb4_bin NULL COMMENT '密钥管理系统引用',
  `provider_config` TEXT NULL COMMENT '端点和允许算法等配置；不得含明文密钥',
  `is_enabled` TINYINT NOT NULL DEFAULT 0 COMMENT '是否启用：0否/1是',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`identity_provider_id`),
  UNIQUE KEY `uk_biz_key` (`identity_provider_biz_key`),
  UNIQUE KEY `uk_provider_key` (`provider_key`),
  CHECK (is_enabled IN (0,1)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='上游第三方身份源；不是下游客户端';


-- 上游身份绑定；校验配置的issuer后匹配subject
CREATE TABLE `user_external_identities` (
  `user_external_identity_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `user_external_identity_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '全局用户',
  `identity_provider_id` BIGINT UNSIGNED NOT NULL COMMENT '可信上游配置',
  `provider_subject` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '上游sub/openid，按原值匹配',
  `verified_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '绑定确权时间',
  `retired_at` DATETIME NULL COMMENT '退役时间；唯一身份默认不回收',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`user_external_identity_id`),
  UNIQUE KEY `uk_biz_key` (`user_external_identity_biz_key`),
  UNIQUE KEY `uk_provider_id_subject` (`identity_provider_id`,`provider_subject`),
  KEY `idx_user_id` (`user_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='上游身份绑定；校验配置的issuer后匹配subject';


-- 多因素认证；恢复和重置须独立审计
CREATE TABLE `mfa_factors` (
  `mfa_factor_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `mfa_factor_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '全局用户',
  `factor_type` TINYINT NOT NULL COMMENT '1=totp；2=webauthn；因子类型',
  `factor_label` VARCHAR(128) NOT NULL COMMENT '设备名称',
  `encrypted_secret` VARBINARY(2048) NULL COMMENT 'TOTP信封加密材料，非明文',
  `key_ref` VARCHAR(255) COLLATE utf8mb4_bin NULL COMMENT '解密密钥引用',
  `public_configuration` TEXT NULL COMMENT 'WebAuthn公钥、credentialId和计数等；服务层校验唯一性',
  `verified_at` DATETIME NULL COMMENT '确认启用时间',
  `revoked_at` DATETIME NULL COMMENT '撤销时间',
  `last_used_step` BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'TOTP重放保护水位（最近一次已消费步进）；实现增列',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`mfa_factor_id`),
  UNIQUE KEY `uk_biz_key` (`mfa_factor_biz_key`),
  KEY `idx_user_id` (`user_id`),
  CHECK (`factor_type` IN (1,2)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='多因素认证；恢复和重置须独立审计';


-- MFA恢复码，只存摘要，条件更新单次使用
CREATE TABLE `recovery_codes` (
  `recovery_code_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `recovery_code_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '全局用户',
  `code_digest` BINARY(32) NOT NULL COMMENT '使用服务端密钥HMAC后的摘要',
  `used_at` DATETIME NULL COMMENT '单次消费时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`recovery_code_id`),
  UNIQUE KEY `uk_biz_key` (`recovery_code_biz_key`),
  UNIQUE KEY `uk_code_digest` (`code_digest`),
  KEY `idx_user_id` (`user_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='MFA恢复码，只存摘要，条件更新单次使用';


-- 注册/绑定/找回验证码挑战；短期保留定期清理
CREATE TABLE `verification_challenges` (
  `verification_challenge_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `verification_challenge_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `challenge_purpose` TINYINT NOT NULL COMMENT '1=register；2=login；3=reset_password；4=bind_identity；5=change_identity；用途',
  `delivery_target` VARCHAR(254) COLLATE utf8mb4_bin NOT NULL COMMENT '投递目标，限制访问并按策略清理',
  `code_digest` BINARY(32) NOT NULL COMMENT '短验证码必须使用服务端密钥HMAC，防离线穷举',
  `transaction_digest` BINARY(32) NOT NULL COMMENT '绑定发起事务和设备的高熵标识摘要',
  `attempt_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '已尝试次数',
  `max_attempts` INT UNSIGNED NOT NULL DEFAULT 5 COMMENT '最多尝试次数',
  `expires_at` DATETIME NOT NULL COMMENT '失效时间',
  `consumed_at` DATETIME NULL COMMENT '消费时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`verification_challenge_id`),
  UNIQUE KEY `uk_biz_key` (`verification_challenge_biz_key`),
  UNIQUE KEY `uk_transaction_digest` (`transaction_digest`),
  KEY `idx_expires_at` (`expires_at`),
  CHECK (max_attempts > 0),
  CHECK (`challenge_purpose` IN (1,2,3,4,5)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='注册/绑定/找回验证码挑战；短期保留定期清理';


-- 应用域；不是租户
CREATE TABLE `applications` (
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `application_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `app_key` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT '唯一应用域',
  `application_name` VARCHAR(128) NOT NULL COMMENT '应用名称',
  `application_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；状态',
  `access_policy` TINYINT NOT NULL DEFAULT 2 COMMENT '1=public；2=assigned；公开应用或显式分配',
  `authz_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '应用权限版本，菜单/角色变更递增',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`application_id`),
  UNIQUE KEY `uk_biz_key` (`application_biz_key`),
  UNIQUE KEY `uk_app_key` (`app_key`),
  CHECK (`application_status` IN (1,2)),
  CHECK (`access_policy` IN (1,2)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='应用域；不是租户';


-- 显式用户应用准入；公开应用无需每人插入
CREATE TABLE `application_assignments` (
  `application_assignment_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `application_assignment_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '应用',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户',
  `assignment_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；准入状态',
  `valid_until` DATETIME NULL COMMENT '截止时间',
  `granted_by` BIGINT UNSIGNED NULL COMMENT '授权人用户ID',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`application_assignment_id`),
  UNIQUE KEY `uk_biz_key` (`application_assignment_biz_key`),
  UNIQUE KEY `uk_application_id_user_id` (`application_id`,`user_id`),
  KEY `idx_user_id` (`user_id`),
  CHECK (`assignment_status` IN (1,2)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='显式用户应用准入；公开应用无需每人插入';


-- OIDC下游客户端；密钥由专用表管理
CREATE TABLE `oauth_clients` (
  `oauth_client_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `oauth_client_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '应用',
  `client_id` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '公开唯一客户端标识',
  `client_name` VARCHAR(128) NOT NULL COMMENT '客户端名称',
  `client_type` TINYINT NOT NULL COMMENT '1=public；2=confidential；公开端或机密端',
  `token_auth_method` TINYINT NOT NULL COMMENT '1=none；2=client_secret_basic；3=private_key_jwt；token端点认证方式',
  `subject_sector` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT 'pairwise主体隔离范围；服务层按注册域策略维护',
  `allowed_scopes` VARCHAR(1024) COLLATE utf8mb4_bin NOT NULL DEFAULT 'openid profile' COMMENT '空格分隔允许scope',
  `require_pkce` TINYINT NOT NULL DEFAULT 1 COMMENT '强制S256：0否/1是',
  `is_enabled` TINYINT NOT NULL DEFAULT 1 COMMENT '启用：0否/1是',
  `public_jwks` TEXT NULL COMMENT 'private_key_jwt客户端公钥',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`oauth_client_id`),
  UNIQUE KEY `uk_biz_key` (`oauth_client_biz_key`),
  UNIQUE KEY `uk_client_id` (`client_id`),
  KEY `idx_application_id` (`application_id`),
  CHECK (require_pkce = 1),
  CHECK (is_enabled IN (0,1)),
  CHECK ((client_type = 1 AND token_auth_method = 1) OR (client_type = 2 AND token_auth_method <> 1)),
  CHECK (`client_type` IN (1,2)),
  CHECK (`token_auth_method` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OIDC下游客户端；密钥由专用表管理';


-- 机密客户端密钥可并存轮换；只存可验证摘要
CREATE TABLE `oauth_client_secrets` (
  `oauth_client_secret_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `oauth_client_secret_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `oauth_client_id` BIGINT UNSIGNED NOT NULL COMMENT '客户端',
  `secret_hash` VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '高熵密钥的校验哈希',
  `expires_at` DATETIME NULL COMMENT '密钥到期',
  `revoked_at` DATETIME NULL COMMENT '密钥撤销',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`oauth_client_secret_id`),
  UNIQUE KEY `uk_biz_key` (`oauth_client_secret_biz_key`),
  KEY `idx_oauth_client_id` (`oauth_client_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='机密客户端密钥可并存轮换；只存可验证摘要';


-- 精确回调允许列表；URI解析/规范化规则由协议层执行
CREATE TABLE `oauth_client_redirects` (
  `oauth_client_redirect_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `oauth_client_redirect_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `oauth_client_id` BIGINT UNSIGNED NOT NULL COMMENT '客户端',
  `redirect_kind` TINYINT NOT NULL COMMENT '1=login；2=logout；3=backchannel_logout；回调类型',
  `redirect_uri` VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '精确允许地址',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`oauth_client_redirect_id`),
  UNIQUE KEY `uk_biz_key` (`oauth_client_redirect_biz_key`),
  UNIQUE KEY `uk_oauth_client_id_kind_uri` (`oauth_client_id`,`redirect_kind`,`redirect_uri`),
  CHECK (`redirect_kind` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='精确回调允许列表；URI解析/规范化规则由协议层执行';


-- 内部用户与OIDC pairwise sub映射；内部ID不作为公开sub
CREATE TABLE `subject_mappings` (
  `subject_mapping_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `subject_mapping_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户',
  `sector_key` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '客户端隔离域',
  `subject_value` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '不可预测的对外subject',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`subject_mapping_id`),
  UNIQUE KEY `uk_biz_key` (`subject_mapping_biz_key`),
  UNIQUE KEY `uk_user_id_sector_key` (`user_id`,`sector_key`),
  UNIQUE KEY `uk_subject` (`subject_value`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='内部用户与OIDC pairwise sub映射；内部ID不作为公开sub';


-- IAM会话；cookie使用独立高熵值，数据库只存摘要
CREATE TABLE `auth_sessions` (
  `auth_session_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `auth_session_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户',
  `session_digest` BINARY(32) NOT NULL COMMENT '认证cookie摘要',
  `device_label` VARCHAR(128) NULL COMMENT '终端描述，不能作为认证证据',
  `auth_context_class` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '认证等级',
  `auth_methods` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '空格分隔认证方式',
  `authenticated_at` DATETIME NOT NULL COMMENT '认证时间',
  `last_seen_at` DATETIME NOT NULL COMMENT '最近活动',
  `idle_expires_at` DATETIME NOT NULL COMMENT '空闲截止',
  `expires_at` DATETIME NOT NULL COMMENT '绝对截止',
  `revoked_at` DATETIME NULL COMMENT '撤销时间',
  `revoke_reason` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '撤销原因',
  `security_version` BIGINT UNSIGNED NOT NULL COMMENT '签入时安全版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`auth_session_id`),
  UNIQUE KEY `uk_biz_key` (`auth_session_biz_key`),
  UNIQUE KEY `uk_session_digest` (`session_digest`),
  KEY `idx_user_id_revoked_at` (`user_id`,`revoked_at`),
  KEY `idx_expires_at` (`expires_at`),
  UNIQUE KEY `uk_auth_session_id_user_id` (`auth_session_id`,`user_id`),
  CHECK (expires_at > authenticated_at),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='IAM会话；cookie使用独立高熵值，数据库只存摘要';


-- OIDC授权事务；服务端保存，单次消费并绑定浏览器
CREATE TABLE `login_transactions` (
  `login_transaction_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `login_transaction_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `oauth_client_id` BIGINT UNSIGNED NOT NULL COMMENT '客户端',
  `browser_binding_digest` BINARY(32) NOT NULL COMMENT '浏览器绑定摘要',
  `redirect_uri` VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '已注册的精确回调地址',
  `client_state` VARCHAR(1024) COLLATE utf8mb4_bin NOT NULL COMMENT '下游state原值，短期保留并原样返回',
  `oidc_nonce` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '下游nonce',
  `pkce_challenge` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT 'S256 challenge',
  `requested_scopes` VARCHAR(1024) COLLATE utf8mb4_bin NOT NULL COMMENT '请求scope',
  `response_mode` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL DEFAULT 'query' COMMENT '响应方式',
  `expires_at` DATETIME NOT NULL COMMENT '事务截止',
  `consumed_at` DATETIME NULL COMMENT '消费时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`login_transaction_id`),
  UNIQUE KEY `uk_biz_key` (`login_transaction_biz_key`),
  KEY `idx_expires_at` (`expires_at`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OIDC授权事务；服务端保存，单次消费并绑定浏览器';


-- 用户、客户端与登录会话的授权关系
CREATE TABLE `oauth_grants` (
  `oauth_grant_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `oauth_grant_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户',
  `oauth_client_id` BIGINT UNSIGNED NOT NULL COMMENT '客户端',
  `auth_session_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM会话',
  `granted_scopes` VARCHAR(1024) COLLATE utf8mb4_bin NOT NULL COMMENT '已授权scope',
  `token_audience` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT '令牌受众',
  `expires_at` DATETIME NOT NULL COMMENT '授权截止',
  `revoked_at` DATETIME NULL COMMENT '撤销时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`oauth_grant_id`),
  UNIQUE KEY `uk_biz_key` (`oauth_grant_biz_key`),
  KEY `idx_user_id_oauth_client_id` (`user_id`,`oauth_client_id`),
  KEY `idx_auth_session_id` (`auth_session_id`),
  UNIQUE KEY `uk_grant_id_oauth_client_id` (`oauth_grant_id`,`oauth_client_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户、客户端与登录会话的授权关系';


-- 授权码原文仅返回一次，摘要匹配，原子消费
CREATE TABLE `authorization_codes` (
  `authorization_code_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `authorization_code_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `code_digest` BINARY(32) NOT NULL COMMENT '高熵授权码摘要',
  `oauth_grant_id` BIGINT UNSIGNED NOT NULL COMMENT '授权',
  `oauth_client_id` BIGINT UNSIGNED NOT NULL COMMENT '客户端',
  `redirect_uri` VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '授权时回调',
  `pkce_challenge` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT 'S256 challenge',
  `oidc_nonce` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT 'ID token绑定nonce',
  `expires_at` DATETIME NOT NULL COMMENT '失效时间',
  `consumed_at` DATETIME NULL COMMENT '消费时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`authorization_code_id`),
  UNIQUE KEY `uk_biz_key` (`authorization_code_biz_key`),
  UNIQUE KEY `uk_code_digest` (`code_digest`),
  KEY `idx_expires_at` (`expires_at`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='授权码原文仅返回一次，摘要匹配，原子消费';


-- 刷新凭证族；重放时全族撤销
CREATE TABLE `refresh_token_families` (
  `refresh_token_family_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `refresh_token_family_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `oauth_grant_id` BIGINT UNSIGNED NOT NULL COMMENT '授权',
  `expires_at` DATETIME NOT NULL COMMENT '族最长寿命',
  `revoked_at` DATETIME NULL COMMENT '全族撤销时间',
  `revoke_reason` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '原因',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`refresh_token_family_id`),
  UNIQUE KEY `uk_biz_key` (`refresh_token_family_biz_key`),
  KEY `idx_grant_id` (`oauth_grant_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='刷新凭证族；重放时全族撤销';


-- 刷新轮换链；旧凭证消费后保留供重放检测
CREATE TABLE `refresh_tokens` (
  `refresh_token_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `refresh_token_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `refresh_token_family_id` BIGINT UNSIGNED NOT NULL COMMENT '凭证族',
  `token_digest` BINARY(32) NOT NULL COMMENT '刷新凭证摘要',
  `parent_token_id` BIGINT UNSIGNED NULL COMMENT '前驱凭证',
  `expires_at` DATETIME NOT NULL COMMENT '到期',
  `consumed_at` DATETIME NULL COMMENT '轮换消费时间',
  `revoked_at` DATETIME NULL COMMENT '撤销时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`refresh_token_id`),
  UNIQUE KEY `uk_biz_key` (`refresh_token_biz_key`),
  UNIQUE KEY `uk_token_digest` (`token_digest`),
  UNIQUE KEY `uk_parent_token_id` (`parent_token_id`),
  KEY `idx_family_id` (`refresh_token_family_id`),
  UNIQUE KEY `uk_refresh_token_id_family_id` (`refresh_token_id`,`refresh_token_family_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='刷新轮换链；旧凭证消费后保留供重放检测';


-- 签名密钥元数据，私钥不入库
CREATE TABLE `signing_keys` (
  `signing_key_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `signing_key_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `key_identifier` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '唯一key id',
  `sign_algorithm` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT '允许算法',
  `public_jwk` TEXT NOT NULL COMMENT '公开JWK',
  `private_key_ref` VARCHAR(255) COLLATE utf8mb4_bin NOT NULL COMMENT 'KMS或密钥系统引用',
  `key_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=pending；2=active；3=verify_only；4=revoked；生命周期',
  `not_before` DATETIME NOT NULL COMMENT '启用时间',
  `verify_until` DATETIME NULL COMMENT '验签保留截止',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`signing_key_id`),
  UNIQUE KEY `uk_biz_key` (`signing_key_biz_key`),
  UNIQUE KEY `uk_kid` (`key_identifier`),
  CHECK (`key_status` IN (1,2,3,4)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='签名密钥元数据，私钥不入库';


-- 管理资格；与密码及普通用户状态分离
CREATE TABLE `platform_admins` (
  `platform_admin_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_admin_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '统一用户',
  `admin_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；资格状态',
  `is_super` TINYINT NOT NULL DEFAULT 0 COMMENT '平台治理超管：0否/1是',
  `valid_until` DATETIME NULL COMMENT '资格截止',
  `authz_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '个人授权版本',
  `granted_by` BIGINT UNSIGNED NULL COMMENT '授予人管理员ID',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_admin_id`),
  UNIQUE KEY `uk_biz_key` (`platform_admin_biz_key`),
  UNIQUE KEY `uk_user_id` (`user_id`),
  UNIQUE KEY `uk_admin_id_user_id` (`platform_admin_id`,`user_id`),
  CHECK (is_super IN (0,1)),
  CHECK (`admin_status` IN (1,2)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='管理资格；与密码及普通用户状态分离';


-- 单应用域平台角色；与聊天组织角色分离
CREATE TABLE `platform_roles` (
  `platform_role_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_role_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '应用域',
  `role_code` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '角色码',
  `role_name` VARCHAR(128) NOT NULL COMMENT '名称',
  `role_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；状态',
  `is_builtin` TINYINT NOT NULL DEFAULT 0 COMMENT '内置角色：0否/1是',
  `role_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '角色版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_role_id`),
  UNIQUE KEY `uk_biz_key` (`platform_role_biz_key`),
  UNIQUE KEY `uk_application_id_code` (`application_id`,`role_code`),
  UNIQUE KEY `uk_role_id_application_id` (`platform_role_id`,`application_id`),
  CHECK (is_builtin IN (0,1)),
  CHECK (`role_status` IN (1,2)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='单应用域平台角色；与聊天组织角色分离';


-- 后端操作权限目录；服务端按应用和code校验
CREATE TABLE `platform_permissions` (
  `platform_permission_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_permission_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '应用域',
  `permission_code` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '权限码，如template.read',
  `permission_name` VARCHAR(128) NOT NULL COMMENT '名称',
  `permission_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；状态',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_permission_id`),
  UNIQUE KEY `uk_biz_key` (`platform_permission_biz_key`),
  UNIQUE KEY `uk_application_id_code` (`application_id`,`permission_code`),
  UNIQUE KEY `uk_permission_id_application_id` (`platform_permission_id`,`application_id`),
  CHECK (`permission_status` IN (1,2)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='后端操作权限目录；服务端按应用和code校验';


-- 目录/页面/按钮/隐藏操作，工程注册后后台调整展示
CREATE TABLE `platform_menus` (
  `platform_menu_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_menu_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '所属应用域',
  `surface_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '后台入口，如platform或camera',
  `parent_id` BIGINT UNSIGNED NULL COMMENT '父节点；同入口同应用',
  `menu_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '入口内稳定键',
  `node_type` TINYINT NOT NULL COMMENT '1=directory；2=page；3=button；4=operation；节点类型',
  `menu_name` VARCHAR(128) NOT NULL COMMENT '显示名称',
  `route_key` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '已注册前端路由键；禁止任意脚本',
  `menu_icon` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '允许的图标键',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序',
  `is_hidden` TINYINT NOT NULL DEFAULT 0 COMMENT '隐藏展示，不等于撤权：0否/1是',
  `menu_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=disabled；状态',
  `source_version` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '工程注册清单版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_menu_id`),
  UNIQUE KEY `uk_biz_key` (`platform_menu_biz_key`),
  UNIQUE KEY `uk_application_id_surface_key_menu_key` (`application_id`,`surface_key`,`menu_key`),
  UNIQUE KEY `uk_menu_id_application_id` (`platform_menu_id`,`application_id`),
  UNIQUE KEY `uk_menu_id_application_id_surface_key` (`platform_menu_id`,`application_id`,`surface_key`),
  KEY `idx_application_id_surface_key_parent_id` (`application_id`,`surface_key`,`parent_id`),
  CHECK (is_hidden IN (0,1)),
  CHECK (parent_id IS NULL OR parent_id <> platform_menu_id),
  CHECK (`node_type` IN (1,2,3,4)),
  CHECK (`menu_status` IN (1,2)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='目录/页面/按钮/隐藏操作，工程注册后后台调整展示';


-- 角色直接分配菜单按钮；不再维护role_permissions双权威
CREATE TABLE `platform_role_menus` (
  `platform_role_menu_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_role_menu_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `platform_role_id` BIGINT UNSIGNED NOT NULL COMMENT '角色',
  `platform_menu_id` BIGINT UNSIGNED NOT NULL COMMENT '菜单按钮',
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '共同应用域',
  `granted_by` BIGINT UNSIGNED NULL COMMENT '操作人管理员ID',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_role_menu_id`),
  UNIQUE KEY `uk_biz_key` (`platform_role_menu_biz_key`),
  UNIQUE KEY `uk_role_id_menu_id` (`platform_role_id`,`platform_menu_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='角色直接分配菜单按钮；不再维护role_permissions双权威';


-- 勾选页面或按钮实际授予的后端权限；不是可见条件
CREATE TABLE `platform_menu_permissions` (
  `platform_menu_permission_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_menu_permission_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `platform_menu_id` BIGINT UNSIGNED NOT NULL COMMENT '菜单按钮',
  `platform_permission_id` BIGINT UNSIGNED NOT NULL COMMENT '操作权限',
  `application_id` BIGINT UNSIGNED NOT NULL COMMENT '共同应用域',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_menu_permission_id`),
  UNIQUE KEY `uk_biz_key` (`platform_menu_permission_biz_key`),
  UNIQUE KEY `uk_menu_id_permission_id` (`platform_menu_id`,`platform_permission_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='勾选页面或按钮实际授予的后端权限；不是可见条件';


-- 管理员角色分配；多角色取并集
CREATE TABLE `platform_admin_roles` (
  `platform_admin_role_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_admin_role_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `platform_admin_id` BIGINT UNSIGNED NOT NULL COMMENT '管理员',
  `platform_role_id` BIGINT UNSIGNED NOT NULL COMMENT '角色',
  `valid_until` DATETIME NULL COMMENT '授权截止',
  `granted_by` BIGINT UNSIGNED NULL COMMENT '操作人管理员ID',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_admin_role_id`),
  UNIQUE KEY `uk_biz_key` (`platform_admin_role_biz_key`),
  UNIQUE KEY `uk_admin_id_role_id` (`platform_admin_id`,`platform_role_id`),
  KEY `idx_role_id` (`platform_role_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='管理员角色分配；多角色取并集';


-- 后台业务会话；每设备独立，不能使用is_login字段代替
CREATE TABLE `platform_admin_sessions` (
  `platform_admin_session_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `platform_admin_session_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `platform_admin_id` BIGINT UNSIGNED NOT NULL COMMENT '管理员',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '用户；用于校验管理员与IAM会话主体一致',
  `auth_session_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM会话',
  `oauth_client_id` BIGINT UNSIGNED NOT NULL COMMENT '后台客户端',
  `session_digest` BINARY(32) NOT NULL COMMENT '管理会话凭证摘要',
  `last_seen_at` DATETIME NOT NULL COMMENT '最近活动',
  `idle_expires_at` DATETIME NOT NULL COMMENT '空闲截止',
  `expires_at` DATETIME NOT NULL COMMENT '绝对截止',
  `revoked_at` DATETIME NULL COMMENT '撤销时间',
  `revoke_reason` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '原因',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`platform_admin_session_id`),
  UNIQUE KEY `uk_biz_key` (`platform_admin_session_biz_key`),
  UNIQUE KEY `uk_session_digest` (`session_digest`),
  KEY `idx_admin_id` (`platform_admin_id`),
  KEY `idx_auth_session_id` (`auth_session_id`),
  KEY `idx_expires_at` (`expires_at`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='后台业务会话；每设备独立，不能使用is_login字段代替';


-- 追加式审计；应用DB账号禁止修改删除，按留存策略归档
CREATE TABLE `audit_events` (
  `audit_event_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `audit_event_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `actor_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '操作者业务标识；system用于系统动作',
  `actor_type` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT 'user/admin/system',
  `action_code` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '动作',
  `target_type` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '目标类型',
  `target_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '目标业务键',
  `action_result` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT 'success/failure',
  `request_id` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '请求关联',
  `event_details` TEXT NULL COMMENT '脱敏变更摘要，不含密码/code/token',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`audit_event_id`),
  UNIQUE KEY `uk_biz_key` (`audit_event_biz_key`),
  KEY `idx_actor_key_created_at` (`actor_key`,`create_time`),
  KEY `idx_target_type_target_key` (`target_type`,`target_key`),
  KEY `idx_created_at` (`create_time`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='追加式审计；应用DB账号禁止修改删除，按留存策略归档';


-- 业务事务内写入；至少一次投递，消费者幂等版本校验
CREATE TABLE `event_outbox` (
  `event_outbox_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `event_outbox_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `event_type` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '事件类型',
  `aggregate_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '聚合业务键',
  `aggregate_version` BIGINT UNSIGNED NOT NULL COMMENT '聚合版本',
  `event_payload` TEXT NOT NULL COMMENT '最小化事件内容',
  `publish_status` VARCHAR(16) COLLATE utf8mb4_bin NOT NULL DEFAULT 'pending' COMMENT 'pending|publishing|published|dead；需适配现有relay',
  `retry_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '重试次数',
  `available_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '下次投递时间',
  `lease_owner` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '工作进程租约',
  `lease_until` DATETIME NULL COMMENT '租约截止',
  `delivered_at` DATETIME NULL COMMENT '完成时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`event_outbox_id`),
  UNIQUE KEY `uk_biz_key` (`event_outbox_biz_key`),
  KEY `idx_status_available_at` (`publish_status`,`available_at`),
  KEY `idx_aggregate_key_aggregate_version` (`aggregate_key`,`aggregate_version`),
  CHECK (deleted_flag IN (0,1)),
  CHECK (publish_status IN ('pending','publishing','published','dead'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='业务事务内写入；至少一次投递，消费者幂等版本校验';


-- 用户偏好KV，不能承载密码/MFA/安全授权策略
CREATE TABLE `user_preference` (
  `user_preference_id` BIGINT UNSIGNED NOT NULL COMMENT '雪花ID（应用侧生成）',
  `user_preference_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '业务主键',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '所属主体主键ID，非业务键',
  `pref_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '白名单配置键',
  `pref_value` VARCHAR(4096) DEFAULT NULL COMMENT '配置值，纯文本或JSON；服务层验证类型与版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`user_preference_id`),
  UNIQUE KEY `uk_biz_key` (`user_preference_biz_key`),
  UNIQUE KEY `uk_preference` (`user_id`,`pref_key`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户偏好KV，不能承载密码/MFA/安全授权策略';


-- 平台全局KV，禁止写入个人偏好与明文密钥
CREATE TABLE `user_setting` (
  `user_setting_id` BIGINT UNSIGNED NOT NULL COMMENT '雪花ID（应用侧生成）',
  `user_setting_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '业务主键',
  `setting_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '白名单配置键',
  `setting_value` VARCHAR(4096) DEFAULT NULL COMMENT '配置值，纯文本或JSON；服务层验证类型与版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`user_setting_id`),
  UNIQUE KEY `uk_biz_key` (`user_setting_biz_key`),
  UNIQUE KEY `uk_preference` (`setting_key`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='平台全局KV，禁止写入个人偏好与明文密钥';


CREATE DATABASE IF NOT EXISTS `ppb_im` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `ppb_im`;

-- 聊天公共扩展；跨库user_id仅逻辑引用
CREATE TABLE `chat_user_profiles` (
  `chat_user_profile_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_user_profile_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM稳定内部用户ID',
  `chat_signature` VARCHAR(512) NULL COMMENT '聊天签名',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_user_profile_id`),
  UNIQUE KEY `uk_biz_key` (`chat_user_profile_biz_key`),
  UNIQUE KEY `uk_user_id` (`user_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天公共扩展；跨库user_id仅逻辑引用';


-- 聊天组织；独立于认证组织与应用域
CREATE TABLE `chat_workspaces` (
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_workspace_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `workspace_name` VARCHAR(128) NOT NULL COMMENT '组织名称',
  `workspace_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=suspended；3=closed；组织状态',
  `authz_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '组织角色授权版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_workspace_id`),
  UNIQUE KEY `uk_biz_key` (`chat_workspace_biz_key`),
  CHECK (`workspace_status` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天组织；独立于认证组织与应用域';


-- 聊天组织成员；离职不删除全局用户
CREATE TABLE `chat_memberships` (
  `chat_membership_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_membership_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '聊天组织',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM用户ID，逻辑引用',
  `member_nickname` VARCHAR(128) NULL COMMENT '组织内昵称',
  `employee_code` VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '组织内工号；无值使用NULL',
  `job_title` VARCHAR(128) NULL COMMENT '职位',
  `member_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=suspended；3=offboarded；成员状态',
  `joined_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '加入时间',
  `offboarded_at` DATETIME NULL COMMENT '离职时间',
  `authz_version` BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '成员授权版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_membership_id`),
  UNIQUE KEY `uk_biz_key` (`chat_membership_biz_key`),
  UNIQUE KEY `uk_workspace_id_user_id` (`chat_workspace_id`,`user_id`),
  UNIQUE KEY `uk_workspace_id_employee_code` (`chat_workspace_id`,`employee_code`),
  UNIQUE KEY `uk_membership_id_workspace_id` (`chat_membership_id`,`chat_workspace_id`),
  KEY `idx_user_id` (`user_id`),
  CHECK (`member_status` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天组织成员；离职不删除全局用户';


-- 组织内部门；服务层拒绝多级循环
CREATE TABLE `chat_departments` (
  `chat_department_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_department_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '组织',
  `parent_id` BIGINT UNSIGNED NULL COMMENT '上级部门',
  `department_name` VARCHAR(128) NOT NULL COMMENT '名称',
  `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_department_id`),
  UNIQUE KEY `uk_biz_key` (`chat_department_biz_key`),
  UNIQUE KEY `uk_department_id_workspace_id` (`chat_department_id`,`chat_workspace_id`),
  KEY `idx_workspace_id_parent_id` (`chat_workspace_id`,`parent_id`),
  CHECK (parent_id IS NULL OR parent_id <> chat_department_id),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='组织内部门；服务层拒绝多级循环';


-- 成员部门关系，最多一个主部门
CREATE TABLE `chat_membership_departments` (
  `chat_membership_department_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_membership_department_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '组织',
  `chat_membership_id` BIGINT UNSIGNED NOT NULL COMMENT '成员',
  `chat_department_id` BIGINT UNSIGNED NOT NULL COMMENT '部门',
  `is_primary` TINYINT NOT NULL DEFAULT 0 COMMENT '主部门：0否/1是',
  `primary_membership_id` BIGINT UNSIGNED GENERATED ALWAYS AS (CASE WHEN is_primary = 1 THEN chat_membership_id ELSE NULL END) STORED,
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_membership_department_id`),
  UNIQUE KEY `uk_biz_key` (`chat_membership_department_biz_key`),
  UNIQUE KEY `uk_membership_id_department_id` (`chat_membership_id`,`chat_department_id`),
  CHECK (is_primary IN (0,1)),
  UNIQUE KEY `uk_primary_membership_id` (`primary_membership_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='成员部门关系，最多一个主部门';


-- 聊天组织操作权限；与平台运营权限分开
CREATE TABLE `chat_permissions` (
  `chat_permission_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_permission_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `permission_code` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '权限码',
  `permission_name` VARCHAR(128) NOT NULL COMMENT '名称',
  `is_enabled` TINYINT NOT NULL DEFAULT 1 COMMENT '启用：0否/1是',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_permission_id`),
  UNIQUE KEY `uk_biz_key` (`chat_permission_biz_key`),
  UNIQUE KEY `uk_code` (`permission_code`),
  CHECK (is_enabled IN (0,1)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天组织操作权限；与平台运营权限分开';


-- 组织内角色owner/admin/member；最后owner保护由事务实现
CREATE TABLE `chat_roles` (
  `chat_role_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_role_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '组织',
  `role_code` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '角色码',
  `role_name` VARCHAR(128) NOT NULL COMMENT '名称',
  `is_builtin` TINYINT NOT NULL DEFAULT 0 COMMENT '内置角色：0否/1是',
  `is_enabled` TINYINT NOT NULL DEFAULT 1 COMMENT '启用：0否/1是',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_role_id`),
  UNIQUE KEY `uk_biz_key` (`chat_role_biz_key`),
  UNIQUE KEY `uk_workspace_id_code` (`chat_workspace_id`,`role_code`),
  UNIQUE KEY `uk_chat_role_id_workspace_id` (`chat_role_id`,`chat_workspace_id`),
  CHECK (is_enabled IN (0,1)),
  CHECK (is_builtin IN (0,1)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='组织内角色owner/admin/member；最后owner保护由事务实现';


-- 聊天角色权限；不通过平台菜单授予
CREATE TABLE `chat_role_permissions` (
  `chat_role_permission_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_role_permission_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_role_id` BIGINT UNSIGNED NOT NULL COMMENT '聊天角色',
  `chat_permission_id` BIGINT UNSIGNED NOT NULL COMMENT '聊天权限',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_role_permission_id`),
  UNIQUE KEY `uk_biz_key` (`chat_role_permission_biz_key`),
  UNIQUE KEY `uk_chat_role_id_chat_permission_id` (`chat_role_id`,`chat_permission_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天角色权限；不通过平台菜单授予';


-- 组织成员角色；跨组织关联由复合外键拒绝
CREATE TABLE `chat_membership_roles` (
  `chat_membership_role_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_membership_role_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '组织',
  `chat_membership_id` BIGINT UNSIGNED NOT NULL COMMENT '成员',
  `chat_role_id` BIGINT UNSIGNED NOT NULL COMMENT '角色',
  `valid_until` DATETIME NULL COMMENT '角色截止',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_membership_role_id`),
  UNIQUE KEY `uk_biz_key` (`chat_membership_role_biz_key`),
  UNIQUE KEY `uk_membership_id_chat_role_id` (`chat_membership_id`,`chat_role_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='组织成员角色；跨组织关联由复合外键拒绝';


-- 聊天组织邀请；接受时再次检查邀请者和组织状态
CREATE TABLE `chat_invitations` (
  `chat_invitation_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_invitation_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '组织',
  `inviter_membership_id` BIGINT UNSIGNED NOT NULL COMMENT '邀请者',
  `target_identity` VARCHAR(254) NOT NULL COMMENT '受邀目标，确权后匹配',
  `token_digest` BINARY(32) NOT NULL COMMENT '高熵邀请凭证摘要',
  `invitation_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=pending；2=accepted；3=revoked；4=expired；状态',
  `expires_at` DATETIME NOT NULL COMMENT '失效时间',
  `accepted_user_id` BIGINT UNSIGNED NULL COMMENT '接受者IAM用户ID',
  `accepted_at` DATETIME NULL COMMENT '接受时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_invitation_id`),
  UNIQUE KEY `uk_biz_key` (`chat_invitation_biz_key`),
  UNIQUE KEY `uk_token_digest` (`token_digest`),
  UNIQUE KEY `uk_invitation_id_workspace_id` (`chat_invitation_id`,`chat_workspace_id`),
  KEY `idx_workspace_id_status` (`chat_workspace_id`,`invitation_status`),
  CHECK (`invitation_status` IN (1,2,3,4)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天组织邀请；接受时再次检查邀请者和组织状态';


-- 邀请拟授予角色，接受时重新核验可授予范围
CREATE TABLE `chat_invitation_roles` (
  `chat_invitation_role_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_invitation_role_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `chat_invitation_id` BIGINT UNSIGNED NOT NULL COMMENT '邀请',
  `chat_workspace_id` BIGINT UNSIGNED NOT NULL COMMENT '组织',
  `chat_role_id` BIGINT UNSIGNED NOT NULL COMMENT '拟授予角色',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_invitation_role_id`),
  UNIQUE KEY `uk_biz_key` (`chat_invitation_role_biz_key`),
  UNIQUE KEY `uk_invitation_id_chat_role_id` (`chat_invitation_id`,`chat_role_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='邀请拟授予角色，接受时重新核验可授予范围';


-- 聊天业务会话；关联IAM会话事件撤销，不跨库外键
CREATE TABLE `chat_sessions` (
  `chat_session_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `chat_session_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM用户',
  `iam_session_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT 'IAM会话关联标识',
  `session_digest` BINARY(32) NOT NULL COMMENT '业务凭证摘要',
  `expires_at` DATETIME NOT NULL COMMENT '截止',
  `revoked_at` DATETIME NULL COMMENT '撤销',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_session_id`),
  UNIQUE KEY `uk_biz_key` (`chat_session_biz_key`),
  UNIQUE KEY `uk_session_digest` (`session_digest`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_iam_session_key` (`iam_session_key`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='聊天业务会话；关联IAM会话事件撤销，不跨库外键';


-- 追加式审计；应用DB账号禁止修改删除，按留存策略归档
CREATE TABLE `audit_events` (
  `audit_event_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `audit_event_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `actor_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '操作者业务标识；system用于系统动作',
  `actor_type` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT 'user/admin/system',
  `action_code` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '动作',
  `target_type` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '目标类型',
  `target_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '目标业务键',
  `action_result` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT 'success/failure',
  `request_id` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '请求关联',
  `event_details` TEXT NULL COMMENT '脱敏变更摘要，不含密码/code/token',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`audit_event_id`),
  UNIQUE KEY `uk_biz_key` (`audit_event_biz_key`),
  KEY `idx_actor_key_created_at` (`actor_key`,`create_time`),
  KEY `idx_target_type_target_key` (`target_type`,`target_key`),
  KEY `idx_created_at` (`create_time`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='追加式审计；应用DB账号禁止修改删除，按留存策略归档';


-- 业务事务内写入；至少一次投递，消费者幂等版本校验
CREATE TABLE `event_outbox` (
  `event_outbox_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `event_outbox_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `event_type` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '事件类型',
  `aggregate_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '聚合业务键',
  `aggregate_version` BIGINT UNSIGNED NOT NULL COMMENT '聚合版本',
  `event_payload` TEXT NOT NULL COMMENT '最小化事件内容',
  `publish_status` VARCHAR(16) COLLATE utf8mb4_bin NOT NULL DEFAULT 'pending' COMMENT 'pending|publishing|published|dead；需适配现有relay',
  `retry_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '重试次数',
  `available_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '下次投递时间',
  `lease_owner` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '工作进程租约',
  `lease_until` DATETIME NULL COMMENT '租约截止',
  `delivered_at` DATETIME NULL COMMENT '完成时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`event_outbox_id`),
  UNIQUE KEY `uk_biz_key` (`event_outbox_biz_key`),
  KEY `idx_status_available_at` (`publish_status`,`available_at`),
  KEY `idx_aggregate_key_aggregate_version` (`aggregate_key`,`aggregate_version`),
  CHECK (deleted_flag IN (0,1)),
  CHECK (publish_status IN ('pending','publishing','published','dead'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='业务事务内写入；至少一次投递，消费者幂等版本校验';


-- 用户偏好KV，不能承载密码/MFA/安全授权策略
CREATE TABLE `chat_user_preference` (
  `chat_user_preference_id` BIGINT UNSIGNED NOT NULL COMMENT '雪花ID（应用侧生成）',
  `chat_user_preference_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '业务主键',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT '所属主体主键ID，非业务键',
  `pref_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '白名单配置键',
  `pref_value` VARCHAR(4096) DEFAULT NULL COMMENT '配置值，纯文本或JSON；服务层验证类型与版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`chat_user_preference_id`),
  UNIQUE KEY `uk_biz_key` (`chat_user_preference_biz_key`),
  UNIQUE KEY `uk_preference` (`user_id`,`pref_key`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户偏好KV，不能承载密码/MFA/安全授权策略';


CREATE DATABASE IF NOT EXISTS `ppb_camera` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `ppb_camera`;

-- 相机业务账号；新用户开通按user_id幂等
CREATE TABLE `camera_accounts` (
  `camera_account_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `camera_account_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM用户ID，逻辑引用',
  `account_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=suspended；3=closed；业务状态',
  `activated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '开通',
  `closed_at` DATETIME NULL COMMENT '关闭',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`camera_account_id`),
  UNIQUE KEY `uk_biz_key` (`camera_account_biz_key`),
  UNIQUE KEY `uk_user_id` (`user_id`),
  CHECK (`account_status` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='相机业务账号；新用户开通按user_id幂等';


-- 相机扩展；NULL代表继承公共资料，空串代表显式清空
CREATE TABLE `camera_user_profiles` (
  `camera_user_profile_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `camera_user_profile_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `camera_account_id` BIGINT UNSIGNED NOT NULL COMMENT '相机账号',
  `display_name_override` VARCHAR(128) NULL COMMENT '业务昵称覆盖',
  `avatar_file_key_override` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '业务头像覆盖',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`camera_user_profile_id`),
  UNIQUE KEY `uk_biz_key` (`camera_user_profile_biz_key`),
  UNIQUE KEY `uk_camera_account_id` (`camera_account_id`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='相机扩展；NULL代表继承公共资料，空串代表显式清空';


-- 相机业务会话；不承担游客额度身份合并
CREATE TABLE `camera_sessions` (
  `camera_session_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `camera_session_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `camera_account_id` BIGINT UNSIGNED NOT NULL COMMENT '相机账号',
  `iam_session_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT 'IAM会话关联',
  `session_digest` BINARY(32) NOT NULL COMMENT '业务凭证摘要',
  `expires_at` DATETIME NOT NULL COMMENT '截止',
  `revoked_at` DATETIME NULL COMMENT '撤销',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`camera_session_id`),
  UNIQUE KEY `uk_biz_key` (`camera_session_biz_key`),
  UNIQUE KEY `uk_session_digest` (`session_digest`),
  KEY `idx_camera_account_id` (`camera_account_id`),
  KEY `idx_iam_session_key` (`iam_session_key`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='相机业务会话；不承担游客额度身份合并';


-- 追加式审计；应用DB账号禁止修改删除，按留存策略归档
CREATE TABLE `audit_events` (
  `audit_event_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `audit_event_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `actor_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '操作者业务标识；system用于系统动作',
  `actor_type` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT 'user/admin/system',
  `action_code` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '动作',
  `target_type` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '目标类型',
  `target_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '目标业务键',
  `action_result` VARCHAR(32) COLLATE utf8mb4_bin NOT NULL COMMENT 'success/failure',
  `request_id` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '请求关联',
  `event_details` TEXT NULL COMMENT '脱敏变更摘要，不含密码/code/token',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`audit_event_id`),
  UNIQUE KEY `uk_biz_key` (`audit_event_biz_key`),
  KEY `idx_actor_key_created_at` (`actor_key`,`create_time`),
  KEY `idx_target_type_target_key` (`target_type`,`target_key`),
  KEY `idx_created_at` (`create_time`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='追加式审计；应用DB账号禁止修改删除，按留存策略归档';


-- 业务事务内写入；至少一次投递，消费者幂等版本校验
CREATE TABLE `event_outbox` (
  `event_outbox_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `event_outbox_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `event_type` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '事件类型',
  `aggregate_key` VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '聚合业务键',
  `aggregate_version` BIGINT UNSIGNED NOT NULL COMMENT '聚合版本',
  `event_payload` TEXT NOT NULL COMMENT '最小化事件内容',
  `publish_status` VARCHAR(16) COLLATE utf8mb4_bin NOT NULL DEFAULT 'pending' COMMENT 'pending|publishing|published|dead；需适配现有relay',
  `retry_count` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '重试次数',
  `available_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '下次投递时间',
  `lease_owner` VARCHAR(128) COLLATE utf8mb4_bin NULL COMMENT '工作进程租约',
  `lease_until` DATETIME NULL COMMENT '租约截止',
  `delivered_at` DATETIME NULL COMMENT '完成时间',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`event_outbox_id`),
  UNIQUE KEY `uk_biz_key` (`event_outbox_biz_key`),
  KEY `idx_status_available_at` (`publish_status`,`available_at`),
  KEY `idx_aggregate_key_aggregate_version` (`aggregate_key`,`aggregate_version`),
  CHECK (deleted_flag IN (0,1)),
  CHECK (publish_status IN ('pending','publishing','published','dead'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='业务事务内写入；至少一次投递，消费者幂等版本校验';


-- 用户偏好KV，不能承载密码/MFA/安全授权策略
CREATE TABLE `camera_user_preference` (
  `camera_user_preference_id` BIGINT UNSIGNED NOT NULL COMMENT '雪花ID（应用侧生成）',
  `camera_user_preference_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '业务主键',
  `camera_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属主体主键ID，非业务键',
  `pref_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '白名单配置键',
  `pref_value` VARCHAR(4096) DEFAULT NULL COMMENT '配置值，纯文本或JSON；服务层验证类型与版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`camera_user_preference_id`),
  UNIQUE KEY `uk_biz_key` (`camera_user_preference_biz_key`),
  UNIQUE KEY `uk_preference` (`camera_account_id`,`pref_key`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户偏好KV，不能承载密码/MFA/安全授权策略';


CREATE DATABASE IF NOT EXISTS `ppb_wardrobe` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `ppb_wardrobe`;

-- 衣橱业务账号
CREATE TABLE `wardrobe_accounts` (
  `wardrobe_account_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `wardrobe_account_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `user_id` BIGINT UNSIGNED NOT NULL COMMENT 'IAM用户ID，逻辑引用',
  `account_status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=active；2=suspended；3=closed；业务状态',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`wardrobe_account_id`),
  UNIQUE KEY `uk_biz_key` (`wardrobe_account_biz_key`),
  UNIQUE KEY `uk_user_id` (`user_id`),
  CHECK (`account_status` IN (1,2,3)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='衣橱业务账号';


-- 身材尺码是衣橱私有资料，不作为IAM公共资料
CREATE TABLE `wardrobe_user_profiles` (
  `wardrobe_user_profile_id` BIGINT UNSIGNED NOT NULL COMMENT '应用侧生成的稳定主键；迁移时保留旧ID',
  `wardrobe_user_profile_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '不透明业务键，应用侧生成',
  `wardrobe_account_id` BIGINT UNSIGNED NOT NULL COMMENT '衣橱账号',
  `height_cm` DECIMAL(5,2) NULL COMMENT '身高cm',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间，UTC',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间，UTC',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记：0正常 1删除；安全校验必须过滤',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`wardrobe_user_profile_id`),
  UNIQUE KEY `uk_biz_key` (`wardrobe_user_profile_biz_key`),
  UNIQUE KEY `uk_wardrobe_account_id` (`wardrobe_account_id`),
  CHECK (height_cm IS NULL OR (height_cm > 0 AND height_cm < 300)),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='身材尺码是衣橱私有资料，不作为IAM公共资料';


-- 用户偏好KV，不能承载密码/MFA/安全授权策略
CREATE TABLE `wardrobe_user_preference` (
  `wardrobe_user_preference_id` BIGINT UNSIGNED NOT NULL COMMENT '雪花ID（应用侧生成）',
  `wardrobe_user_preference_biz_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '业务主键',
  `wardrobe_account_id` BIGINT UNSIGNED NOT NULL COMMENT '所属主体主键ID，非业务键',
  `pref_key` VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '白名单配置键',
  `pref_value` VARCHAR(4096) DEFAULT NULL COMMENT '配置值，纯文本或JSON；服务层验证类型与版本',
  `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '软删除标记',
  `deleted_time` DATETIME DEFAULT NULL COMMENT '删除时间',
  PRIMARY KEY (`wardrobe_user_preference_id`),
  UNIQUE KEY `uk_biz_key` (`wardrobe_user_preference_biz_key`),
  UNIQUE KEY `uk_preference` (`wardrobe_account_id`,`pref_key`),
  CHECK (deleted_flag IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户偏好KV，不能承载密码/MFA/安全授权策略';


-- 示例种子：不创建用户/超管，不向个人分配任何角色。
USE ppb_iam;
START TRANSACTION;
INSERT INTO `applications` (`application_id`, `application_biz_key`, `app_key`, `application_name`, `access_policy`) VALUES (1, 'app_iam', 'iam', '认证中心', 2), (2, 'app_base', 'base', '平台管理', 2), (3, 'app_chat', 'chat', '聊天', 2), (4, 'app_camera', 'camera', '相机', 1), (5, 'app_wardrobe', 'wardrobe', '衣橱', 1);
INSERT INTO `platform_permissions` (`platform_permission_id`, `platform_permission_biz_key`, `application_id`, `permission_code`, `permission_name`) VALUES (101, 'perm_camera_read', 4, 'template.read', '读取模板'), (102, 'perm_camera_edit', 4, 'template.edit', '编辑模板'), (103, 'perm_camera_publish', 4, 'template.publish', '发布模板');
INSERT INTO `platform_roles` (`platform_role_id`, `platform_role_biz_key`, `application_id`, `role_code`, `role_name`) VALUES (101, 'role_camera_editor', 4, 'template_editor', '模板编辑'), (102, 'role_camera_publisher', 4, 'template_publisher', '模板发布');
INSERT INTO `platform_menus` (`platform_menu_id`, `platform_menu_biz_key`, `application_id`, `surface_key`, `parent_id`, `menu_key`, `node_type`, `menu_name`, `route_key`, `sort_order`) VALUES (101, 'menu_camera_root', 4, 'platform', NULL, 'camera', 1, '相机管理', NULL, 10), (102, 'menu_camera_templates', 4, 'platform', 101, 'camera.templates', 2, '模板管理', 'camera.templates', 10), (103, 'menu_camera_edit', 4, 'platform', 102, 'camera.templates.edit', 3, '编辑模板', NULL, 10), (104, 'menu_camera_publish', 4, 'platform', 102, 'camera.templates.publish', 3, '发布模板', NULL, 20);
INSERT INTO `platform_menu_permissions` (`platform_menu_permission_id`, `platform_menu_permission_biz_key`, `platform_menu_id`, `platform_permission_id`, `application_id`) VALUES (101, 'mp_camera_read', 102, 101, 4), (102, 'mp_camera_edit', 103, 102, 4), (103, 'mp_camera_publish', 104, 103, 4);
INSERT INTO `platform_role_menus` (`platform_role_menu_id`, `platform_role_menu_biz_key`, `platform_role_id`, `platform_menu_id`, `application_id`) VALUES (101, 'rm_editor_page', 101, 102, 4), (102, 'rm_editor_edit', 101, 103, 4), (103, 'rm_publisher_page', 102, 102, 4), (104, 'rm_publisher_publish', 102, 104, 4);
COMMIT;

-- 管理权限汇总查询（不执行，问号由应用参数绑定；调用前验证session、MFA、应用准入）。
-- 授权入口为角色菜单，按钮是menu节点；不再增加platform_role_permissions双权威。
-- SELECT DISTINCT app.app_key,p.permission_code
-- FROM platform_admins a
-- JOIN user u ON u.user_id=a.user_id AND u.user_status=1 AND u.deleted_flag=0
-- JOIN platform_admin_roles ar ON ar.platform_admin_id=a.platform_admin_id AND ar.deleted_flag=0
-- JOIN platform_roles r ON r.platform_role_id=ar.platform_role_id AND r.role_status=1 AND r.deleted_flag=0
-- JOIN applications app ON app.application_id=r.application_id AND app.application_status=1 AND app.deleted_flag=0
-- JOIN platform_role_menus rm ON rm.platform_role_id=r.platform_role_id AND rm.deleted_flag=0
-- JOIN platform_menus m ON m.platform_menu_id=rm.platform_menu_id AND m.menu_status=1 AND m.deleted_flag=0
-- JOIN platform_menu_permissions mp ON mp.platform_menu_id=m.platform_menu_id AND mp.deleted_flag=0
-- JOIN platform_permissions p ON p.platform_permission_id=mp.platform_permission_id AND p.permission_status=1 AND p.deleted_flag=0
-- WHERE a.platform_admin_id=? AND a.admin_status=1 AND a.deleted_flag=0
-- AND (a.valid_until IS NULL OR a.valid_until>UTC_TIMESTAMP())
-- AND (ar.valid_until IS NULL OR ar.valid_until>UTC_TIMESTAMP());
-- 此查询仅示例基础汇总；必须额外校验同application_id、页面依赖和祖先未停用。
-- is_super通过显式治理分支处理，不隐式授予敏感业务数据访问。


-- 服务层约束索引；完整规则见../技术大纲.md、../数据模型.md和../注册与登录流程.md。
-- 1. 所有授权查询过滤deleted_flag=0并校验全链状态、到期与会话；软删不能代替撤销。
-- 2. user/identity退役默认保留唯一键占用；关联撤权物理删除或恢复原软删行，并留审计。
-- 3. platform_role_menus、platform_menu_permissions、roles/menus/permissions必须同application_id。
--    菜单父子同surface_key和应用；检查多级循环。chat成员/角色/部门/邀请必须同组织。
-- 4. 目录祖先只用于导航，不隐式授予权限；按钮需有页面权限，新增按钮不自动授予旧角色。
--    is_hidden只控制展示；停用/删除祖先阻断子树；接口独立检查操作权限和资源范围。
-- 5. 修改角色菜单递增role_version和应用authz_version；映射变动递增应用版本；
--    个人角色分配递增admin.authz_version并可靠失效缓存。菜单映射编辑需防止自我提权。
-- 6. is_super只能由受保护治理接口修改；最后有效超管/聊天owner须事务串行保护。
-- 7. grant/client/session/user主体一致，子凭证期限不得超过父授权；PKCE、issuer/aud、nonce、
--    签名、scope、回调地址由协议层校验；公开客户端无secret。密钥只存引用。
-- 8. 授权码/验证码单次消费与会话授权创建同事务；刷新锁family，检测重放撤族，拒绝分叉。
-- 9. 管理会话user_id与platform_admin及IAM会话一致；撤管理资格只撤管理访问。
--    全局停用撤全部会话，通过event_outbox可靠通知业务HTTP/WS；高权限故障拒绝。
-- 10. 个人开关按库归KV，user_setting仅全局配置，禁止放个人资料/明文密钥或授权事实。
-- 11. IAM注册和业务开通分库事务，业务按user_id幂等；开通失败可重试，不删除全局用户。
-- 12. event_outbox至少一次投递；消费者以事件biz_key和聚合版本持久幂等；需inbox/等效记录。
-- 13. 不声明DDL实现了OIDC/MFA/限流/CSRF/登录Cookie；时限和撤权SLA在实施时固定并验收。
-- 14. 上游第三方认证事务和下游login_transactions分开；上游state/nonce/verifier安全短期保存。
-- 15. 新环境受控命令创建首个超管；密码迁移、旧主键/业务键保留、同人账号合并均须独立验证。
-- 16. 存量DDL列变动必须单独迁移，并同步GORM标签、IDL/API映射和查询；不得直接覆盖旧库。

