# Think My Day

正式 App。现在是 M4 的骨架（#4）：菜单栏 App、记录库、系统授权检查和开机自动启动。开启一天、读取窗口文字等由 M4 的其他 issue 加入。

## 目录

| 路径 | 内容 |
| --- | --- |
| `Sources/ThinkMyDayCore/` | 记录库和领域类型，不依赖界面，可直接测试 |
| `Sources/ThinkMyDay/` | 菜单栏 App |
| `Sources/tmd-store-stress/` | 开发工具：给崩溃测试用的写入器 |
| `Tests/ThinkMyDayCoreTests/` | 记录库测试 |
| `scripts/build-app.sh` | 构建通用二进制、签名、安装到 `~/Applications` |
| `scripts/crash-test.sh` | 在随机时刻强杀写入进程，检查数据库是否完好 |

## 构建与安装

签名证书沿用 M0b 的「ThinkMyDay Local Signing」。还没有这张证书时，先运行 `../tools/M0bProbe/scripts/make-signing-cert.sh`。

```bash
SIGN_IDENTITY="ThinkMyDay Local Signing" ./scripts/build-app.sh
```

第一次启动需要在「系统设置 → 隐私与安全性」里给 Think My Day 打开辅助功能和屏幕录制。之后用同一张证书重新构建，授权会保留。

## 测试

```bash
swift test
```

```bash
./scripts/crash-test.sh 20
```

## 记录库

- 位置：`~/Library/Application Support/ThinkMyDay/thinkmyday.sqlite`。开发时可用环境变量 `TMD_DATA_DIR` 指定别的目录。
- 单库 SQLite，WAL，`synchronous = FULL`。
- 所有写入都是一条**事件**（`events` 表）。`review_days`、`records` 等表是事件的投影，在同一个事务里更新，`cursors` 记录投影处理到哪条事件。崩溃后要么事件和投影都在，要么都不在；投影落后时，打开库会自动补上。
- 结构变更只做前向迁移：在 `Schema.migrations` 末尾追加，不改已发布的条目。库的版本比 App 新时拒绝打开。
- 加密、保留期限和脱敏分别在 #10、#9 中加入。

启动日志：

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.jonascyang.thinkmyday"' --style compact
```
