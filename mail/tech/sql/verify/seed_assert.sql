-- 一次性验证用：向 ppb_mail 写入样例数据并断言 8 个视图的输出。
-- 域名用 RFC 2606 保留域，地址用 RFC 5737 文档网段，不是真实数据。
USE ppb_mail;
SET time_zone = '+00:00';

DELIMITER $$
CREATE PROCEDURE assert_fail(IN cond BOOLEAN, IN msg VARCHAR(255))
BEGIN
  IF cond IS NULL OR cond THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
  END IF;
END$$
DELIMITER ;

INSERT INTO mail_endpoint (mail_endpoint_id, public_hostname, public_ip)
VALUES (1, 'mail.example.com', '192.0.2.10');

-- 三个域：默认域、普通域、停用域
INSERT INTO mail_domain (mail_domain_id, domain_name, default_flag, domain_status, dkim_selector)
VALUES (1, 'example.com', 1, 1, 's202611'),
       (2, 'example.net', 0, 1, 's202611'),
       (3, 'example.org', 0, 2, 's202611');

INSERT INTO mail_domain_dkim_key (dkim_key_id, mail_domain_id, dkim_selector, dkim_key_path, dkim_public_record, active_flag)
VALUES (11, 1, 's202611', 'dkim/example.com/s202611.key', 'v=DKIM1; k=rsa; p=CURRENT', 1),
       (12, 1, 's202601', 'dkim/example.com/s202601.key', 'v=DKIM1; k=rsa; p=OLD', 0);

-- 101 正常；102 管理员停用；103 待删除；104 第二个域里正常；105 账号正常但所在域停用；106 临时密码已过期
INSERT INTO mail_account (mail_account_id, user_id, mail_domain_id, account_local, mail_address,
                          account_status, admin_suspended_flag, iam_status, password_hash,
                          password_expire_time, quota_bytes, purge_time)
VALUES (101, 9001, 1, 'zhangsan', 'zhangsan@example.com', 1, 0, 1, '{SHA512-CRYPT}$6$a', NULL, 5368709120, NULL),
       (102, 9002, 1, 'lisi',      'lisi@example.com',      2, 1, 1, '{SHA512-CRYPT}$6$b', NULL, 5368709120, NULL),
       (103, 9003, 1, 'wangwu',    'wangwu@example.com',    3, 0, 3, '{SHA512-CRYPT}$6$c', NULL, 5368709120, '2026-12-24 00:00:00'),
       (104, 9004, 2, 'zhaoliu',   'zhaoliu@example.net',   1, 0, 1, '{SHA512-CRYPT}$6$d', NULL, 5368709120, NULL),
       (105, 9005, 3, 'sunqi',     'sunqi@example.org',     1, 0, 1, '{SHA512-CRYPT}$6$e', NULL, 5368709120, NULL),
       (106, 9006, 1, 'temp',      'temp@example.com',      1, 0, 1, '{SHA512-CRYPT}$6$f', '2026-01-01 00:00:00', 5368709120, NULL);

INSERT INTO mail_alias (mail_alias_id, mail_account_id, alias_address, alias_source)
VALUES (201, 101, 'zhang.san@example.com', 1),
       (202, 101, 'zs@example.net',        1),
       (203, 102, 'lisi.alias@example.com', 2),
       (204, 103, 'wangwu.old@example.com', 3),
       (205, 105, 'sq@example.com', 1),        -- 目标邮箱所在域停用
       (206, 101, 'other@example.org', 1);     -- 别名自己所在的域停用

INSERT INTO mail_system_alias (system_alias_id, mail_domain_id, alias_local, target_address)
VALUES (301, 1, 'postmaster', 'zhangsan@example.com'),
       (302, 1, 'abuse',      'zhangsan@example.com'),
       (303, 2, 'postmaster', 'zhaoliu@example.net');

