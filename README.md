# DeepThink

Jonas 个人用的 macOS 本地活动复盘底座。v1 只做**采集与存储**：签名 Swift 边沿记录器 + Python 幂等摄入 + 单机 SQLite。无截图、无击键、无剪贴板、无网络、无 iCloud。

复盘界面与 LLM 摘要不在本期范围，但库里的数据必须够支撑日后复盘。

产品需求见 [docs/PRD-采集与存储.md](docs/PRD-采集与存储.md)（PRD v0.1，草案，2026-10-28）。

## 范围

- 记录操作系统会忘掉的信号：前台焦点、窗口标题（受敏感 App 约束）、AFK（180 秒）、睡眠 / 唤醒 / 锁屏。
- 按游标幂等摄入已有磁盘日志：Claude Code JSONL、Codex rollout、Chrome History（多 Profile，不含无痕）。
- 可选读取 Biome `App.InFocus`（仅 `local/`）做双见证，缺口写入 `witness_gaps`。
- 写入前脱敏。每台 Mac 一份 SQLite WAL，`device_id` 区分机器，不同步。

## 明确不做

周期截图、OCR、击键、剪贴板、iPhone、iCloud、Mac App Store、Chrome 扩展实时 URL、复盘 UI、LLM 日摘要。
