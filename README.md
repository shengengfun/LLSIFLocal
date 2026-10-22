# LLSIF 国服 9.7.1 · 本地服务端启动器

LoveLive! 学园偶像祭（国服 9.7.1）本地化运行的**桌面/移动启动器（管理端）**。
它负责拉起本地服务端、改配置、管账号、管卡池与乐曲，并提供游戏内 GM 面板的开关。

- 服务端：改造版 [honoka-chan](https://github.com/YumeMichi/honoka-chan)（Go）
- 启动器：本仓库（Flutter，Windows / Android 共用一套 UI）
- 客户端：改包后的 9.7.1 APK（**不随本仓库分发**，见下文）

> 仅供**个人已购内容的离线备份与学习研究**。仓库不含任何游戏美术、音频、剧情资源；
> 与官方（KLab / 盛趣 / Bushiroad）无关，请勿用于任何商业或公开传播用途。

---

## 一、你需要准备什么

| 文件 | 来源 | 说明 |
|---|---|---|
| 数据包 `LLSIFLocal-数据包-*.7z` | 单独分发（约 15 GB，超出 GitHub Release 单文件上限） | 服务端 + 全量游戏资源 |
| [`LLSIFLocal-Launcher-1.3.0-windows-x64.zip`](https://github.com/shengengfun/LLSIFLocal/releases/download/v1.3.0/LLSIFLocal-Launcher-1.3.0-windows-x64.zip) | [Release v1.3.0](https://github.com/shengengfun/LLSIFLocal/releases/tag/v1.3.0) | Windows 启动器 |
| [`LLSIFLocal-Launcher-1.3.0-android.apk`](https://github.com/shengengfun/LLSIFLocal/releases/download/v1.3.0/LLSIFLocal-Launcher-1.3.0-android.apk) | [Release v1.3.0](https://github.com/shengengfun/LLSIFLocal/releases/tag/v1.3.0) | Android 启动器（含内嵌服务端） |
| 客户端 APK | 自备 | 打一次「通用中转包」以后换 IP 不用再打，见第 4 节 |

**磁盘要求**：解压数据包约 16 GB（压缩包本身另需 15 GB）。

**系统要求**：Windows 10/11 x64；Android 8.0+（启动器/管理端）。

---

## 二、安装（Windows，推荐流程）

### 1. 解压数据包

把 `LLSIFLocal-数据包-*.7z` 解压到一个**不含中文和空格**的目录，例如 `D:\LLSIFLocal\`。
解压后的结构必须保持原样：

```
D:\LLSIFLocal\
├─ honoka-chan-dev\
│  ├─ honoka-chan.exe          ← 服务端主程序
│  ├─ run.bat / run.sh         ← 命令行启停脚本
│  ├─ config.json              ← 监听端口与 cdn_server
│  ├─ assets\
│  │  ├─ main.db               ← 主数据（曲目、卡表、谱面索引）
│  │  ├─ data.db               ← 玩家存档
│  │  ├─ serverdata\beatmaps\  ← 1912 个谱面
│  │  └─ certs\
│  └─ static\
│     ├─ Android\archives\     ← 9260 个资源包（约 15 GB）
│     ├─ images\ css\ js\ templates\ font\
│     └─ download\
├─ launcher\                   ← 启动器（把 Release 的 zip 解压到这里）
└─ tools\                      ← 改包/加密辅助脚本
```

### 2. 启动服务端

三种方式任选其一：

```bat
:: A. 命令行
cd /d D:\LLSIFLocal\honoka-chan-dev
run.bat start        :: 启动
run.bat status       :: 查看状态
run.bat logs         :: 跟随日志
run.bat stop         :: 停止（先走 /local/admin/shutdown 优雅退出，再兜底强杀）
```

```text
:: B. 直接跑二进制（前台，Ctrl+C 退出）
honoka-chan.exe
```

**C. 用启动器自动拉起（推荐）** —— 见下一步。

首次启动会在 `assets\` 下自动建库，日志写到 `temp\run\honoka-chan.log`。

### 3. 用启动器管理

把 `LLSIFLocal-Launcher-*-windows-x64.zip` 解压到 `D:\LLSIFLocal\launcher\`，
双击 `llsif_local_admin.exe`（**整个目录要一起保留**，Flutter 的运行库在 `data\` 和 DLL 里）。

启动器会按 `launcher\..\..\honoka-chan-dev\honoka-chan.exe` 的顺序向上找服务端，
找到后自动接管：启动 / 停止 / 看护（App 开着就保证服务端活着）。

**概览页第一件事：点「修正 cdn_server 为本机 IP」。**
客户端下载资源走 `config.json` 里的 `cdn_server`，DHCP 换 IP 后必须同步，否则游戏会卡在下载。

### 4. 客户端 APK

数据包**不含** APK（游戏本体版权原因不随包分发）。你自己手上应有一份 9.7.1 的安装包，
改包后再装。

**推荐：通用中转包（一次打包，以后换 IP 不用再打）**

```powershell
cd D:\LLSIFLocal\honoka-chan-dev
# 需要：apktool.jar、apksigner、zipalign、honoka2.exe、jdk17（路径在脚本头部可改）
powershell -ExecutionPolicy Bypass -File .\tools\patch_client_lan.ps1 `
    -Ip 127.0.0.1 -RelayUpstream 192.168.0.106 -NoInstall
```

产物 `temp\netpatch\client_lan_127_0_0_1.apk`。客户端内部地址固定为 `127.0.0.1:8080`，
由 APK 内的 Relay 转发到 `RelayUpstream`。换服务端电脑时**不用重打包**：
进游戏 → 右边缘把手 → 「连接」页签 → 填新 IP → 「应用」，立刻生效。

> ⚠️ 这个模式靠「自己转发给自己」，所以**别在设备上留 iptables 的 loopback DNAT** 规则，
> 否则 `127.0.0.1:8080` 会被改写走，Relay 收不到连接（表现为卡启动页 + 网络请求超时）。
> 如果以前加过，清掉：
> ```bash
> adb shell su -c 'iptables -t nat -D OUTPUT -d 127.0.0.1/32 -p tcp --dport 8080 -j DNAT --to-destination <旧IP>:8080'
> ```

**旧做法：把 IP 焊死进包（换 IP 就得重打）**

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\patch_client_lan.ps1 -Ip 192.168.0.106 -NoInstall
```

脚本会产出 `temp\netpatch\client_lan_192_168_0_106.apk`，安装即可。
它做三件事：把 ghome 的 `/v1/*` 地址改成 `http://<IP>:8080`、把 `AppAssets.zip` 里的
`server_info.json` 同步成同一个地址、把 `server_version` 对齐（否则会停在「下载 NaN%」）。

**服务端侧**：`config.json` 里保持 `"cdn_server": "auto"`，资源下载地址会按请求的
Host 头自动推导，所以服务端换机器、客户端换 IP 都不用改配置。

> 已装过同签名旧包时直接 `adb install -r` 覆盖，**存档不丢**。

**装到平板/手机**：与电脑处于同一局域网，允许「未知来源」安装。

### 5. 登录

首次进入任意输入手机号 + 密码即自动注册（同一手机号再次输入同密码 = 登录）。
启动器「概览 → 原版从零开始」可以控制新号是否从 0 开始（关掉 = 送全套资源）。

---

## 三、游戏内面板

屏幕**右边缘中部**有一条细把手：

- **长按约 0.6 秒**拉出面板（单击不响应，避免打歌误触）
- 两个页签：
  - **GM**：加金币 / 加等级 / 加爱心（**分开发放**，加等级会同步重算升级所需经验、耐力上限）、
    自动打歌开关、校准轨道、判定偏移 ±20 ms
  - **连接**：服务器地址、端口、账号切换（手机号 + 密码）

## 三·五、自定义卡面

卡面纹理在**服务端资源包**里（`static/Android/archives/*.zip`），不在 APK 内，
所以换图不用重打包、不用重签名。

启动器：**卡池 → 右上角图片按钮（或某张卡上的图片按钮）→ 自定义卡面**

1. 填 `unit_id` → 查询，能看到这张卡最多 10 层纹理（图标 128² / 立绘 256×512 /
   NAVI 1024² / 半身像 512×1024）及各自所在资源包
2. 填 PNG 路径（服务端所在机器上能读到的）→ 收料并归档
3. 选模式执行：
   - **只出命令** —— 不改文件，复制命令到别处跑
   - **改写服务端资源包** —— 自动备份到 `assets/cardface_backups`，客户端重下该包后生效
   - **推送客户端** —— adb 直推 `files/install/...`，重启游戏立刻生效

命令行等价操作：

```powershell
cd honoka-chan-dev
python tools\cardface.py list  --unit 41107008
python tools\cardface.py server --unit 41107008 --png my.png --yes
python tools\cardface.py push   --unit 41107008 --png my.png
python tools\cardface.py restore --unit 41107008     # 回滚
```

---

## 三·六、手机开服（Android 内嵌服务端）

启动器 APK 里**自带服务端**，手机可以自己开服，不需要 PC。

1. 打开 App → 总览页显示数据目录：
   `/storage/emulated/0/Android/data/com.llsiflocal.llsif_local_admin/files/srv`
2. 用数据线把 PC 上 `honoka-chan-dev/assets` 与 `honoka-chan-dev/static` 整个拷进去
   （约 15 GB，**不需要 root**，也不需要存储权限）
3. 点「启动服务端」，服务端在手机上监听 `8080`
4. 客户端地址：同一台手机填 `127.0.0.1`，其它设备填手机的局域网 IP

从源码出包（服务端是伪装成 native lib 的 Go 可执行文件）：

```powershell
cd launcher
.\tool\build_android_server.ps1                             # 交叉编译 + 自检 PIE/linker64
..\sdk\flutter\bin\flutter.bat build apk --release
```

> 为什么能跑：`GOOS=android` 的 Go 产物是 PIE 且 interp 指向 `/system/bin/linker64`；
> 放进 APK 的 `lib/arm64-v8a/` 后属于可执行的 `apk_data_file`，
> 绕开「Android 10+ 不许执行可写目录文件」的限制。细节见 `docs/` 里回合 15。

限制：只带 arm64（32 位机加 `-Abis armeabi-v7a`）；服务端与 App 同生命周期，
App 被杀就一起没（尚未做前台 Service）。

## 四、常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| 卡在「下载 ××%」或「NaN%」 | `cdn_server` 不是当前 IP，或客户端 `server_version` 与服务端不一致 | 启动器概览页一键修正 `cdn_server`；或重打包 APK |
| 所有功能都显示「正在维护」 | 服务端没起来 / 端口被占 | `run.bat status`；看 `temp\run\honoka-chan.log` |
| 进 Live 或「选择队伍」闪退 | 队伍不足 9 人 / 持有客户端不认识的卡 | 打开启动器让服务端跑一次启动修复（会自动补满队伍、过滤未知卡） |
| 抽卡出来的卡直接满级、不消耗爱心 | 旧的魔改逻辑 | 本方案已还原为原生规则 |
| 换电脑或换 IP 后连不上 | APK 内地址写死 | 重新执行 `patch_client_lan.ps1 -Ip <新IP>` |
| 想清空存档重来 | — | 停服后删除 `assets\data.db`，重启服务端会重建 |

端口默认 **8080**，可在 `config.json` 或启动器里改。管理接口 `/local/*` 只在本机可用。

---

## 五、从源码构建

```powershell
# 启动器 · Windows
cd launcher
..\sdk\flutter\bin\flutter.bat build windows --release
# 产物：build\windows\x64\runner\Release\

# 启动器 · Android（必须先把三个环境变量指到本地 SDK/JDK）
$env:ANDROID_HOME="D:\LLSIFLocal\android-sdk"
$env:ANDROID_SDK_ROOT="D:\LLSIFLocal\android-sdk"
$env:JAVA_HOME="D:\LLSIFLocal\jdk-17.0.14+7"
..\sdk\flutter\bin\flutter.bat build apk --release
```

服务端源码在 [honoka-chan-dev](https://github.com/YumeMichi/honoka-chan)，本地化改造说明见 `docs/`。

---

## 六、致谢

- [honoka-chan](https://github.com/YumeMichi/honoka-chan)（源自 [Salaron/honoka-chan](https://github.com/Salaron/honoka-chan)）：服务端
- [NPPS4](https://github.com/DarkEnergyProcessor/NPPS4)、[alay](https://github.com/Salaron/alay)：曲目 / 随机打歌 / 接口行为参考
- Apktool、libhonoka：客户端改包与加密

## 七、许可

启动器源码：MIT（见 [LICENSE](LICENSE)）。
服务端为上游项目，遵循其自身许可。
游戏本体与全部美术、音频、剧情资源版权归原作者与发行方所有，**本仓库不包含**。

---

## 八、版本

| 版本 | 日期 | 内容 |
|---|---|---|
| v1.3.0 | 2026-10-22 | 通用客户端（中转模式，换 IP 不用重打包）；服务端 `cdn_server: auto`；修启动器 Android 白屏（`shared_preferences_android` 版本钉回 2.4.20） |
| v1.2.0 | 2026-10-22 | 手机开服：APK 内嵌 arm64 服务端（PIE + `/system/bin/linker64`），数据目录体检与初始化 |
| v1.1.0 | 2026-10-22 | 自定义卡面（查纹理 / 收料 / 三种落地 / 回滚）；honoka v4 加解密逐字节可复现 |
| v1.0.0 | 2026-10-22 | 首个可分发版本：启动器（Windows/Android）、服务端改造、GM 面板、自动打歌 |
