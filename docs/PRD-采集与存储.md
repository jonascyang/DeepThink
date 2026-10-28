# 个人活动复盘 · 采集与存储 PRD

**版本：** PRD v0.1  
**状态：** 草案  
**Owner：** Jonas C（United Stable / UTechStables · @jonasCyang）  
**Author：** Engineer  
**日期：** 2026-10-28 Asia/Shanghai  
**范围：** 采集与存储（v1）；复盘 UI / LLM 摘要 out of scope  
**平台：** 仅 macOS；iPhone 已放弃  

v1 只解决活动数据的采集与本地存储：签名 Swift 边沿记录器 + Python 幂等摄入 + 单机 SQLite。复盘 UI 与 LLM 摘要不在本期范围，但存储形态必须能支撑日后复盘。

> **产品一句话**  
> 这是 Jonas 个人用的 macOS 本地活动复盘底座：只记「操作系统会忘掉」的焦点/AFK/睡眠边沿，其余从 Claude、Codex、Chrome、Biome 已有磁盘日志按游标摄入。数据落本机一份 SQLite，采集时脱敏，无截图、无击键、无剪贴板、无网络、无 iCloud。本期交付采集与存储；复盘界面与 LLM 摘要留给后续版本，但库里的数据必须够用。

本 PRD 面向产品决策，不复述实现细节。技术数字来自已完成的 Linux 原型与源码调研。相关文档：技术最终方案页（红队后 v3）、早期可行方案页。

- 活动采集与存储：最终方案（技术页）— https://cursor.com/canvas/store-53dd1173-d034-4a8e-bfd1-d140b10dbc3c/f863315c-cbbb-470e-9caa-58795ece6c8a
- 个人活动复盘：macOS 可行方案（早期）— https://cursor.com/canvas/store-53dd1173-d034-4a8e-bfd1-d140b10dbc3c/f13d760f-b318-4ba4-82ea-b623dec07337

## 目录

