---
name: ppb-portal-card-width
description: ppb-base iam-web 门户卡片 2026-11-05 定宽 400px（去 min）已提交 699e8fa；用户实测三页同宽后的裁决
metadata:
  node_type: memory
  type: project
  originSessionId: 2a7acd6e-b7f5-49d1-9446-f6b9aa8c9e62
  modified: 2026-11-04T23:46:28.050Z
---

ppb-base main `699e8fa style(iam): 门户卡片定宽 400px——去除 min() 收缩保护`（2026-11-05，未 push）：iam-web `.card` 由 `min(400px,100%)` 改为固定 `width: 400px`——用户明确要求去除 min，窄视口横向溢出属接受的取舍。背景：无头 Chromium 实测 /login、/register、/forgot 卡片本就同为 400px（输入 334px），"宽度不一样"的感知实为与桌面端 320px 登录窗的对比；用户选择整体加宽三页又最终回到 400 定宽。测量脚本模式：`/tmp/portal-width.mjs`（Chromium CDP 直连 Runtime.evaluate 量 getBoundingClientRect，无新依赖）；8240 是 vite dev，改源码即生效。

**Why:** 避免下次再把"门户三页宽度不一致"当 bug 排查——静态与实测均一致，差异来自跨端对比。
**How to apply:** 涉及门户视觉对齐时先实测（portal-width 模式），跨端宽度统一需求先确认锚点（桌面窗 vs 门户卡）。相关 [[chat-desktop-rewrite-progress]]。
