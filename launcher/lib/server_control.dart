import 'dart:io';

/// 服务端自身状态（对应 `GET /local/admin/server`）。
class ServerInfo {
  const ServerInfo({
    required this.pid,
    required this.uptimeSec,
    required this.root,
    required this.exePath,
    required this.goVersion,
    required this.os,
    required this.arch,
    required this.listenPort,
    required this.cdnServer,
    required this.packageVersion,
    required this.dataDb,
    required this.mainDb,
    required this.lanIps,
    required this.userCount,
  });

  final int pid;
  final int uptimeSec;
  final String root;
  final String exePath;
  final String goVersion;
  final String os;
  final String arch;
  final String listenPort;
  final String cdnServer;
  final String packageVersion;
  final String dataDb;
  final String mainDb;
  final List<String> lanIps;
  final int userCount;

  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
        pid: _int(j['pid']),
        uptimeSec: _int(j['uptime_sec']),
        root: _str(j['root']),
        exePath: _str(j['exe_path']),
        goVersion: _str(j['go_version']),
        os: _str(j['os']),
        arch: _str(j['arch']),
        listenPort: _str(j['listen_port']),
        cdnServer: _str(j['cdn_server']),
        packageVersion: _str(j['package_version']),
        dataDb: _str(j['data_db']),
        mainDb: _str(j['main_db']),
        lanIps: (j['lan_ips'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        userCount: _int(j['user_count']),
      );
}

/// 一条服务端输出。
class LogLine {
  const LogLine({required this.seq, required this.ts, required this.text});

  final int seq;
  final int ts;
  final String text;

  factory LogLine.fromJson(Map<String, dynamic> j) => LogLine(
        seq: _int(j['seq']),
        ts: _int(j['ts']),
        text: _str(j['text']),
      );

  /// 日志级别只用于配色，判断规则与参考项目 OutputPanel 一致。
  LogKind get kind {
    final t = text;
    if (RegExp(r'\berror\b|panic|failed|失败|错误', caseSensitive: false)
        .hasMatch(t)) {
      return LogKind.error;
    }
    if (RegExp(r'\bwarn|warning|警告', caseSensitive: false).hasMatch(t)) {
      return LogKind.warn;
    }
    if (t.startsWith('[update]')) return LogKind.notice;
    return LogKind.info;
  }
}

enum LogKind { info, notice, warn, error }

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String _str(dynamic v) => v?.toString() ?? '';

/// 本机网卡 IPv4 地址（App 侧探测，用于提示该填哪个 cdn_server）。
Future<List<NetworkInterface>> _allInterfaces() => NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

/// 返回本机可用于局域网访问的 IPv4 地址，按「像内网地址」优先排序。
Future<List<String>> localLanIps() async {
  try {
    final result = <String>[];
    for (final iface in await _allInterfaces()) {
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip == '127.0.0.1') continue;
        result.add(ip);
      }
    }
    result.sort((a, b) {
      int score(String ip) {
        if (ip.startsWith('192.168.')) return 0;
        if (ip.startsWith('10.')) return 1;
        if (ip.startsWith('172.')) return 2;
        return 3;
      }

      final d = score(a) - score(b);
      return d != 0 ? d : a.compareTo(b);
    });
    return result;
  } on Object {
    return const [];
  }
}

/// 管理 `adb reverse tcp:<port> tcp:<port>`。
///
/// 客户端把服务端地址打成了 `http://localhost`，所以要靠 adb 的反向转发
/// 把手机的 localhost 接到电脑上。问题是这个转发**只是 adb 进程的状态**：
/// adb 重启、设备重新插拔、换 USB 口都会丢，丢了就是「网络请求超时」。
/// 所以这里不指望它一直活着，而是定期检查、丢了就补回来。
class AdbReverse {
  AdbReverse({this.adbPath, this.port = 8080});

  /// adb 可执行文件路径；为空时从 PATH 里找。
  String? adbPath;
  final int port;

  String? _resolved;
  String? lastError;
  bool lastOk = false;

  /// 只在桌面端有意义（Android 端自己就是设备）。
  bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<String?> _adb() async {
    if (_resolved != null) return _resolved;
    if (adbPath != null && File(adbPath!).existsSync()) {
      _resolved = adbPath;
      return _resolved;
    }
    for (final candidate in _guessAdbPaths()) {
      if (File(candidate).existsSync()) {
        _resolved = candidate;
        return _resolved;
      }
    }
    try {
      // PATH 里有就直接用名字。
      final r = await Process.run('adb', ['version']);
      if (r.exitCode == 0) {
        _resolved = 'adb';
        return _resolved;
      }
    } on Object {
      // 没有 adb 就算了，不当作错误。
    }
    _resolved = '';
    return null;
  }

