# 服务端 APP（启动器）GUI 更新方案 v1

> 对象：`gh/LLSIFLocal/launcher`（Flutter，`llsif_local_admin`，6301 行 / 5 个一级页）
> 目标：让 GUI 覆盖「局域网交付 + 社区谱面」这条已跑通的新链路，而不是只做服务端起停。

## 1. 结论摘要

当前启动器缺三块关键能力，且有一处与实际部署不符：

1. **社区谱面完全没有 GUI**：服务端已实现 10 个 `/local/admin/community/*` 接口，启动器 `lib/` 里 `community` 零引用。发谱、撤谱、停用、体检全靠 curl。
2. **默认端口写死 8080**（`state.dart:17/32`），而本机 8080 被管控软件内核级拦截、实际必须用 8090 —— 新用户开机即「连不上」。
3. **没有「客户端怎么连」的引导**：relay 客户端需要知道 `PC IP + 端口`，现在只能靠口头传达；`server_control.dart` 已有 `localLanIps()` 与 adb 能力，可直接做成连接卡。
4. **没有体检视图**：`/admin/community/packages` 已返回 `missing` / `size_mismatch`，但没人看得到；而 `size_mismatch` 正是「通信中断」的真因。

优先级：P0 = 端口自适应 + 社区谱面页 + 体检面板；P1 = 连接卡（IP/端口/二维码）；P2 = 批量与导出。

## 2. 现状盘点

| 一级页 | 已有能力 | 与本次需求的差距 |
|---|---|---|
| 总览 `overview_page.dart` (1246) | 服务端启停/重启、端口配置与自动探测、路径设置、`一键改为 $expected` | 默认 8080；无「客户端连接信息」；无健康横幅 |
| 账号 `players_page.dart` (367) + `player_detail_page.dart` (744) | 玩家列表、详情、发卡/道具/道具箱、邮件、备份恢复 | 基本够用，只需在详情页挂「该玩家社区曲通关情况」（P2） |
| 卡池 `cards_page.dart` (257) | 卡面库、texb 转换 | 与本次无关 |
| 乐曲 `lives_page.dart` (842) | 官方曲列表、启停、谱面替换（`saveBeatmap`） | **只覆盖官方曲**；社区曲是另一套表（`Com_9xxx` + `1_T_1.zip`），不能混进这里 |
| 工具 `tools_page.dart` (498) | 新号模式、卡面库扫描、快速切号、解绑 | 缺「生成客户端配置二维码」 |

服务端可用接口（`internal/handler/local/`）：

```
GET  /local/admin/community/packages        列表 + 逐曲 missing / size_mismatch（体检核心）
GET  /local/admin/community/beatmaps        磁盘上已就绪的谱面文件
POST /local/admin/community/beatmaps/attach 把磁盘谱面挂到指定 live_difficulty_id（可 detach）
POST /local/admin/community/publish         发布（multipart：chart/cover/title/audio + 元数据）
POST /local/admin/community/withdraw        撤下某曲（track_id）
POST /local/admin/community/toggle          启用/停用
POST /local/admin/community/rollback-all    回滚全部社区改动
GET  /local/admin/community/chart-stat      解析谱面统计（发布前预览）
```

发布接口字段（`readPublishForm`，已核对源码）：`name` `name_en` `difficulty` `member_category` `capital_value` + 文件 `chart` `cover` `title` `audio`（后两者可选，缺省由服务端渲染）。返回 `track_id` `setting_id` `difficulty_id` `music_id` `chart{note_count,time,...}` `resources` `download`。

## 3. 目标信息架构

保持 5 个一级区不变（不增加认知负担），把社区能力**挂进「乐曲」页作为二级 Tab**，体检挂进「总览」：

