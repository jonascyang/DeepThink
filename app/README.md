# Think My Day

正式 App，M4 记录层进行中。已有：菜单栏 App、记录库、系统授权检查、开机自动启动（#4），开启一天和结束一天（#5），读取窗口文字（#6），写入前脱敏（#9），加密存储和保留期限（#10），不看名单和永不读取（#8），多窗口和桌面布局（#7）。

## 目录

| 路径 | 内容 |
| --- | --- |
| `Sources/ThinkMyDayCore/` | 记录库和领域类型，不依赖界面，可直接测试 |
| `Sources/ThinkMyDayCore/Redaction/` | 写入前脱敏；`BIP39Words.swift` 由官方词表生成，不要手改 |
| `Sources/ThinkMyDayCore/Capture/` | 可见性规则、行去重、网址去参数、OCR 限频、无输入判定（纯逻辑，有测试） |
| `Sources/ThinkMyDay/` | 菜单栏 App |
| `Sources/ThinkMyDay/Capture/` | 读取窗口：辅助功能遍历、窗口列表、Chrome 网址、OCR、触发时机 |
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
- 写入前脱敏（#9）：每条记录写库前经过 `Redactor`，替换私钥（PEM、64 位十六进制、WIF、xprv）、助记词（连续 12 个以上 BIP39 英文或简体中文词）、JWT、常见服务的 API key、`password=`/`密码：` 一类赋值的值、通过 Luhn 校验的卡号，网址去掉 query 和 fragment；钱包地址保留。单独出现、没有标签的密码无法识别，密码输入框本身不读。64 位十六进制按私钥处理，交易哈希也会被隐去。
- 加密（#10，ADR 0003）：每条事件和记录的内容用 AES-256-GCM 加密，密钥在登录钥匙串（服务 `com.jonascyang.thinkmyday`，账户 `database-key`）。时间、种类、复盘日编号不加密。钥匙串里没有密钥而库里已有加密数据时，App 拒绝打开，不会换新密钥。旧版本写入的明文在打开时自动加密。
- 保留与删除（#10）：原始记录默认保留 30 天，可在菜单里选 7 天、30 天或永不清除，启动时和每 6 小时清理一次；复盘日本身保留。`deleteDay` 删除某一天的原始记录（或整个复盘日），正在记录的那天不能删。`secure_delete` 打开，删除后清空 WAL。
- 备份：菜单「备份记录库」用 `VACUUM INTO` 写到数据文件夹的 `backups/`，备份同样是加密的，要用同一把钥匙串密钥打开。
- 测试从不访问钥匙串：测试用 `InMemoryKeyStore`，崩溃测试的写入器把密钥放在数据库旁边的文件里。

## 采集

开启一天之后才读取，结束一天或锁屏、睡眠时停止。读取规则见 `docs/M0b-探测报告.md` §3.1，测试在 `Tests/ThinkMyDayCoreTests/CaptureTests.swift`。

- 触发：切换 App、焦点或标题变化、输入（防抖 1 秒），没有变化时每 5 秒一次。
- 每次读取当前桌面上可见的窗口（可见比例 ≥ 5%），每个窗口最多 6000 个元素、400 毫秒。
- 只存和该窗口上一次相比新出现的行（`windowText` 记录的 `added`）。
- 辅助功能读到的字数少于 50 时用 OCR 识别该窗口：每个窗口每 30 秒最多一次，全局每 5 秒最多一次，超时 10 秒，图片不落盘。读不到时写一条 `gap` 记录。
- 记录种类：`windowText`、`focus`、`gap`、`presence`（无输入、睡眠、锁屏的边沿）。
- 不看名单（#8）：名单里的 App 一律不做辅助功能读取，也不读标题，只写一条 `gap`（`blocked`）和不带 App 与标题的 `focus`（`hidden`）。首次使用时预置密码管理器、钱包和银行类 App，可在菜单「不看名单」或开启一天面板里修改，下一次读取立即生效。
- 桌面布局（#7）：`layout` 记录写下所有屏幕和可见窗口（位置、所在屏幕、可见比例、是否焦点），只在排列真正变化时写，焦点变化另有 `focus` 记录；不读的窗口只留位置，不留 App。窗口按窗口编号、位置（±2 pt）、排除法三步对上辅助功能窗口，对不上时写 `gap`（`noAccessibilityWindow`）。M0b 里匹配率掉到 78%，全是锁屏或显示器睡眠时所有窗口同时对不上；现在锁屏、睡眠和显示器睡眠时都停止读取。
- 永不读取：密码输入框、Chrome 无痕窗口、所有 `chrome-extension://` 页面（钱包、密码管理器插件都在其中）。Chrome 窗口对不上标签页时，焦点记录不保留标题，以防是无痕窗口。其他浏览器的无痕窗口目前识别不了。

开发开关：`open --env TMD_DATA_DIR=路径 ~/Applications/ThinkMyDay.app` 使用另一个记录库，密钥放在库旁的 `.key` 文件里而不是钥匙串，可以用 `tmd-store-stress dump 路径/thinkmyday.sqlite` 查看每条记录的种类和 App（不输出文字）；再加 `--env TMD_OCR_COMPARE=1` 时每分钟对焦点窗口做一次 OCR，在日志里和辅助功能字数对照。

启动日志：

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.jonascyang.thinkmyday"' --style compact
```