-- 401 已验证且保留副本；402 已验证不留副本（管理员设置）；403 未验证
INSERT INTO mail_forward (mail_forward_id, mail_account_id, forward_address, keep_copy_flag, enable_flag, verify_status, forward_source)
VALUES (401, 101, 'zhangsan@external.example', 1, 1, 2, 1),
       (402, 104, 'zhaoliu@external.example',  0, 1, 2, 2),
       (403, 105, 'sunqi@external.example',    1, 1, 2, 1),     -- 已验证，但邮箱所在域停用
       (404, 102, 'lisi@external.example',      1, 1, 2, 1);     -- 已验证，但邮箱停用

INSERT INTO mail_blocklist (blocklist_id, list_type, block_type, block_value, creator_admin_id)
VALUES (501, 1, 1, 'spam@example.org',    1),
       (502, 1, 2, 'spamhouse.example',   1),
       (503, 2, 1, 'friend@example.org',  1);

-- 域视图：只有状态正常的域
CALL assert_fail((SELECT COUNT(*) FROM v_mail_domain) <> 2, 'A01 v_mail_domain 行数应为 2');
CALL assert_fail((SELECT GROUP_CONCAT(domain ORDER BY domain) FROM v_mail_domain) <> 'example.com,example.net', 'A02 v_mail_domain 内容不符');

-- 邮箱视图：状态正常且所在域正常的账号；临时密码过期的账号仍能收信
CALL assert_fail((SELECT GROUP_CONCAT(address ORDER BY address) FROM v_mailbox) <> 'temp@example.com,zhangsan@example.com,zhaoliu@example.net', 'A03 v_mailbox 内容不符');

-- 收件人策略视图：停用和待删除的邮箱
CALL assert_fail((SELECT GROUP_CONCAT(address ORDER BY address) FROM v_mail_recipient_policy) <> 'lisi@example.com,wangwu@example.com', 'A04 v_mail_recipient_policy 内容不符');
CALL assert_fail((SELECT COUNT(*) FROM v_mail_recipient_policy WHERE action <> 'REJECT Mailbox disabled') <> 0, 'A05 v_mail_recipient_policy 的 action 应为 REJECT Mailbox disabled');

-- 别名视图：别名、保留地址、已验证的转发；停用邮箱的别名和未验证的转发不出现
CALL assert_fail((SELECT COUNT(*) FROM v_mail_alias) <> 7, 'A06 v_mail_alias 行数应为 7');
CALL assert_fail((SELECT goto FROM v_mail_alias WHERE address = 'zhang.san@example.com') <> 'zhangsan@example.com', 'A07 别名解析');
CALL assert_fail((SELECT goto FROM v_mail_alias WHERE address = 'zhangsan@example.com') <> 'zhangsan@example.com,zhangsan@external.example', 'A08 转发保留副本');
CALL assert_fail((SELECT goto FROM v_mail_alias WHERE address = 'zhaoliu@example.net') <> 'zhaoliu@external.example', 'A09 转发不留副本');
CALL assert_fail((SELECT COUNT(*) FROM v_mail_alias WHERE address IN ('sunqi@example.org', 'lisi@example.com', 'lisi.alias@example.com', 'wangwu.old@example.com', 'sq@example.com', 'other@example.org')) <> 0, 'A10 不应出现的别名');
CALL assert_fail((SELECT COUNT(*) FROM v_mail_sender WHERE address LIKE '%@example.org' OR login_name LIKE '%@example.org') <> 0, 'A10b 停用域的地址不应出现在发件地址视图');
CALL assert_fail((SELECT COUNT(*) FROM v_mail_dovecot_user WHERE home = '/var/vmail/example.com/zhangsan' AND userid = 'zhangsan@example.com') <> 1, 'A10c 用户视图的 home 按域名和账号名分层');

-- 发件地址视图：登录账号到它的主地址和全部别名
CALL assert_fail((SELECT COUNT(*) FROM v_mail_sender) <> 5, 'A11 v_mail_sender 行数应为 5');
CALL assert_fail((SELECT GROUP_CONCAT(address ORDER BY address) FROM v_mail_sender WHERE login_name = 'zhangsan@example.com') <> 'zhang.san@example.com,zhangsan@example.com,zs@example.net', 'A12 v_mail_sender 内容不符');