```
总览    ├─ 服务状态卡（原有）+ ★健康横幅（社区包体检）
        └─ ★客户端连接卡（IP/端口/中转说明/二维码）
账号    （不变，P2 加社区通关统计）
卡池    （不变）
乐曲    ├─ 官方曲（原 Tab）
        └─ ★社区谱面（新 Tab：列表 / 发布 / 体检整改）
工具    ├─ 原有
        └─ ★「生成客户端连接二维码」（与总览共用同一组件）
```

★ = 本次新增。

## 4. 逐块方案

### 4.1 端口自适应（P0，最小改动、收益最大）

问题：`state.dart` 默认 8080；用户点「启动服务端」后连不上，误判成服务端坏了。

- 默认值改为 **8090**，并把 `8080` 保留为候选。
- `connectOrStart()` 里改为「候选端口列表探测」：`[prefs.port, 8090, 8080]` 依次 `GET /local/admin/overview`（2s 超时），命中即用并写回 prefs。
- 总览的端口输入框下方加一行**实时结果**：`✓ 8090 可连接（当前） / ✗ 8080 被占用或被系统拦截`。
- 「用此端口重新连接」按钮旁加「试试 8090 / 试试 8080」两个快捷 chip。
- 验收：全新安装（无 prefs）→ 点一次「启动服务端」→ 直接进总览且显示 8090。

### 4.2 社区谱面页（P0，核心新增）

新文件 `lib/pages/community_page.dart`（作为 `lives_page.dart` 的第二个 Tab，复用其 TabBar）。

**列表区**（数据源 `GET /admin/community/packages`）

每行：封面缩略图（`/local/admin/live-cover/:track`，已有接口）、曲名、难度徽章（1–6）、`Com_9xxx` 谱面名、状态徽章、操作。

状态徽章规则（直接映射体检字段）：

| 条件 | 徽章 | 颜色 |
|---|---|---|
| `missing` 为空且 `size_mismatch=false` | 正常 | 绿 |
| `size_mismatch=true` | 包大小不一致（会弹通信中断） | 红 |
| `missing` 含 `chart` | 缺谱面 | 红 |
| `missing` 含 `download_m` | 未登记下载（客户端看不到） | 橙 |

- 顶部统计条：`共 24 首 · 正常 24 · 待修 0`。
- 右上「一键体检」→ 重拉接口并 toast 差异；「回滚全部」→ 二次确认后 `rollback-all`。
- 行操作菜单：`停用/启用`（toggle）、`撤下`（withdraw，二次确认写明"会同时删除下载包"）、`查看统计`。

**发布区**（右侧抽屉或独立对话框，宽屏并排）

表单字段（严格对齐 `readPublishForm`）：

- 谱面文件（必填，`.json`）——选择后**立即**调 `POST /admin/community/chart-stat` 预览：音符数、时长、BPM 区间、建议难度
- 曲名 `name`（必填）、英文名 `name_en`（留空＝与曲名同）
- 难度 `difficulty`（下拉 1 普通 / 2 困难 / 3 专家 / 4 大师 / 5–6 特殊；留空＝按谱面自动建议）
- 成员分类 `member_category`（默认 4 = Liella，与现有 24 首一致）
- 消耗耐力 `capital_value`（留空＝按难度默认 5/10/15/20/25）
- 封面（可选 png/jpg）、题图（可选）、音频（可选 ogg/mp3；不给则用同名缓存）
- 底部：`发布` 按钮带**上传进度**（`http.MultipartRequest` + `StreamedResponse` 读进度），禁用重复点击。

发布成功后的反馈必须具体（这是最容易踩坑的一步）：

```
✓ 已发布：track_id=27 · difficulty_id=96 · music_id=9003
  已生成 1_27_1.zip (4.8 MB) / 1_27_2.zip
  体检：正常，可被客户端立即看到
```

若返回的 `resources`/`download` 字段显示异常，直接在成功卡片上标红提示「包大小需核对」。

**空/错态**

