-- 媒体Worker可选目标态，在独立ppb_media schema执行；HLS包为P1。
-- file与媒体跨库用业务键，不JOIN、不建跨库外键。

CREATE TABLE `media_assets` (
  media_asset_id BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花主键',
  media_asset_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '稳定业务键',
  create_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  update_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  application_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '所属应用',
  input_file_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '输入file跨库逻辑关联',
  duration_millis BIGINT NULL COMMENT '真实时长',
  media_width INT NULL COMMENT '像素宽',
  media_height INT NULL COMMENT '像素高',
  video_codec VARCHAR(64) NULL COMMENT '视频编码',
  audio_codec VARCHAR(64) NULL COMMENT '音频编码',
  rotation_degrees INT NULL COMMENT '旋转信息',
  probe_status TINYINT NOT NULL DEFAULT 1 COMMENT '1pending 2ready 3failed',
  PRIMARY KEY (media_asset_id),
  UNIQUE KEY uk_media_asset_biz (media_asset_biz_key),
  UNIQUE KEY uk_media_asset_input (application_biz_key,input_file_biz_key),
  CONSTRAINT ck_media_probe CHECK (probe_status IN (1,2,3) AND (duration_millis IS NULL OR duration_millis >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='媒体探测元数据';

CREATE TABLE `media_jobs` (
  media_job_id BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花主键',
  media_job_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '稳定业务键',
  create_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  update_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  application_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '所属应用',
  input_file_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '输入文件',
  request_key VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '幂等请求键',
  profile_code VARCHAR(64) NOT NULL COMMENT '白名单处理方案',
  profile_version INT NOT NULL COMMENT '方案版本',
  job_status TINYINT NOT NULL DEFAULT 1 COMMENT '1queued 2running 3ready 4failed 5cancelled',
  input_reference_key VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '输入处理保护引用',
  quota_reservation_key VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '输出预算预留凭据',
  retry_count INT NOT NULL DEFAULT 0 COMMENT '重试次数',
  lease_expire_time DATETIME(3) NULL COMMENT '租约截止',
  error_code VARCHAR(64) NULL COMMENT '脱敏错误',
  completed_time DATETIME(3) NULL COMMENT '终态时间',
  PRIMARY KEY (media_job_id),
  UNIQUE KEY uk_media_job_biz (media_job_biz_key),
  UNIQUE KEY uk_media_job_request (application_biz_key,request_key),
  KEY idx_media_job_status (job_status,lease_expire_time),
  CONSTRAINT ck_media_job_values CHECK (profile_version > 0 AND retry_count >= 0 AND job_status IN (1,2,3,4,5))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='媒体异步作业';

CREATE TABLE `media_packages` (
  media_package_id BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花主键',
  media_package_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '稳定业务键',
  create_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  update_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  application_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '所属应用',
  media_job_id BIGINT UNSIGNED NOT NULL COMMENT '创建任务',
  package_format VARCHAR(16) NOT NULL COMMENT 'hls|dash',
  storage_backend_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '跨库后端标识',
  object_prefix VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '平台分配不可变包目录',
  manifest_object_key VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '主清单键',
  inventory_object_key VARCHAR(512) COLLATE utf8mb4_bin NOT NULL COMMENT '包内对象清单键',
  size_bytes BIGINT NOT NULL DEFAULT 0 COMMENT '整个包实测计费大小',
  file_quota_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '容量账户',
  package_status TINYINT NOT NULL DEFAULT 1 COMMENT '1staging 2ready 3deleting 4deleted',
  protection_reference_key VARCHAR(128) COLLATE utf8mb4_bin NOT NULL COMMENT '包保护关联，媒体服务管理',
  revision_number BIGINT NOT NULL DEFAULT 1 COMMENT '包级授权/删除版本',
  PRIMARY KEY (media_package_id),
  UNIQUE KEY uk_media_package_biz (media_package_biz_key),
  KEY idx_media_package_job (media_job_id),
  CONSTRAINT ck_media_package_values CHECK (size_bytes >= 0 AND package_status IN (1,2,3,4))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='流媒体逻辑包，P1独立发布与GC';

CREATE TABLE `media_outputs` (
  media_output_id BIGINT UNSIGNED NOT NULL COMMENT '应用侧雪花主键',
  media_output_biz_key VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '稳定业务键',
  create_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
  update_time DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '更新时间',
  media_job_id BIGINT UNSIGNED NOT NULL COMMENT '任务',
  output_role VARCHAR(64) NOT NULL COMMENT 'cover|mp4_720p等',
  output_file_biz_key VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '独立产物文件',
  output_package_biz_key VARCHAR(64) COLLATE utf8mb4_bin NULL COMMENT '流媒体包，与file二选一',
  media_width INT NULL COMMENT '输出宽',
  media_height INT NULL COMMENT '输出高',
  bitrate_bps BIGINT NULL COMMENT '实际码率',
  output_status TINYINT NOT NULL DEFAULT 1 COMMENT '1pending 2ready 3failed',
  PRIMARY KEY (media_output_id),
  UNIQUE KEY uk_media_output_biz (media_output_biz_key),
  UNIQUE KEY uk_media_output_role (media_job_id,output_role),
  CONSTRAINT ck_media_output_values CHECK (((output_file_biz_key IS NOT NULL) + (output_package_biz_key IS NOT NULL)) = 1 AND output_status IN (1,2,3))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='任务产物';
