# P2c 子任务简报：IM manage 契约 + 承接装配（Lead 集成用）

范围：server-im/api/manage-http.json（39 条 manage 路由）+ main.go manage 装配 + 审计/公告 sink。
不动：server-gateway/**、server-pkg/**（除只读）、server-iam/**、server-file/**。

## 契约 schema（Lead 在 servicehttp/contracts.go 扩展后生效）

Contract: {service: "server-im", identity: "manage", routes: [...]}
Route: {
  method, path, rpc, operator, bindings{qName:{field,kind}}, request, response,
  policy: {kind: self|app_perm|super_gov, appKey, perm, resolver?},
  audit?: {action, targetType, targetField?},   // 成功后审计（operator=认证主体）
  broadcast?: "announcement.publish"            // 成功后公告广播
}

## 路由表（39 条；政策与绑定逐字来自 server-gateway/proxy/registry_manage.go）

UserOrg 面（29）：
| method path | policy | rpc | 绑定（query/path→field） | audit |
|---|---|---|---|---|
| GET /api/v1/manage/members | chat member.read | /user.UserService/ListMembers | q→Q,deptBizKey→DeptBizKey,tenantBizKey→TenantBizKey,page→Page(page),pageSize→Page.PageSize,startTime→StartTimeUnix(pos64),endTime→EndTimeUnix,sortBy→SortBy,sortOrder→SortOrder | - |
| POST /api/v1/manage/members | chat member.create | CreateMember | body only | - |
| PUT /api/v1/manage/members | chat member.update | UpdateMember | body only | - |
| DELETE /api/v1/manage/members | chat member.offboard | DeleteMember | bizKey→BizKey | - |
| POST /api/v1/manage/members/import | chat member.create | ImportMembers | body only | - |
| POST .../members/{memberBizKey}/disable | chat member.disable | DisableMember | path memberBizKey→MemberBizKey | - |
| POST .../enable | chat member.disable | EnableMember | 同上 | - |
| POST .../reset-password | chat member.update | ResetMemberPassword | path 同上（body 可有新密码） | - |
| POST .../unlock | chat member.update | UnlockMember | path 同上 | - |
| GET .../members/{memberBizKey}/sessions | chat member.read | AdminListMemberSessions | path→MemberBizKey | - |
| POST .../sessions/revoke-all | chat member.disable | AdminRevokeAllSessions | path 同上 | - |
| POST .../sessions/{sessionBizKey}/revoke | chat member.disable | AdminRevokeSession | memberBizKey+sessionBizKey | - |
| POST /api/v1/manage/members/import | （重复，忽略） | | | |
| GET .../members/{memberBizKey}/account | chat member.read | AdminGetMemberAccount | path | - |
| GET .../members/{memberBizKey}/profile-view | chat member.read | AdminGetMemberProfileView | path | - |
| GET .../members/{memberBizKey}/roles | chat role.read | GetMemberRoles | path | - |
| PUT .../members/{memberBizKey}/roles | chat role.assign | AssignMemberRoles | path（roleBizKeys 在 body） | - |
| GET /api/v1/manage/sessions | chat member.read | AdminListSessions | state→State,page→Page | - |
| POST /api/v1/manage/sessions/{sessionBizKey}/revoke | chat member.disable | AdminRevokeSessionByKey | path sessionBizKey | - |
| GET /api/v1/manage/roles | resolver=roles-scope | ListRoles | roleScope→RoleScope,appKey→AppKey | - |
| GET /api/v1/manage/roles/{roleBizKey}/members | chat role.read | AdminListRoleMembers | path | - |
| GET /api/v1/manage/friends | chat friend.read | AdminListFriends | memberBizKey→MemberBizKey,page | - |
| POST /api/v1/manage/friends/force-unfriend | chat friend.manage | AdminForceUnfriend | body | friend.relation.admin/chat_friend_relation/peerBizKey |
| GET /api/v1/manage/friend-requests | chat friend.read | AdminListFriendRequests | memberBizKey,direction(int32),page | - |
| GET /api/v1/manage/settings | chat settings.read | AdminGetPlatformSettings | - | - |
| PUT /api/v1/manage/settings | chat settings.update | AdminSetPlatformSetting | body | platform.setting.admin/platform_setting/key |
| GET /api/v1/manage/audit/chat | chat audit.read | AdminListAudit | actorKey,actionCode,startTime,endTime,page | - |
| POST /api/v1/manage/announcements | chat announcement.publish | PublishAnnouncement | body | broadcast=announcement.publish |
| GET /api/v1/manage/announcements | chat announcement.read | ListAnnouncements | status(int32),page,pageSize,startTime,endTime,sortBy,sortOrder | - |
| POST /api/v1/manage/announcements/{bizKey}/revoke | chat announcement.revoke | RevokeAnnouncement | path bizKey→BizKey | - |

IM 面（10）：
| GET /api/v1/manage/groups | chat group.read | /im.IMService/AdminListGroups | q,status(int32),page,pageSize,startTime,endTime,sortBy,sortOrder | - |
| GET /api/v1/manage/groups/{groupBizKey}/members | chat group.read | AdminListGroupMembers | path groupBizKey | - |
| POST /api/v1/manage/groups/dissolve | chat group.dissolve | AdminDissolveGroup | body | group.dissolve.admin/im_group/groupBizKey |
| POST /api/v1/manage/groups/transfer-owner | chat group.transfer | AdminTransferOwner | body | group.transfer.admin/im_group/groupBizKey |
| POST /api/v1/manage/messages/recall | chat message.recall | AdminRecallMessage | body | im.recall.admin/im_message/msgBizKey |
| GET /api/v1/manage/messages/{msgBizKey} | chat message.read | AdminGetMessage | path | - |
| GET /api/v1/manage/messages | chat message.read | AdminListMessages | convBizKey,senderBizKey,msgType(i32),msgStatus(i32),startTime,endTime,page,pageSize | - |
| GET /api/v1/manage/chat-files | chat message.read | AdminListChatFiles | convBizKey,senderBizKey,fileBizKey,fileName,msgType,startTime,endTime,page,pageSize | - |
| GET /api/v1/manage/im/messages/content | chat message.content.read | AdminListMessageContent | convBizKey,senderBizKey,msgType,msgStatus,startTime,endTime,page,pageSize | - |
| GET /api/v1/manage/conversations/resolve | chat message.read | AdminResolveConversation | memberABizKey,memberBBizKey | - |

operator 字段：全部 req 的 operatorBizKey（proto 字段名核实——UserOrg 面多为 operatorBizKey，IM 面核实 AdminListGroupsReq 无 operator 字段！→ 契约 Operator 留空则无法注入 actor：IM 面 rpc 的 operator 字段名按 proto 实际字段核对，缺 operator 字段的路由 Operator=""，actor 只走 x-ppb-actor metadata）。

## 其他要点
- IM main.go：manage 面挂载 mux.Handle("/api/v1/manage/", manageAuth.Wrap(manageHandler))，manageHandler=servicehttp.NewManageHandler(contract, guard, localManageConn, sinks...)；guard=authzguard.New(AdminAuthz/RbacVersion via iamConn 的 user client)。
- AdminMethodPerms 补 /im.IMService/AdminListGroupMembers {chat, group.read}。
- 审计 sink：UserIam.AdminAudit（iamConn）成功后写；失败 warn 不回滚。
- 公告 sink：eventmq publisher topic announcement.publish（payload 同旧 hub 广播字段）。
- 匿名 2 条（register/send-code、invitations/send-code）→ 独立 contract identity=anonymous（P2b 契约解析已支持）；register/accept 两条继续走网关（P3 IAM 签发）。
- 测试：契约 Parse 通过 + 401/403/503 负控 + policy 矩阵（roles-scope resolver）。
