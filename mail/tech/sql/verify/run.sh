#!/bin/bash
# 一次性验证：在无网络的临时 MySQL 8.0 容器里执行 ../schema.sql，
# 再跑样例数据断言（seed_assert.sql）和负向约束测试（negative.sql）。结束后删除容器。
#
# 用法：bash run.sh    需要本机有 Docker 和本地镜像 mysql:8.0。不发布端口，不联网，不碰任何现有数据库。
# 通过的标志：第 1 段 exit=0；第 2 段 exit=0 且输出 ALL CHECKS PASSED；第 3 段 errors=13。
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$DIR/../schema.sql"
NAME=ppbmail-schema-check-$$
OUT="${TMPDIR:-/tmp}/ppbmail-schema-check-out"
mkdir -p "$OUT"
PW=$(openssl rand -hex 24)

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1; }
trap cleanup EXIT

docker run -d --rm --name "$NAME" --network none --tmpfs /var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD="$PW" mysql:8.0 >/dev/null 2>&1 || { echo "FAIL: docker run"; exit 2; }

# 等数据库就绪
for i in $(seq 1 90); do
  if docker exec -e MYSQL_PWD="$PW" "$NAME" mysqladmin -uroot ping --silent >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
# 官方镜像初始化后会重启一次，再确认一次连接稳定
sleep 5
for i in $(seq 1 30); do
  if docker exec -e MYSQL_PWD="$PW" "$NAME" mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 2
done

echo "== version"
docker exec -e MYSQL_PWD="$PW" "$NAME" mysql -uroot -N -e 'SELECT VERSION(), @@character_set_server, @@collation_server'

echo "== 1. schema.sql"
docker exec -i -e MYSQL_PWD="$PW" "$NAME" mysql -uroot < "$SCHEMA" > "$OUT/schema.log" 2>&1
rc=$?
echo "exit=$rc"; [ -s "$OUT/schema.log" ] && head -20 "$OUT/schema.log"

echo "== objects（期望 24 表 8 视图，single_word_columns=0，auto_inc=0，fk=0）"
docker exec -e MYSQL_PWD="$PW" "$NAME" mysql -uroot -N -e "SELECT table_type, COUNT(*) FROM information_schema.tables WHERE table_schema='ppb_mail' GROUP BY table_type; SELECT CONCAT('columns=', SUM(cnt), ' single_word_columns=', SUM(single)) FROM (SELECT c.table_name, COUNT(*) cnt, SUM(LENGTH(c.column_name)-LENGTH(REPLACE(c.column_name,'_',''))=0) single FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name WHERE t.table_schema='ppb_mail' AND t.table_type='BASE TABLE' GROUP BY c.table_name) x; SELECT CONCAT('auto_inc=', COUNT(*)) FROM information_schema.columns WHERE table_schema='ppb_mail' AND extra LIKE '%auto_increment%'; SELECT CONCAT('fk=', COUNT(*)) FROM information_schema.referential_constraints WHERE constraint_schema='ppb_mail'"

echo "== 2. seed + assertions"
docker exec -i -e MYSQL_PWD="$PW" "$NAME" mysql -uroot < "$DIR/seed_assert.sql" > "$OUT/seed.log" 2>&1
rc=$?
echo "exit=$rc"; tail -15 "$OUT/seed.log"

echo "== 3. negative constraints（期望 13 条都被拒绝）"
docker exec -i -e MYSQL_PWD="$PW" "$NAME" mysql -uroot --force < "$DIR/negative.sql" > "$OUT/negative.log" 2>&1
errs=$(grep -c '^ERROR' "$OUT/negative.log")
echo "errors=$errs"
grep '^ERROR' "$OUT/negative.log" | cut -c1-150

echo "== 4. 被拒绝的语句不应留下改动（期望 accounts=5 domains=3 default_domains=1 outbound_perm_101=1）"
docker exec -e MYSQL_PWD="$PW" "$NAME" mysql -uroot -N -e "SELECT 'accounts', COUNT(*) FROM ppb_mail.mail_account UNION ALL SELECT 'domains', COUNT(*) FROM ppb_mail.mail_domain UNION ALL SELECT 'default_domains', COUNT(*) FROM ppb_mail.mail_domain WHERE default_flag=1 UNION ALL SELECT 'outbound_perm_101', outbound_perm FROM ppb_mail.mail_account WHERE mail_account_id=101"

echo "== done（完整输出在 ${OUT}）"
