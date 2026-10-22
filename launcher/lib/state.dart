import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'server_control.dart';

/// 连接配置 + 主题 + 本机服务端进程，供各页面共享。
class AppState extends ChangeNotifier {
  AppState();

  /// 测试用：直接注入已建立好的 API，跳过 prefs 与网络探测。
  AppState.forTest({
    required LocalApi api,
    this.host = '127.0.0.1',
    this.port = 8080,
    this.darkMode = false,
  }) {
    _api = api;
    runtime = ServerRuntime.external;
  }

  static const _kHost = 'srv_host';
  static const _kPort = 'srv_port';
  static const _kExe = 'srv_exe';
  static const _kWorkDir = 'srv_workdir';
  static const _kDark = 'ui_dark';
  static const _kAutoStart = 'srv_autostart';

  String host = '127.0.0.1';
  int port = 8080;

  /// 深色开关（默认浅色，与参考项目一致）。
  bool darkMode = false;

  /// 打开 App 时如果连不上，是否自动把本机服务端拉起来。默认开。
  bool autoStartServer = true;

  /// 最近一次自动启动的错误（界面用来解释为什么没起来）。
  String? autoStartError;

  /// 本机服务端可执行文件与工作目录。
  String exePath = '';
  String workDir = '';

  LocalApi? _api;
  String? connectionError;

  final ServerProcess process = ServerProcess();

  /// 客户端走 localhost，需要 adb 反向转发；这个对象负责「丢了就补回来」。
  final AdbReverse adbReverse = AdbReverse();

  ServerRuntime runtime = ServerRuntime.stopped;
  List<String> lanIps = const [];

  /// 看门狗：只要 App 开着，就保证服务端真的活着。
  Timer? _watchdog;
  int _failStreak = 0;
  bool _recovering = false;

  /// 用户主动点了「终止服务」后不再自动拉起，直到他再点启动。
  bool _userStopped = false;

  /// adb 反向转发是否可用（客户端走 localhost 时依赖它）。
  bool adbForwardOk = false;

  LocalApi? get api => _api;
  bool get connected => _api != null;
  String get baseUrl => 'http://$host:$port';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    host = prefs.getString(_kHost) ?? host;
    port = prefs.getInt(_kPort) ?? port;
    darkMode = prefs.getBool(_kDark) ?? false;
    autoStartServer = prefs.getBool(_kAutoStart) ?? true;
    exePath = prefs.getString(_kExe) ?? '';
    workDir = prefs.getString(_kWorkDir) ?? '';

    // 首次运行时自动猜一下服务端位置，免得用户手填。
    if (exePath.isEmpty || workDir.isEmpty) {
      final guess = await guessServerPaths();
      if (guess != null) {
        exePath = guess.exe;
        workDir = guess.workDir;
        await prefs.setString(_kExe, exePath);
        await prefs.setString(_kWorkDir, workDir);
      }
    }
    lanIps = await localLanIps();
    notifyListeners();

    // 直接进主程序，所以启动时就自己尝试连一次；连不上由总览页给出提示。
    await _autoConnect();

    // 连不上且本机能跑服务端 → 直接把服务端拉起来，用户打开 App 就能用。
    if (!connected && autoStartServer && process.supported) {
      autoStartError = await startServer();
      notifyListeners();
    }

    _startWatchdog();