- 无社区曲：插画 + 「还没有社区谱面，先发布一首」；
- 接口 404：说明「服务端版本较旧，无社区模块」并给升级指引（而不是空白）。

### 4.3 体检面板（P0，总览页横幅）

- 进入总览时并行请求 `overview` + `community/packages`（失败不影响主流程）。
- 有待修项时在顶部显示黄色横幅：`社区包 2 项异常（1 项会导致客户端"通信中断"）`，点击直接跳到社区页对应筛选。
- 全绿时不占位，仅在「服务状态卡」里显示一行 `社区包 24/24 正常`。
- 用途明确：**把今天"通信中断"那类问题变成一眼可见**，不再靠翻服务端日志。

### 4.4 客户端连接卡（P1）

总览页新增卡片，直接消除「客户端连不上、不知道填什么」的反复沟通：

- 自动列出 `localLanIps()` 的候选（过滤 docker/vEthernet），默认选 `192.168.*`；
- 显示三项：`服务器地址 192.168.0.106:8090`、`客户端默认上游（relay）`、`直连备选`；
- 「复制地址」按钮；「生成二维码」把 `llsif://relay?host=…&port=…` 画成 QR（`qr_flutter`，不新增重型依赖）；
- 已接入 adb 时（`server_control.deviceReady()`）追加「推送到已连接设备」：`adb install -r` 交付目录里的局域网版 APK，显示进度与结果；
- 附一行排查口诀：`连不上先测 TCP：手机浏览器开 http://IP:端口/local/admin/overview`。

### 4.5 工具页增补（P2）

- 「导出社区曲清单」→ CSV（track_id、曲名、难度、谱面、包大小、状态），便于批量核对。
- 「重算 pkg_size」→ 调服务端新接口（见 §5），把历史脏数据一次性抹平。

## 5. 需要服务端补的接口（很少，2 个）

1. `POST /local/admin/community/repair-sizes` —— 按真实文件大小回写 `download_m.pkg_size`，返回修正行数。
   理由：这次是我用 SQL 修的 153 行；有了接口，GUI 一个按钮就能修，且以后 publish 之外的脏数据可自愈。
2. `GET /local/admin/client-config` —— 返回 `{lan_ips:[], listen_port, relay_default_host, client_apk_name}`。
   理由：GUI 不该自己猜端口和 APK 名，由服务端做单一事实来源。

其余能力现有接口已够，无需改动契约。

## 6. 分阶段实施与验收

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| P0-a | 端口自适应（§4.1） | 全新安装一键进总览；8090/8080 探测结果可见 |
| P0-b | 社区页列表 + 状态徽章 + 体检横幅（§4.2 列表 / §4.3） | 24 首全部显示状态；人为改坏一行的 pkg_size 能立刻变红并定位 |
| P0-c | 发布表单 + chart-stat 预览 + 进度条（§4.2 发布） | 用现有 `Com_900x.json` 发布一首，成功卡片字段正确；客户端「仙乡梦旅」式下载并开打 |
| P1 | 连接卡 + 二维码 + adb 推送（§4.4） | 换一台手机，仅凭界面信息即可连上并进入游戏 |
| P2 | 导出 CSV、重算 size、玩家详情挂社区统计（§4.5） | 导出的 CSV 与体检结果一致 |

工作量估计：P0 约 2–3 天（社区页是大头，列表 200 行 + 表单 300 行 + 状态组件 80 行）；P1 半天；P2 半天。

## 7. 技术要点

- **状态**：沿用现有 `AppState extends ChangeNotifier`，新增 `CommunityState`（列表、体检结果、加载态、错误），避免把所有逻辑塞进页面。
- **API 层**：`api.dart` 新增 8 个方法，统一 `_get/_post` 封装，超时 8s（发布 60s，上传用 stream）。
- **列表性能**：24 首不需要虚拟滚动，但封面走 `Image.network` 并加 `cacheWidth: 160`，避免大图解码拖慢。
- **错误呈现**：服务端统一返回 `{ok:false,message}`，GUI 直接展示 `message`，不要吞掉（这次 `pkg_size` 问题就是被吞成"超时"）。
- **危险操作**：`回滚全部`、`撤下` 必须二次确认 + 输入曲名确认（防误点，这两者都不可逆）。
- **主题**：沿用 `theme.dart` 的双主题；徽章用语义色，不写死 RGB。