1. [文档信息](#1-文档信息)
2. [背景与问题](#2-背景与问题)
3. [目标与非目标](#3-目标与非目标)
4. [用户与场景](#4-用户与场景)
5. [成功标准](#5-成功标准)
6. [产品原则](#6-产品原则)
7. [功能需求](#7-功能需求)
8. [非功能需求](#8-非功能需求)
9. [隐私与数据采集范围](#9-隐私与数据采集范围)
10. [系统架构](#10-系统架构)
11. [权限与安装](#11-权限与安装)
12. [里程碑](#12-里程碑)
13. [开放问题](#13-开放问题)
14. [风险与依赖](#14-风险与依赖)
15. [附录](#15-附录)

## 1. 文档信息

| 项 | 内容 |
| --- | --- |
| 版本 | PRD v0.1 |
| 状态 | 草案 |
| Owner | Jonas C（United Stable / UTechStables · @jonasCyang） |
| Author | Engineer |
| 日期 | 2026-10-28 Asia/Shanghai |
| 范围 | 采集与存储（v1）；复盘 UI / LLM 摘要 out of scope |
| 平台 | 仅 macOS；iPhone 已放弃 |

## 2. 背景与问题

Jonas 是加密研究员，日常并行使用多个 AI Agent（Claude Code、Codex、Claude Desktop、Muse、Chrome 网页研究、Grok Bot 助手等）。一天结束后，没有统一、可信、本地的活动时间线：哪段时间在哪个 App、哪些 Agent 会话、浏览了哪些研究域名、何时离开键盘、睡眠/锁屏造成了哪些空隙。

现有开源方案要么依赖周期截图（Screenpipe / Dayflow / Rewind 类，违背轻量与隐私约束），要么主库模型不适合幂等摄入 Agent 日志（ActivityWatch heartbeat 会改写末行、无去重键）。自研若从零做全栈又过重。

因此 v1 先只做「采集与存储」：把可验证的信号以优雅、可重放、可脱敏的方式落盘。没有干净数据，复盘 UI 与 LLM 摘要只会放大噪声与隐私风险。

## 3. 目标与非目标

### 目标（v1）

1. 在授权后，可靠记录前台 App 切换、窗口标题（受 allowlist 约束）、AFK、睡眠/唤醒/锁屏边沿。
2. 幂等摄入 Claude Code JSONL、Codex rollout（含归档与 `.zst`）、Chrome History（多 Profile、不含无痕）。
3. 可选读取 Biome `App.InFocus`（仅 `local/`）作双见证，缺口写入 `witness_gaps`，供复盘可见。
4. 采集时脱敏：密钥、助记词、URL query、敏感 App 标题不落明文。
5. 崩溃后可从游标重放：不丢、不重复；单机本地 SQLite WAL，无网络、无 iCloud。
6. 存储形态足以支撑日后「日复盘」：焦点 ∩ ¬AFK 时间线、Agent 会话标记、域名 Top-N、健康/缺口警告。

### 非目标（v1 明确不做）

- 复盘 UI、菜单栏今日分钟看板、LLM 中文日摘要（可作为后续成功标准的消费者，但不交付）。
- 周期截图、OCR、屏幕录制、击键监听、剪贴板监听。
- iPhone / 跨设备账号同步 / iCloud。
- Mac App Store 分发；Chrome 扩展实时 URL（推迟到 v2）。
- 解密 ChatGPT Mac 本地缓存；把 Claude Desktop / Muse / Grok Bot 当作有完整本地日志的一等解析源。
- EndpointSecurity、Unified Log 主路径、osquery 主机遥测。

## 4. 用户与场景

| 项 | 内容 |
| --- | --- |
| Persona | Jonas · 加密研究员 · 多 Agent 重度用户 · 重视准确与隐私 |
| 沟通 | 产品与文档用中文 |
| 设备 | 一台或多台 Mac；每机一库，手动拷贝备份 |

| 场景 | 用户要做什么 | 系统必须提供的数据 |
| --- | --- | --- |
| 晚间复盘 | 回顾今天 Agent 会话与浏览器研究 | 焦点边沿→时长、Claude/Codex 会话瘦字段、Chrome 域名/标题（已脱敏）、AFK 排除 |
| 检测离开 | 确认「看起来在工作」的时段是否其实 AFK | 180s 无输入 → AFK 边沿；复盘时焦点 ∩ ¬AFK |
| 崩溃恢复 | 守护进程或摄入脚本异常退出后继续用 | 游标 + `UNIQUE(dedupe_key)`；半行不推进；重放无重复 |
| 发现静默缺口 | 怀疑采集挂了但白天没注意 | Biome 双见证 vs 本机焦点 → `witness_gaps` 在复盘可见 |
| 敏感工作日 | 当天打开过钱包 / 1Password / 银行 | 这些 App 只记 bundle 名，不记窗口标题；密钥形态写入前替换 |

## 5. 成功标准

下列指标可验收。验证标签：**Linux 已验** = 本盒 Python 原型与测试；**Mac 未验** = 依赖真机 NSWorkspace / AX / TCC / FDA，尚未跑过。

| 标准 | 度量 | 验证 |
| --- | --- | --- |
| 焦点边沿延迟 | 授权后 App 切换边沿记录延迟 ≤ 1s（事件驱动，非轮询） | Mac 未验 |
| 零明文密钥 | 红队用例：API key / 助记词 / URL token 不出现在 db 与 `-wal` 字节中 | Linux 已验 |
| 崩溃可重放 | 中断后从游标续读：无丢失、无重复（半行不消费） | Linux 已验 |
| 空闲资源 | 无焦点变化时近零 CPU；无截图路径；常驻进程仅边沿 | 部分已验 |
| 磁盘体量 | Linux 实测：3,000 焦点边沿 + 120 tick ≈ 905 KB；真机长跑未测 | 部分已验 |
| 双见证缺口 | 守护进程静默死亡时段在 `witness_gaps` 可见（Biome 可用时） | 部分已验 |
| 无痕不入库 | Incognito / 无痕 / Private Browsing 标题标记 → 不落详细 URL/标题 | Linux 已验 |
| 测试门禁 | 存储/摄入/脱敏/迁移相关单测 58/58 通过（Linux, Python 3.13.5） | Linux 已验 |

## 6. 产品原则

1. **只常驻 OS 会忘掉的信号。** 焦点切换、标题、AFK、睡眠/锁屏必须边沿记录；磁盘上已有的日志只做定时摄入。
2. **一个 Event 模型。** 所有来源统一为 `Event(ts_utc_ms, source, kind, dedupe_key, payload)`；时长读时计算，不存易错区间。
3. **追加 + 幂等游标。** `INSERT OR IGNORE`；事件与游标同一事务；崩溃 = 从游标重放。
4. **采集时隐私。** 脱敏发生在写入之前，而不是复盘导出时才想起来。
5. **本地唯一。** 无网络客户端、无账号同步、无 iCloud；备份靠 `VACUUM INTO` / 手动拷库。
6. **优先开源先例，拒绝重方案。** 借 ActivityWatch 的 AX 思路（MPL-2.0），不 fork 其主库；排除截图类与击键类项目。
7. **准确优于速度；诚实标注未验。** Mac 行为一律标「真机待验」；不编造资源数字。

## 7. 功能需求

| 编号 | 优先级 | 需求 | 验收要点 |
| --- | --- | --- | --- |
| FR-01 | P0 | 焦点边沿：前台 App 切换记 bundle + 显示名 | NSWorkspace 通知驱动；切换边沿 ±1s（Mac 未验）；存边沿非 heartbeat 区间 |
| FR-02 | P0 | 窗口标题（受 allowlist）：AX 可读则记，敏感 App 只记 App 名 | `drop_detail_bundle_ids` 命中时 payload 无 title；Electron 空标题记缺口 |
| FR-03 | P0 | AFK：`CGEventSource` 空闲秒数，阈值 180s | `afk_start` / `afk_end` 边沿；无需 TCC；不监听击键 |
| FR-04 | P0 | 睡眠 / 唤醒 / 锁屏边沿 | `willSleep` / `didWake` / `screenIsLocked`；唤醒清除 asleep 与 afk 假设 |
| FR-05 | P0 | Claude Code 摄入：`~/.claude/projects` JSONL | 按 sessionId+uuid 去重；瘦 payload（默认不存 prompt）；日至少一次 |
| FR-06 | P0 | Codex 摄入：rollout JSONL + archived + `.jsonl.zst` | 顶层 timestamp；uuid 去重；`.zst` 需 Python≥3.14，否则 health=warn |
| FR-07 | P0 | Chrome History：多 Profile，copy-then-read | dedupe 含 profile；游标可回退；无痕不采；通常无需 FDA（Mac 未验） |
| FR-08 | P1 | Biome 见证：只读 `local/` `App.InFocus` | 与焦点对齐写入 `witness_gaps`；`remote/` 忽略；macOS 26 是否仍写待验 |
| FR-09 | P0 | 采集时脱敏 | 共享 `redact_rules.json`；8+ 密钥类、BIP39≥12、URL query 丢弃；db/WAL 无明文 |
| FR-10 | P1 | 缺口 / 健康报告 | daemon 超 10 分钟无 tick → unknown；权限拒绝 → health；双见证缺口可查 |
| FR-11 | P1 | 导出与备份 | `VACUUM INTO` 一致性快照；按时间段导出 JSONL |
| FR-12 | P2 | 保留策略 | `purge_before` 同时清 events 与 `witness_gaps`，游标不动；保留期由 Jonas 选定 |

## 8. 非功能需求

| 类别 | 要求 | 备注 |
| --- | --- | --- |
| 性能 | 事件驱动边沿；AFK 仅低频调度检查；空闲近零 CPU/RAM | Linux 写入约 71 µs/边沿；Mac Instruments 待测 |
| 可靠性 | WAL + `BEGIN IMMEDIATE`；schema 前向迁移；拒绝打开比代码新的库 | `PRAGMA user_version = 2` |
| 隐私 / 安全 | 无击键/截图/剪贴板/OCR；写入前脱敏；建议 FileVault；DB 加密可选后续 | 见第 9 节 |
| 打包 | 签名 `.app`（`LSUIElement`）+ `SMAppService` 登录项；Accessibility 授给 `.app` 而非 Python | Swift 骨架未编译（Mac 未验） |
| 网络 | v1 零网络依赖；无遥测、无自动更新通道要求 | 硬约束 |
| FDA | 仅 Biome 见证可能需要；Chrome History 通常不需要 | 两者均 Mac 未验 |

## 9. 隐私与数据采集范围

> **直接回答隐私顾虑**  
> 不记击键、不截图、不读剪贴板、不做 OCR。密钥与助记词在写入前替换；1Password / 钱包 / 银行等敏感 App 只记应用名不记标题；无痕窗口不采详细内容。库文件建议放在 FileVault 保护的磁盘上；可选库加密留待后续决策。

| 记什么 | 不记什么 |
| --- | --- |
| 前台 App bundle 与显示名、切换时刻 | 键盘内容、鼠标轨迹、剪贴板 |
| 窗口标题（非敏感 App、已脱敏） | 屏幕像素、OCR 文本、录屏 |
| AFK 起止（空闲秒数阈值） | 具体按了哪些键 |
| 睡眠 / 唤醒 / 锁屏边沿 | 锁屏后的任何窗口内容 |
| Claude/Codex 会话元数据（id、时间、cwd、计数） | 默认不存完整 prompt/response |
| Chrome 访问 URL（去 query）+ title | 无痕/Private 详细内容；SPA 未进 History 的软导航（v1） |
| Biome 焦点 in/out（可选见证） | Biome `remote/`（其他设备同步来的） |

### 脱敏规则（写入前）

- 密钥形态：Anthropic / OpenAI / GitHub / AWS / Slack / JWT / 64-hex 私钥 / xprv·WIF / PEM 私钥 → 替换为占位符。
- BIP39：连续 ≥12 个词表词整段丢弃（宁可多删；相邻词表词可能被误伤，已接受）。
- URL：默认丢弃 query/fragment；`url_keep_query_hosts` 为空。
- 敏感 App（当前草案）：1Password、Bitwarden、钥匙串、Passwords、KeePassXC、Ledger Live、Trezor Suite — 只记 App 名。
- 标题含 Incognito / 无痕 / Private Browsing → 不落详细字段。

### 残余风险（诚实）

- 非敏感 App 的窗口标题仍可能含项目名、人名或未匹配规则的秘密形态。
- Swift 端 BIP39 尚未移植，骨架对疑似长标题 fail-closed（未测）。
- 未开 FileVault 时，本地 db 物理可读；库级加密（如 SQLCipher）为开放问题。
- Accessibility 若误授给 Python/终端，其他脚本可能继承（故必须签名 `.app`）。

## 10. 系统架构

```
Swift 边沿记录器（签名 .app · SMAppService）
        │ 边沿
        ▼
采集时脱敏（redact_rules.json） ──► SQLite WAL（每台 Mac 一库 · device_id）
        ▲                                    │
        │                                    ├──► witness_gaps（双见证缺口）
Python 定时摄入（游标 · 同事务提交）           │
        ▲                                    ▼
磁盘已有日志（Claude · Codex · Chrome History）   日后复盘消费者（读时算时长 · 非 v1 UI）

Biome App.InFocus（只读 local/）──对齐──► witness_gaps
```

| 项 | 内容 |
| --- | --- |
| Event | `ts_utc_ms` · `source` · `kind` · `dedupe_key` · `payload` |
| 表 | `events`（追加）· `ingest_cursors` · `health` · `witness_gaps` · `meta(device_id)` |
| 时长 | 读时 sessionize：边沿→下一状态；tick 宽限 10 分钟；睡眠豁免 |
| 打包 | Swift `.app` 常驻 + Python 摄入脚本/定时；非 MAS；本地构建大概率无需公证（待验） |

## 11. 权限与安装

| 用户会看到的提示 | 为何需要 | 拒绝之后 |
| --- | --- | --- |
| 辅助功能（Accessibility）→ 签名的 `.app` | 读取窗口标题（AX） | 仍记 App 切换与 AFK；标题缺失，记 health 缺口 |
| 登录项（`SMAppService`） | 开机自动跑边沿记录器 | 需手动启动；关机期间无边沿 |
| 完全磁盘访问 FDA（可选） | 读 Biome 见证流 | 双见证关闭；health=warn；主路径不受影响 |
| 自动化 / AppleScript（不申请） | — | v1 不用脚本取 URL，改走 Chrome History |
| 屏幕录制（不申请） | — | 永不截图 |

安装预期：用户拿到签名 `.app` → 打开一次 → 系统引导开辅助功能 → 登录项注册。重新构建后授权是否保留取决于代码签名身份（真机待验）。切勿把 Accessibility 授给系统 Python 或 Terminal。

## 12. 里程碑

Checklist 为截至 2026-10-28 Asia/Shanghai 的记录状态。

- [x] **M0** 研究与红队：需求、先例、最终架构、24 条发现处理（完成）
- [x] **M1** Linux 原型：Store / 摄入 / 脱敏 / 双见证 / 迁移 / 导出；58/58 测试（完成）
- [ ] **M2** 本 PRD 定稿与 Jonas 开放问题决策（进行中）
- [ ] **M3** 真机只读探测：Chrome History 权限、Biome 是否仍写、TCC 行为（Mac 未验）
- [ ] **M4** 编译并签名 Swift `.app`；Accessibility 授给 `.app`；登录项（骨架未编译）
- [ ] **M5** 真机联调：边沿延迟、AFK、睡眠、脱敏、崩溃重放、缺口可见（未开始）
- [ ] **M6** 打包给 Jonas 日常使用（保留期、备份习惯、可选 DB 加密决策落地）（未开始）
- [ ] **M7+** 复盘 UI / LLM 摘要（明确非本 PRD 范围）（后续）

## 13. 开放问题

| 问题 | 为何阻塞 | 建议默认 |
| --- | --- | --- |
| Muse 具体是哪个产品？ | 无已验证本地日志；避免错误 parser | v1 仅焦点 + Chrome URL 级可见 |
| 是否上库级加密（SQLCipher 等）？ | FileVault 已覆盖磁盘盗窃；加密增运维 | v1 依赖 FileVault；加密作 P2 |
| 标题拒绝列表还要加哪些 App？ | 银行 / 聊天 / 交易所窗口可能含秘密 | 先合并 Jonas 常用钱包与聊天 App bundle 列表 |
| 是否批准真机检查脚本？ | M3 需要在 Jonas 的 Mac 上跑只读探测 | 先跑 `macos_readonly_check.sh`，不写库 |
| FDA 授给谁？ | Biome 见证需要时 | 授给同一签名 `.app`；或放弃 Biome |
| 数据保留几天？ | 影响磁盘与隐私面 | 建议 90 天起步，可配 |
| 日后 LLM 复盘默认本地还是 opt-in 云？ | 不阻塞 v1 存储，但影响 payload 瘦身策略 | 存储已按「默认可外发聚合」瘦身；决策可后置 |

## 14. 风险与依赖

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| macOS 更新破坏 AX / Biome 字段 | 标题丢失或见证失效 | 双见证 + health；Biome 非主路径；关注系统发布 |
| Claude 默认 30 天清理本地会话 | 未及时摄入则丢失 | 至少每日摄入；库内只留瘦字段 |
| Codex 7 天后压成 `.zst` | Python 3.13 读不了 | 发现即 health=warn；运行环境升到 3.14+（路径未测） |
| Accessibility 授给解释器 | 任意脚本继承权限 | 必须签名 `.app`；禁止 Python launchd 持权 |
| 守护进程静默死亡 | 最后焦点被算成无限长 | 5 分钟 tick + 10 分钟宽限 → unknown；Biome 缺口 |
| 多机简单加总时长 | 重复计算 | 每库 `device_id`；复盘按墙钟并集；不同步 |

## 15. 附录

| 项 | 内容 |
| --- | --- |
| 技术页 | 活动采集与存储：最终方案 — https://cursor.com/canvas/store-53dd1173-d034-4a8e-bfd1-d140b10dbc3c/f863315c-cbbb-470e-9caa-58795ece6c8a |
| 代码根（研究工作区，不在本仓库） | `/workspace/activity-monitor-research/capture-storage/` |
| 关键文档 | `docs/CAPTURE_SPEC.md` · `RED_TEAM.md` · `PRIOR_ART_CITATIONS.md` · `rules/redact_rules.json` |
| 测试 | 58 run / 58 OK / 0 skipped · Linux · Python 3.13.5 · 2026-10-28 · `logs/test_run.txt` |
| Swift | `swift/` 为未编译骨架；从未在 Mac 上跑过 |

明确未在真机验证的事项：

- NSWorkspace 焦点通知、AXObserver 标题、TCC 弹窗文案与重建后授权保留。
- `CGEventSource` AFK、睡眠/唤醒/锁屏通知在实机时序。
- 无 FDA 读 Chrome History；有/无 FDA 读 Biome；macOS 26 是否仍写 `App.InFocus`。
- `SMAppService` 登录项、本地构建是否触发公证/隔离属性。
- Python 3.14 读取 Codex `.jsonl.zst`。
- 真机长跑 CPU / RSS / 磁盘增长。
