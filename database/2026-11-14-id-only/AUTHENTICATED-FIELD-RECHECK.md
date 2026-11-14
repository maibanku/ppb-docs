# 认证后字段返回复核（2026-11-14）

## 执行方式

对隔离网关8081执行真实注册、密码登录、组织选择、管理会话建立；使用持有凭据的成员/管理请求执行角色、成员、群、文件、Camera模板生命周期。测试使用本地真实MySQL克隆、独立Redis及本地文件服务；未以未登录401作为功能通过。

独立请求钩子递归解析每个JSON对象及数组，检查字段名中的biz_key/bizKey及deleted_time/DeletedTime等变体。仅检查字段名，不误删历史消息正文中出现的文字；报告不保存响应中的密码或token。

## 实测结果

- 请求总数62。
- 携带登录凭据53次，其中HTTP2xx共39次（2xx数量不等于业务全部成功数量）。
- 旧字段返回0处。
- 认证请求5xx为0。
- 已覆盖的角色/成员/群/文件/模板操作不能代表全部244入口完成验收。

证据：`/Users/pipi-ban/Documents/Codex/2026-10-24/du/work/id-only-20261114/acc-stack/authenticated-field-results.json`。

## 源码复核发现与处理

管理端菜单元数据旧名称改为menuKey/parentMenuKey，与IAM既有语义菜单标识一致，无新增实体UUID字段；chat提交4171c131已推送，类型检查及7项授权/文件入口测试通过。

仍发现桌面原生通话模块存在旧序列化键与校验，已明确交由运行中的Claude Lead修复并检查前端/原生接口一致性。SQLite历史迁移必须保留数据安全，不能用直接删迁移代码来凑字段清零。

验收工具补充全局5xx失败和旧JSON字段失败规则；重复调用非成功响应必须有明确端点预期，不能无条件判幂等通过。全量场景尚在推进，不声明全部完成。

## 深入复核追加修复（同日20:38）

此前扫描未包含MFA已启用分支及JWT内部字段，不能据此认定全量清理完成。本轮实际发现并修复：

1. IAM MFA绑定与状态响应仍使用factor_biz_key，已改为factor_id；提交23e55e9已推送、更新本地运行IAM及隔离IAM。
2. MemberMinter仍签发冗余biz_key JWT claim。已删除Claims字段及签发赋值，消费者只读取标准sub；冲突旧claim不覆盖sub。提交74e02c8已推送，IAM运行二进制已更新。
3. endpoint-audit旧字段递归检查与5xx/幂等误判修复da0f1cb已推送，工具测试通过。

更新后的隔离栈再次执行62请求/53认证请求/39认证2xx，JSON及嵌入JWT扫描旧字段0。另真实密码登录→MFA绑定→TOTP确认→启用状态查询全部200；另真实成员登录→组织选择签发的2种JWT均无旧claim，sub/sid均为十进制。

证据补充：acc-stack/authenticated-mfa-results.json、authenticated-jwt-results.json。MFA测试只变更隔离测试账户。

JWT改动后全量Go回归有1项定时窗口测试TestCoalesceBurst出现调度波动（合并次数2而预期1），该包独立重跑通过；其余64包通过。保留首轮失败日志jwt-final-full-go.log及重跑日志jwt-ws-recheck.log，不抹除该波动。

桌面原生通话/退役待办等剩余清理由Claude继续处理，需等待原生编译和回归后才能给出全部完成结论。

更新后再次认证复测完成：53认证请求旧字段0；MFA5请求全部200；JWT2种解析均无biz_key。以上均为本轮实际执行，非历史推断。unused idOrKey回退已删除并通过IM handler回归，ff056d4已推送。

## 实际存储补查

MySQL13个JSON/文本列发现41条审计JSON含旧字段名：IAM39条、IM2条。已先将原文写入私有0600归档，再按原文CAS转换；11条引用映射为真实ID，30条历史引用无法映射，user_id置null并显式标记unresolved_historical_reference，原引用只在离线归档保留。没有删除审计事件。转换后复扫旧JSON字段0；实际Camera SQLite51个文本/JSON列同样0。

桌面清理代码独立Rust回归207通过、0失败、2忽略。但实际用户数据目录中6个历史SQLite仍有36个旧列，含2条草稿（待发队列均0），已交Claude执行备份和无损迁移。此部分未处理前不能声称所有本地数据库清理完成；此前“数据库清零”仅指服务端MySQL与Camera SQLite。