-- 黑名单视图：只有黑名单
CALL assert_fail((SELECT COUNT(*) FROM v_mail_blocklist) <> 2, 'A13 v_mail_blocklist 行数应为 2');

-- Dovecot 用户视图
CALL assert_fail((SELECT COUNT(*) FROM v_mail_dovecot_user) <> 3, 'A14 v_mail_dovecot_user 行数应为 3');
CALL assert_fail((SELECT CONCAT_WS('|', uid, gid, home, mail, quota_rule) FROM v_mail_dovecot_user WHERE userid = 'zhangsan@example.com')
  <> '5000|5000|/var/vmail/example.com/zhangsan|maildir:~/Maildir|*:bytes=5368709120', 'A15 v_mail_dovecot_user 字段不符');

-- Dovecot 密码视图：不含临时密码已过期的账号
CALL assert_fail((SELECT GROUP_CONCAT(userid ORDER BY userid) FROM v_mail_dovecot_passwd) <> 'zhangsan@example.com,zhaoliu@example.net', 'A16 v_mail_dovecot_passwd 内容不符');

-- 物理删除后地址和域名可以重新分配
DELETE FROM mail_account WHERE mail_account_id = 106;
INSERT INTO mail_account (mail_account_id, user_id, mail_domain_id, account_local, mail_address, account_status, password_hash, quota_bytes)
VALUES (107, 9007, 1, 'temp', 'temp@example.com', 1, '{SHA512-CRYPT}$6$g', 5368709120);
DELETE FROM mail_alias WHERE mail_account_id IN (SELECT mail_account_id FROM (SELECT mail_account_id FROM mail_account WHERE mail_domain_id = 2) t);
DELETE FROM mail_forward WHERE mail_account_id IN (SELECT mail_account_id FROM (SELECT mail_account_id FROM mail_account WHERE mail_domain_id = 2) t);
DELETE FROM mail_account WHERE mail_domain_id = 2;
DELETE FROM mail_system_alias WHERE mail_domain_id = 2;
DELETE FROM mail_domain WHERE mail_domain_id = 2;
INSERT INTO mail_domain (mail_domain_id, domain_name, default_flag, domain_status, dkim_selector)
VALUES (8, 'example.net', 0, 1, 's202611');

-- 切换默认域：先改旧行再改新行，两步在同一事务里
START TRANSACTION;
UPDATE mail_domain SET default_flag = 0 WHERE mail_domain_id = 1;
UPDATE mail_domain SET default_flag = 1 WHERE mail_domain_id = 8;
COMMIT;
CALL assert_fail((SELECT COUNT(*) FROM mail_domain WHERE default_flag = 1) <> 1, 'A17 默认域应只有 1 个');

-- 其余表各插一行，确认列定义可用
INSERT INTO mail_account_password_history (password_history_id, mail_account_id, password_hash) VALUES (601, 101, '{SHA512-CRYPT}$6$h');
INSERT INTO mail_autoreply (autoreply_id, mail_account_id, enable_flag, reply_subject, reply_body) VALUES (701, 101, 0, '自动回复', '我不在办公室');
INSERT INTO mail_filter_rule (filter_rule_id, mail_account_id, rule_order, rule_name, condition_json, action_json)
VALUES (801, 101, 1, 'newsletters', '[{"field":"from","op":"contains","value":"news"}]', '{"type":"move","folder":"INBOX.News"}');
INSERT INTO mail_outbound_rule (outbound_rule_id, mail_account_id, hourly_recipient_limit, daily_recipient_limit) VALUES (851, 101, 500, 2000);
INSERT INTO mail_setting (setting_id, setting_key, setting_value) VALUES (901, 'default_quota_bytes', '5368709120');
INSERT INTO mail_attachment_temp (attachment_temp_id, owner_user_id, file_name, mime_type, file_size, storage_path, expire_time)
VALUES (1001, 9001, 'a.pdf', 'application/pdf', 1024, 'att/9001/1001.bin', '2026-11-25 00:00:00');
INSERT INTO mail_trash_origin (trash_origin_id, mail_account_id, folder_name, uid_validity, message_uid, origin_folder)
VALUES (1101, 101, 'Trash', 17, 42, 'INBOX');
INSERT INTO mail_idempotency (idempotency_id, owner_user_id, idempotency_key, request_hash, response_body, expire_time)
VALUES (1201, 9001, 'k-1', REPEAT('a', 64), '{}', '2026-11-25 00:00:00');
INSERT INTO mail_delivery_log (delivery_log_id, log_time, mail_direction, queue_id, message_id, sender_address, recipient_address, message_size,
                               delivery_status, dsn_code, bounce_reason, delay_ms, tls_flag, auth_account, client_ip, log_line_hash)