## 8. 风险与回退

| 风险 | 影响 | 对策 |
|---|---|---|
| 发布时音频过大导致上传超时 | 发布失败但服务端可能已落半包 | 上传前校验（ogg ≤ 6 MB），失败提供「体检并重算」入口 |
| 社区页把 `Com_9xxx` 与官方曲混排 | 误停用官方曲 | 社区页只读社区表，官方曲仍在原 Tab，物理隔离 |
| 端口自适应误判（别的程序占了 8090） | 连到错误服务 | 探测必须校验 `/local/admin/overview` 的 `ok` 与产品标识，不只看 TCP 通 |
| GUI 依赖新接口，旧服务端不支持 | 页面报 404 | 前端做能力探测，缺接口时降级为只读并提示升级 |

## 9. 代码改动清单

| 文件 | 动作 |
|---|---|
| `lib/state.dart` | 默认端口 8090；候选端口探测；新增 `CommunityState` |
| `lib/api.dart` | 新增 community 8 个方法 + client-config + repair-sizes |
| `lib/pages/community_page.dart` | **新增**（列表 + 发布抽屉 + 状态徽章） |
| `lib/pages/lives_page.dart` | 外层改为 TabBar：官方曲 / 社区谱面 |
| `lib/pages/overview_page.dart` | 加体检横幅 + 客户端连接卡 |
| `lib/widgets.dart` | 新增 `StatusBadge`、`SectionCard`、`ProgressButton` 复用组件 |
| `pubspec.yaml` | 加 `qr_flutter`（仅此一个） |
| `test/app_test.dart` | 加端口探测、徽章映射、发布表单校验的单测 |

## 10. 下一步

建议先做 P0-a（端口）——改动不足 50 行，却直接消掉「新机器第一次就连接失败」这个最劝退的问题；然后做 P0-b 列表与体检，最后做 P0-c 发布表单。

## 11. 实施进展（2026-10-25 晚，P0-b / P0-c 已落地）

本轮按本文 §4.2 / §5 的思路，**在 `srvapp`（Flutter 服务端 APP）内**完成社区谱面的「显示 + 解析 + 推送」闭环；端口自适应（P0-a）与总览连接卡（P1）留待后续。

### 11.1 服务端契约补齐（`honoka-chan-dev`）

| 接口 | 变更 |
|---|---|
| `GET /local/admin/community/packages` | 每行新增 `member_category`、`notes`、`seconds`、`pkg_size`（= `1_T_1.zip` + `1_T_2.zip` 真实大小）；`missing` 语义不变 |
| `POST /local/admin/community/publish` | `resources` 现在回填**实际写进包的资源名**，`download` 回填两个下发包名（此前恒为空） |

- `notes` / `seconds` 由服务端顺带解析谱面得到，GUI 列表不必再逐曲请求 `chart-stat`。
- 修正 `buildCommunityPackage` 的接收者：改传 `*publishResult`，否则资源/下发包清单无法回传。
- 无需新增 §5 的两个接口。

### 11.2 服务端 APP（`srvapp`）

- `lib/models.dart`：新增 `ChartStat`、`CommunityPackage`（含 `healthy` / `problemLabels` 语义化文案）、`PublishOutcome`。
- `lib/api.dart`：新增 `communityPackages` / `communityChartStat` / `publishCommunityTrack`（multipart，带上传进度）/ `withdrawCommunityTrack` / `liveCoverUrl`；
  新增 `_ProgressMultipart`（用 `transform` 统计字节，保留背压，几十 MB 音频不整包缓存）。
