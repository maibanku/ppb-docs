-- 一次性验证用：每条语句都应被数据库拒绝。配合 mysql --force 执行，数输出里的 ERROR 行数。
USE ppb_mail;

-- N1 账号状态取值越界
INSERT INTO mail_account (mail_account_id, user_id, mail_domain_id, account_local, mail_address, account_status, password_hash, quota_bytes)
VALUES (9901, 9901, 1, 'bad01', 'bad01@example.com', 4, 'x', 1);
-- N2 同一用户第二个邮箱
INSERT INTO mail_account (mail_account_id, user_id, mail_domain_id, account_local, mail_address, account_status, password_hash, quota_bytes)
VALUES (9902, 9001, 1, 'bad02', 'bad02@example.com', 1, 'x', 1);
-- N3 主地址与已有主地址重复
INSERT INTO mail_account (mail_account_id, user_id, mail_domain_id, account_local, mail_address, account_status, password_hash, quota_bytes)
VALUES (9903, 9903, 1, 'zhangsan', 'zhangsan@example.com', 1, 'x', 1);
-- N4 第二个默认域
INSERT INTO mail_domain (mail_domain_id, domain_name, default_flag, domain_status, dkim_selector)
VALUES (99, 'example.edu', 1, 1, 's202611');
-- N5 别名地址重复
INSERT INTO mail_alias (mail_alias_id, mail_account_id, alias_address, alias_source)
VALUES (99201, 104, 'zhang.san@example.com', 1);
-- N6 同一域内 DKIM 选择器重复
INSERT INTO mail_domain_dkim_key (dkim_key_id, mail_domain_id, dkim_selector, dkim_key_path, dkim_public_record, active_flag)
VALUES (9911, 1, 's202611', 'x', 'x', 0);
-- N7 外发权限取值越界
UPDATE mail_account SET outbound_perm = 2 WHERE mail_account_id = 101;
-- N8 同一邮箱第二条转发
INSERT INTO mail_forward (mail_forward_id, mail_account_id, forward_address, keep_copy_flag, enable_flag, verify_status, forward_source)
VALUES (99401, 101, 'again@example.com', 1, 1, 2, 2);
-- N9 名单类型越界
INSERT INTO mail_blocklist (blocklist_id, list_type, block_type, block_value, creator_admin_id)
VALUES (99501, 3, 1, 'x@example.com', 1);
-- N10 同一来源日志行重复入库
INSERT INTO mail_delivery_log (delivery_log_id, log_time, mail_direction, delivery_status, log_line_hash)
VALUES (99601, '2026-11-24 00:00:00', 1, 1, REPEAT('9', 32)),
       (99602, '2026-11-24 00:00:00', 1, 1, REPEAT('9', 32));
-- N11 第二行主机名登记
INSERT INTO mail_endpoint (mail_endpoint_id, public_hostname, public_ip)
VALUES (2, 'mail2.example.com', '192.0.2.11');
-- N12 同一邮箱第二条自动回复
INSERT INTO mail_autoreply (autoreply_id, mail_account_id, enable_flag, reply_subject, reply_body)
VALUES (99701, 101, 0, 'x', 'x');
-- N13 同一幂等键
INSERT INTO mail_idempotency (idempotency_id, owner_user_id, idempotency_key, request_hash, response_body, expire_time)
VALUES (99801, 9001, 'k-1', REPEAT('b', 64), '{}', '2026-11-25 00:00:00');