VALUES (1301, '2026-11-24 00:00:00', 2, 'ABC123', '<m1@example.com>', 'zhangsan@example.com', 'peer@example.net', 1234, 1, '2.0.0', NULL, 120, 1, 'zhangsan@example.com', '192.0.2.99', REPEAT('1', 32));
INSERT INTO mail_auth_log (auth_log_id, log_time, mail_address, protocol_type, client_ip, auth_result, fail_reason, log_line_hash)
VALUES (1401, '2026-11-24 00:00:00', 'zhangsan@example.com', 1, '192.0.2.99', 1, NULL, REPEAT('2', 32));
INSERT INTO mail_filter_log (filter_log_id, log_time, message_id, sender_address, rcpt_addresses, spam_score, spam_action, hit_symbols, history_uniq)
VALUES (1501, '2026-11-24 00:00:00', '<m2@example.com>', 'peer@example.net', 'zhangsan@example.com', 2.50, 1, 'BAYES_HAM(-2.5)', 'u1');
INSERT INTO mail_admin_audit_log (admin_audit_id, admin_user_id, action_code, target_type, target_id, target_label, before_json, after_json, client_ip, result_flag)
VALUES (1601, 1, 'account.reset_password', 'mail_account', '101', 'zhangsan@example.com', NULL, '{"reset":true}', '192.0.2.99', 1);
INSERT INTO mail_sync_run (sync_run_id, trigger_type, start_time, end_time, scanned_count, created_count, updated_count, failed_count)
VALUES (1701, 1, '2026-11-24 00:00:00', '2026-11-24 00:00:05', 5, 1, 2, 0);
INSERT INTO mail_admin_batch (admin_batch_id, batch_action, batch_status, request_admin_id, request_json, total_count, done_count, success_count, failed_count, start_time, end_time)
VALUES (1801, 'account.suspend', 2, 1, '{"accountIds":["102"]}', 1, 1, 1, 0, '2026-11-24 00:00:00', '2026-11-24 00:00:01');
INSERT INTO mail_quota_dict (quota_username, quota_bytes, quota_messages) VALUES ('zhangsan@example.com', 1024, 2);
INSERT INTO mail_collector_checkpoint (checkpoint_source, file_identity, file_offset, last_line_hash, cursor_value)
VALUES ('postfix', REPEAT('a', 64), 4096, REPEAT('b', 64), NULL), ('rspamd_history', NULL, 0, NULL, '2026-11-24T00:00:00Z');

UPDATE mail_domain SET dns_check_status = 2,
  dns_check_detail = JSON_ARRAY(JSON_OBJECT('item', 'mx', 'status', 'pass', 'message', '', 'time', '2026-11-24 00:00:00'),
                                JSON_OBJECT('item', 'dmarc', 'status', 'fail', 'message', 'TXT 记录不存在', 'time', '2026-11-24 00:00:00'))
WHERE mail_domain_id = 1;
CALL assert_fail((SELECT JSON_LENGTH(dns_check_detail) FROM mail_domain WHERE mail_domain_id = 1) <> 2, 'A18 dns_check_detail 应有 2 项');

DROP PROCEDURE assert_fail;
SELECT 'ALL CHECKS PASSED' AS result;
