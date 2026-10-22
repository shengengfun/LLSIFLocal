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
| 数据包 `LLSIFLocal-数据包-*.7z` | Release 说明页给出的地址 | 约 15 GB，含服务端 + 全量游戏资源 |
| `LLSIFLocal-Launcher-*-windows-x64.zip` | 本仓库 Release | Windows 启动器 |
| `LLSIFLocal-Launcher-*-android.apk` | 本仓库 Release | Android 启动器（可选） |
| 客户端 APK | 自备 | 需要按你的服务端 IP 改包，见第 4 节 |

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
按你的服务端 IP 改包后再装：

```powershell
cd D:\LLSIFLocal\honoka-chan-dev
# 需要：apktool.jar、apksigner、zipalign、honoka2.exe、jdk17（路径在脚本头部可改）
powershell -ExecutionPolicy Bypass -File .\tools\patch_client_lan.ps1 -Ip 192.168.0.106 -NoInstall
```

脚本会产出 `temp\netpatch\client_lan_192_168_0_106.apk`，安装即可。
它做三件事：把 ghome 的 `/v1/*` 地址改成 `http://<IP>:8080`、把 `AppAssets.zip` 里的
`server_info.json` 同步成同一个地址、把 `server_version` 对齐（否则会停在「下载 NaN%」）。

> 已装过同签名旧包时直接 `adb install -r` 覆盖，**存档不丢**。

**装到平板/手机**：与电脑处于同一局域网，允许「未知来源」安装。
服务器地址不是 `192.168.0.106` 就必须重打包，APK 里的地址是编译期写死的。

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

---

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