  /// 常见安装位置：本项目自带的 android-sdk，以及 Flutter/Android Studio 默认路径。
  List<String> _guessAdbPaths() {
    final sep = Platform.pathSeparator;
    final out = <String>[];
    final env = Platform.environment;
    final roots = <String?>[
      env['ANDROID_SDK_ROOT'],
      env['ANDROID_HOME'],
      env['LOCALAPPDATA'] == null
          ? null
          : '${env['LOCALAPPDATA']}${sep}Android${sep}Sdk',
      env['USERPROFILE'] == null
          ? null
          : '${env['USERPROFILE']}${sep}AppData${sep}Local${sep}Android${sep}Sdk',
    ];
    for (final root in roots) {
      if (root == null || root.isEmpty) continue;
      out.add('$root${sep}platform-tools${sep}adb${Platform.isWindows ? '.exe' : ''}');
    }
    // 项目内 SDK：从当前目录与 App 目录向上找 android-sdk\platform-tools\adb.exe
    for (final start in [Directory.current, File(Platform.resolvedExecutable).parent]) {
      var dir = start;
      for (var i = 0; i < 6; i++) {
        out.add('$dir.path${sep}android-sdk${sep}platform-tools$sep'
            'adb${Platform.isWindows ? ".exe" : ""}');
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return out;
  }

  /// 检查设备是否连着（`adb devices` 里有一行 `device`）。
  Future<bool> deviceReady() async {
    final adb = await _adb();
    if (adb == null) return false;
    try {
      final r = await Process.run(adb, ['devices']);
      final text = '${r.stdout}';
      return text
          .split('\n')
          .any((l) => l.trim().endsWith('\tdevice') || l.trim().endsWith(' device'));
    } on Object catch (e) {
      lastError = '$e';
      return false;
    }
  }

  /// 确保转发存在。返回 true 表示当前可用。
  Future<bool> ensure() async {
    if (!supported) return false;
    final adb = await _adb();
    if (adb == null) {
      lastError = '没找到 adb';
      lastOk = false;
      return false;
    }
    try {
      final list = await Process.run(adb, ['reverse', '--list']);
      final has = '${list.stdout}'.contains('tcp:$port tcp:$port');
      if (!has) {
        final add = await Process.run(
            adb, ['reverse', 'tcp:$port', 'tcp:$port']);
        if (add.exitCode != 0) {
          lastError = '${add.stderr}'.trim();
          lastOk = false;
          return false;
        }
      }
      lastError = null;
      lastOk = true;
      return true;
    } on Object catch (e) {
      lastError = '$e';
      lastOk = false;
      return false;
    }
  }
}

/// 服务端托管状态。
enum ServerRuntime {  /// 由本 App 拉起的子进程。
  managed,

  /// 能连上，但不是本 App 拉起的（别人 / 开机脚本启动）。
  external,

  /// 连不上。
  stopped,
}

/// 猜测服务端可执行文件与工作目录。
///
/// Windows 开发布局：`<root>/honoka-chan-dev/honoka-chan.exe`；
/// 而 App 的可执行文件在 `<root>/srvapp/build/windows/x64/runner/Release/`。
/// 所以从 App 目录和当前目录分别向上找，命中 `honoka-chan-dev/<exe>` 即返回。
Future<({String exe, String workDir})?> guessServerPaths() async {
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return null;
  final exeName = Platform.isWindows ? 'honoka-chan.exe' : 'honoka-chan';
  const dirName = 'honoka-chan-dev';

  final starts = <Directory>[
    Directory.current,
    File(Platform.resolvedExecutable).parent,
  ];

  for (final start in starts) {
    var dir = start;
    for (var i = 0; i < 8; i++) {
      final candidate = File('${dir.path}${Platform.pathSeparator}$dirName'
          '${Platform.pathSeparator}$exeName');
      if (await candidate.exists()) {
        return (
          exe: candidate.path,
          workDir:
              '${dir.path}${Platform.pathSeparator}$dirName',
        );
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return null;
}

/// 管理本 App 拉起的 honoka-chan 子进程。
///
/// Android 上无法执行 PC 的 exe，`supported` 为 false，界面会禁用相关按钮
/// 并说明原因；此时仍可通过 `/local/admin/shutdown` 停掉远端服务端。
class ServerProcess {
  Process? _process;
  final List<String> launchLog = [];
  static const _maxLaunchLog = 500;

  bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get running => _process != null;
  int? get pid => _process?.pid;

  String get defaultExePath {
    if (Platform.isWindows) return r'honoka-chan-dev\honoka-chan.exe';
    return 'honoka-chan-dev/honoka-chan';
  }

  /// 启动服务端。返回 null 表示成功，否则返回错误说明。
  Future<String?> start({
    required String exePath,
    required String workingDirectory,
  }) async {
    if (!supported) return '当前平台不能启动本机服务端';
    if (_process != null) return '服务端已在运行';

    final exe = File(exePath);
    if (!await exe.exists()) return '找不到可执行文件：$exePath';

    final dir = Directory(workingDirectory);
    if (!await dir.exists()) return '工作目录不存在：$workingDirectory';

    launchLog
      ..clear()
      ..add('> 启动 $exePath');
    try {
      final proc = await Process.start(
        exePath,
        const [],
        workingDirectory: workingDirectory,
        runInShell: false,
      );
      _process = proc;
      _capture(proc);
      return null;
    } on Object catch (e) {
      launchLog.add('! 启动失败：$e');
      return '启动失败：$e';
    }
  }

  void _capture(Process proc) {
    void push(String line) {
      if (line.trim().isEmpty) return;
      launchLog.add(line);
      if (launchLog.length > _maxLaunchLog) {
        launchLog.removeRange(0, launchLog.length - _maxLaunchLog);
      }
    }

    proc.stdout
        .transform(const SystemEncoding().decoder)
        .listen(push, onError: (Object e) => push('! stdout: $e'));
    proc.stderr
        .transform(const SystemEncoding().decoder)
        .listen(push, onError: (Object e) => push('! stderr: $e'));
    // 进程退出后清掉句柄，界面据此回到「未运行」。
    proc.exitCode.then((code) {
      push('> 进程已退出，code=$code');
      _process = null;
    });
  }

  /// 停止本 App 拉起的进程。
  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    proc.kill();
    try {
      await proc.exitCode.timeout(const Duration(seconds: 5));
    } on Object {
      proc.kill(ProcessSignal.sigkill);
    }
    _process = null;
  }
}