- `lib/pages/lives_page.dart` 的「社区谱面」Tab 重做：
  - 体检横幅（全绿 / N 首有问题 + 逐条原因）；
  - 「已发布曲目」列表：封面、曲名、`#曲目号·成员组·难度·难度号`、音符/时长/包大小/谱面文件名、`可下载` 或红色问题徽章、`撤下`；
  - 「发布社区曲」表单：曲名/英文曲名/难度（可自动）/成员组/LP，谱面可选文件或粘贴 JSON，选完自动 `chart-stat` 预览（音符/时长/密度/和弦/建议难度），封面/标题图/音频可分别选，上传进度条，成功后弹结果卡（曲目号、难度号、资源、下发包）；
  - 危险操作 `撤下` 需**原样输入曲名**确认；
  - 原「谱面库（附加到官方难度）」折叠区保留（改用自管展开状态，原因见 §11.4）。
- `pubspec.yaml`：新增 `file_picker`（选中后立刻读成字节，避免 Android 临时路径失效）。
- `lib/main.dart`：宽屏导航栏在矮屏（横屏手机 ~390dp 高）放不下 6 个目的地，`乐曲 / 工具` 被裁掉——
  社区谱面入口就在乐曲页，等于点不到。矮屏改为 `NavigationRailLabelType.none` + 整条 rail 可滚动（等高、位置稳定），
  宽屏行为不变。

### 11.3 体检字段怎么读

`missing` 的取值与界面文案对应：`chart`→缺谱面文件、`1_T_1.zip`→缺资源包、`1_T_2.zip`→缺安装信息包、`download_m`→未登记下载（客户端看不到）、`size_mismatch`→包大小不一致（客户端会「通信中断」）。

### 11.4 两个踩过的坑（勿回退）

1. **不要用 `ExpansionTile` 装折叠区**：它把展开标志写进 `PageStorage`，而同一路径还有 `ListView` 的滚动偏移（`double`），列表刷新后长度一变就会撞
   `type 'double' is not a subtype of type 'bool?'`，整页渲染成空白。现改为 `_libExpanded` 自管状态。
2. **Android x86_64 模拟器上不能由 App 自己拉服务端**：`modernc.org/sqlite` 打开库时走 `lstat`，被 untrusted_app 的 seccomp 拦成 `SIGSYS: bad system call`。
   arm64 真机无此问题（arm64 没有 `lstat`）。模拟器联调请用 `adb reverse tcp:8080 tcp:<PC 端口>` 指向 PC 上的服务端。

### 11.5 验证

- `go build ./...` / `go vet` 通过；`srvapp` `flutter analyze` 0 error（余 6 条既有 warning）、`flutter test` 16/16 通过（新增社区列表解析、谱面解析、multipart 上传进度、社区 Tab 渲染 4 组用例）。
- 沙箱实测（PC 服务端 + SIF30 模拟器（Android 11 / x86_64）App，经 `adb reverse` 指到 PC 服务端）：
  1. 社区 Tab 显示「体检通过：24 首社区曲谱面、资源包、下载登记齐全」，24 首逐行带封面与 `可下载`；
  2. 改坏一首（不推谱面）后立刻变红并给出「缺谱面文件」；
  3. 粘贴 3 音符 JSON → 预览「3 音符 / 0:02 / 1.50 密度 / 建议普通」，发布成功返回 `曲目号 900 / 难度号 4525 / 曲号 9026`，并提示「没有生成下发包」（未给音频封面）；
  4. 该曲在列表中显示 `缺资源包 / 缺安装信息包 / 未登记下载`，输入曲名确认后 `撤下` 成功，列表回到 24 首。
- 带封面/音频的完整发布会话另用 curl 验证：`resources` 7 项、`download` 2 个 zip，`pkg_size` 与真实文件一致。
