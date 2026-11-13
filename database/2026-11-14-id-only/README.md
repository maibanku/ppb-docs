# 单一 ID 与删除字段改造

用户要求：移除全部冗余 xxx_biz_key 和通用 deleted_time。实体只保留数值主键，接口大整数按字符串传输；deleted_flag 保留。OIDC pairwise subject、消息幂等请求键、事件去重标识、邀请凭证等保留独立业务语义，不能与实体主键混为一谈。

## 当前完成的删除时间改造

- 公共模型、各服务软删/恢复读写、初始化 SQL 已移除通用删除时间；现存数据库尚未删列。
- 文件回收站改为 purge_after 清理期限；更新其他字段不会改变保留期，恢复后清空。未知期限的回收站文件仍保护其物理内容。
- 回收站协议新增 purgeAfterUnix（protobuf tag 8），废弃字段 tag 6 不复用；文件管理端和聊天管理端显示清理期限。
- MySQL 升级工具：ppb-base/server-pkg/cmd/remove-deletion-time，默认 dry run。执行前停写并全库备份，工具额外保存删除时间列的回退快照，再执行 DDL。
- 后端现有测试及补充回归通过；前端 12+84 测试、两端类型检查与构建通过。本地 Docker MySQL 8 隔离数据库完成迁移及回退验证，业务数据未动。

## 尚未完成的 ID 迁移

biz_key→ID 仍在实现，不能宣称全量完成。账号 user_id 与组织成员 chat_membership_id 是不同实体，成员 token 保留组织成员范围；IM 既有保存 user_id 的关联列必须经过显式边界转换，不能直接重新解释为成员 ID。每个服务实例的雪花节点号需要独立配置。

在接口、服务端、客户端待发队列/缓存和历史引用映射验证完成后，才协调现有库切换。迁移必须保留数据并提供回退，不能清空数据库或把 UUID 复制到改名字段规避目标。

详细实时执行状态：/Users/pipi-ban/Documents/Codex/2026-10-24/du/work/id-only-20261114/status.md；删除时间证据与检查点在同目录 deletion-status.md。