    // 首次启动就把 adb 转发补上，别等 5 秒。
    await _adbTick();
  }

  /// 每 5 秒探一次服务端；连不上就试着拉起来，进程假死就重启。
  /// 这是为了解决「App 开着但服务端没跑，客户端一直网络超时」这种状态。
  ///
  /// 同时检查 adb 反向转发：客户端的服务端地址是 localhost，
  /// adb 一重启转发就没了，客户端同样会立刻超时。
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _healthTick();
      await _adbTick();
    });
  }

  /// adb 转发保活：没设备就跳过，设备在就确保转发存在。
  Future<void> _adbTick() async {
    if (!adbReverse.supported) return;
    try {
      if (!await adbReverse.deviceReady()) return;
      final ok = await adbReverse.ensure();
      if (ok != adbForwardOk) {
        adbForwardOk = ok;
        notifyListeners();
      }
    } on Object {
      // adb 不在或权限不足都不该影响主流程。
    }
  }

  Future<void> _healthTick() async {
    if (_recovering) return;

    final ok = await _ping();
    if (ok) {
      _failStreak = 0;
      if (runtime == ServerRuntime.stopped) {
        runtime = process.running ? ServerRuntime.managed : ServerRuntime.external;
        notifyListeners();
      }
      return;
    }

    _failStreak++;
    if (runtime != ServerRuntime.stopped) {
      runtime = ServerRuntime.stopped;
      notifyListeners();
    }

    // 用户主动停的、或平台跑不了服务端，就只报状态不折腾。
    if (_userStopped || !autoStartServer || !process.supported) return;
    // 连续两次（约 10 秒）都不通才动手，避免瞬断误判。
    if (_failStreak < 2) return;

    _recovering = true;
    try {
      if (process.running) await process.stop();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      autoStartError = await startServer();
      _failStreak = 0;
    } finally {
      _recovering = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  Future<void> setAutoStart(bool value) async {
    autoStartServer = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoStart, value);
    notifyListeners();
  }

  /// 启动时的静默连接：只等 2 秒，失败不弹错，交给界面提示。
  Future<void> _autoConnect() async {
    final probe =
        LocalApi(baseUrl: baseUrl, timeout: const Duration(seconds: 2));
    try {
      await probe.ping();
      _api = LocalApi(baseUrl: baseUrl);
      connectionError = null;
    } on Object catch (e) {
      _api = null;
      connectionError = e.toString();
    }
    notifyListeners();
  }

  Future<void> saveConnection(String newHost, int newPort) async {
    host = newHost.trim();
    port = newPort;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, host);
    await prefs.setInt(_kPort, port);
    notifyListeners();
  }

  Future<void> saveServerPaths(String exe, String dir) async {
    exePath = exe;
    workDir = dir;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kExe, exe);
    await prefs.setString(_kWorkDir, dir);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDark, value);
    notifyListeners();
  }

  /// 探测 /local/ping，成功才建立会话。
  Future<bool> connect() async {
    connectionError = null;
    final candidate = LocalApi(baseUrl: baseUrl);
    try {
      await candidate.ping();
      _api = candidate;
      notifyListeners();
      await refreshRuntime();
      return true;
    } on Object catch (e) {
      _api = null;
      connectionError = e.toString();
      notifyListeners();
      await refreshRuntime();
      return false;
    }
  }

  void disconnect() {
    _api = null;
    connectionError = null;
    runtime = ServerRuntime.stopped;
    notifyListeners();
  }

  Future<void> refreshLanIps() async {
    lanIps = await localLanIps();
    notifyListeners();
  }

  Future<bool> _ping() async {
    try {
      await LocalApi(baseUrl: baseUrl, timeout: const Duration(seconds: 2)).ping();
      return true;
    } on Object {
      return false;
    }
  }

  /// 更新运行状态：能连上且是我们拉起的 → managed；能连上 → external；否则 stopped。
  Future<void> refreshRuntime() async {
    final reachable = await _ping();
    if (!reachable) {
      // 端口连不上，但子进程还活着 → 可能正在启动或已卡死，保留 managed 便于界面给出判断。
      runtime = process.running ? ServerRuntime.managed : ServerRuntime.stopped;
    } else {
      runtime = process.running ? ServerRuntime.managed : ServerRuntime.external;
    }
    notifyListeners();
  }

  /// 启动本机服务端并等待可连接。返回 null 表示成功。
  Future<String?> startServer() async {
    _userStopped = false;
    if (exePath.isEmpty || workDir.isEmpty) {
      final guess = await guessServerPaths();
      if (guess == null) return '还没设置服务端位置';
      await saveServerPaths(guess.exe, guess.workDir);
    }

    final err = await process.start(exePath: exePath, workingDirectory: workDir);
    notifyListeners();
    if (err != null) return err;

    // 最多等 25 秒；服务端要连数据库、装路由，冷启动需要时间。
    final probe = LocalApi(baseUrl: baseUrl, timeout: const Duration(seconds: 2));
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (!process.running) return '服务端启动后立即退出了，请看启动输出';
      try {
        await probe.ping();
        _api = LocalApi(baseUrl: baseUrl);
        connectionError = null;
        runtime = ServerRuntime.managed;
        notifyListeners();
        return null;
      } on Object {
        // 还没起来，继续等
      }
    }
    await refreshRuntime();
    return '启动超时：25 秒内没连上 $baseUrl';
  }

  /// 停止服务端：优先走 `/local/admin/shutdown`（远端也能用），再兜底 kill 本地进程。
  Future<String?> stopServer() async {
    // 标记成"用户自己停的"，看门狗就不会立刻把它拉回来。
    _userStopped = true;
    try {
      final api = _api ??
          LocalApi(baseUrl: baseUrl, timeout: const Duration(seconds: 3));
      await api.shutdownServer();
    } on Object {
      // 远端已经挂了也无所谓，下面还有 kill 兜底。
    }

    if (process.running) {
      await process.stop();
    }

    // 等端口真正释放
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!await _ping()) break;
    }

    _api = null;
    runtime = ServerRuntime.stopped;
    notifyListeners();
    return null;
  }

  Future<String?> restartServer() async {
    _userStopped = false;
    await stopServer();
    _userStopped = false;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return startServer();
  }
}
