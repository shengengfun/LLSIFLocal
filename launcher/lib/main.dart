import 'dart:io';

import 'package:flutter/material.dart';

import 'pages/cards_page.dart';
import 'pages/custom_cards_page.dart';
import 'pages/lives_page.dart';
import 'pages/overview_page.dart';
import 'pages/players_page.dart';
import 'pages/tools_page.dart';
import 'server_control.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// 启动流程刻意做成「先出界面，再加载数据」。
///
/// 之前是 `await state.load(); runApp(...)` —— 只要 load() 里任何一步抛异常
/// （或卡住），就一帧都不渲染，用户看到的是纯白屏且没有任何线索。
/// 现在：立刻画启动页 → 后台 load() → 成功进主界面 / 失败进错误页，
/// 并把异常写进 startup_error.txt 方便事后定位。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 留痕：能区分「Dart 根本没跑起来」和「跑起来但卡在某一步」。
  writeStartupMarker('dart-main-entered');

  // 渲染期异常也显式画出来，别退化成灰块/白屏。
  ErrorWidget.builder = (details) => StartupIssueView(
        title: '界面渲染出错',
        message: details.exceptionAsString(),
        detail: '${details.stack ?? ''}',
      );

  runApp(const LauncherBoot());
}

class LauncherBoot extends StatefulWidget {
  const LauncherBoot({super.key});

  @override
  State<LauncherBoot> createState() => _LauncherBootState();
}

class _LauncherBootState extends State<LauncherBoot> {
  final AppState _state = AppState();
  Object? _error;
  StackTrace? _stack;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _state.load();
      if (mounted) setState(() => _ready = true);
    } on Object catch (e, st) {
      writeStartupError(e, st);
      if (mounted) {
        setState(() {
          _error = e;
          _stack = st;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    if (_ready) return AdminApp(state: _state);
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(colors),
        home: Scaffold(
          backgroundColor: colors.background,
          body: StartupIssueView(
            title: '启动失败',
            message: '$_error',
            detail: '${_stack ?? ''}\n\n已写入 ${startupErrorPath()}',
          ),
        ),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(colors),
      home: Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('LLSIF 本地服务端',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.foreground)),
              const SizedBox(height: 14),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(height: 12),
              Text('正在启动…',
                  style:
                      TextStyle(fontSize: 12, color: colors.mutedForeground)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 启动期出错的兜底展示：把异常本身显示出来，可全选复制。
class StartupIssueView extends StatelessWidget {
  const StartupIssueView({
    super.key,
    required this.title,
    required this.message,
    required this.detail,
  });

  final String title;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(message,
                style: const TextStyle(fontSize: 13, color: Colors.white)),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  detail,
                  style: const TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'monospace',
                      color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('把这段内容发给开发者即可定位',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

/// 启动错误落盘位置：优先写到进程缓存目录（一定可写、`adb run-as` 可读），
/// 桌面写到当前目录。
String startupErrorPath() {
  if (Platform.isAndroid) {
    return '${Directory.systemTemp.path}${Platform.pathSeparator}startup_error.txt';
  }
  return '${Directory.current.path}${Platform.pathSeparator}startup_error.txt';
}

void writeStartupError(Object error, StackTrace? stack) {
  final body = '${DateTime.now().toIso8601String()}\n'
      'platform: ${Platform.operatingSystem} ${Platform.version}\n'
      'error: $error\n\nstack:\n${stack ?? ''}\n';
  // 同时打日志：logcat 里 tag=flutter 能直接看到，不依赖文件写成功。
  debugPrint('STARTUP-ERROR: $error');
  debugPrint('$stack');
  for (final path in startupErrorPaths()) {
    try {
      final f = File(path);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(body, flush: true);
      debugPrint('启动错误已写入 $path');
      return;
    } on Object catch (e) {
      debugPrint('写入启动错误日志失败 $path: $e');
    }
  }
}

/// 候选落盘路径，按可读性从高到低。
List<String> startupErrorPaths() {
  if (!Platform.isAndroid) {
    return ['${Directory.current.path}${Platform.pathSeparator}startup_error.txt'];
  }
  final out = <String>['${Directory.systemTemp.path}/startup_error.txt'];
  // 外部私有目录：桌面端 adb 免 run-as 直接 cat，但 Android 11+ 由系统托管，
  // 万一写不进去就退回缓存目录。
  for (final base in androidServerRootCandidates()) {
    final cut = base.lastIndexOf('/files/');
    if (cut > 0) out.add('${base.substring(0, cut + '/files'.length)}/startup_error.txt');
  }
  return out;
}

/// 启动阶段留痕：能区分「Dart 没跑起来」和「跑起来但卡在某一步」。
void writeStartupMarker(String stage) {
  debugPrint('STARTUP-MARKER: $stage');
  try {
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}startup_stage.txt');
    f.writeAsStringSync('${DateTime.now().toIso8601String()} $stage\n', flush: true);
  } on Object catch (_) {
    // 留痕失败不影响启动
  }
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final colors = state.darkMode ? AppColors.dark : AppColors.light;
        return MaterialApp(
          title: 'LLSIF 本地服务端',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(colors),
          home: AppBackdrop(
            colors: colors,
            child: HomeShell(state: state),
          ),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations =
      <({String label, IconData icon, IconData selected})>[
    (label: '总览', icon: Icons.dashboard_outlined, selected: Icons.dashboard),
    (label: '账号', icon: Icons.people_outline, selected: Icons.people),
    (label: '卡池', icon: Icons.style_outlined, selected: Icons.style),
    (label: '造卡', icon: Icons.palette_outlined, selected: Icons.palette),
    (label: '乐曲', icon: Icons.music_note_outlined, selected: Icons.music_note),
    (label: '工具', icon: Icons.build_outlined, selected: Icons.build),
  ];

  Widget _page() {
    final api = widget.state.api;
    return switch (_index) {
      0 => OverviewPage(key: const PageStorageKey('overview'), state: widget.state),
      1 => api == null
          ? const EmptyView(
              message: '还没连上服务端，请到「总览」页连接', icon: Icons.wifi_off)
          : PlayersPage(key: const PageStorageKey('players'), api: api),
      2 => api == null
          ? const EmptyView(
              message: '还没连上服务端，请到「总览」页连接', icon: Icons.wifi_off)
          : CardsPage(
              key: const PageStorageKey('cards'), api: api, state: widget.state),
      3 => api == null
          ? const EmptyView(
              message: '还没连上服务端，请到「总览」页连接', icon: Icons.wifi_off)
          : CustomCardsPage(
              key: const PageStorageKey('custom_cards'),
              api: api,
              state: widget.state),
      4 => api == null
          ? const EmptyView(
              message: '还没连上服务端，请到「总览」页连接', icon: Icons.wifi_off)
          : LivesPage(key: const PageStorageKey('lives'), api: api),
      _ => ToolsPage(key: const PageStorageKey('tools'), state: widget.state),
    };
  }

  /// 顶栏右侧：本机 IP、连接地址、深浅色、断开。
  List<Widget> _actions(BuildContext context) {
    final state = widget.state;
    final ip = state.lanIps.isNotEmpty ? state.lanIps.first : null;
    return [
      if (ip != null)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              ip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      Center(
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
            state.baseUrl,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      IconButton(
        tooltip: state.darkMode ? '切换到浅色' : '切换到深色',
        icon: Icon(state.darkMode ? Icons.light_mode : Icons.dark_mode, size: 18),
        onPressed: () => state.setDarkMode(!state.darkMode),
      ),
      IconButton(
        tooltip: '断开连接',
        icon: const Icon(Icons.logout, size: 18),
        onPressed: () => state.disconnect(),
      ),
      const SizedBox(width: 6),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = _page();

    if (!wide) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_destinations[_index].label),
          actions: _actions(context),
        ),
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      // 宽屏分支整条 Row 之前没有 SafeArea：NavigationRail 一直顶到屏幕
      // 最上沿，在带刘海/挖孔的平板与桌面上，顶部的云图标会被状态栏压住
      // （窄屏分支第 361 行已有 SafeArea，这里对齐）。
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 横屏手机只有 ~390dp 高，6 个目的地 + 顶部图标放不下，
            // 「乐曲 / 工具」会被裁掉（社区谱面入口就在乐曲页）。
            // 矮屏改成「不显示文字」并把 rail 变成可滚动：
            // 各项等高、位置稳定（tooltip 仍能看到名字），每一项都点得到。
            final short = constraints.maxHeight < 480;
            final rail = NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: short
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Icon(Icons.cloud_circle, size: 28),
              ),
              trailing: short
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: IconButton(
                        tooltip: '断开连接',
                        icon: const Icon(Icons.logout, size: 18),
                        onPressed: () => widget.state.disconnect(),
                      ),
                    )
                  : Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IconButton(
                            tooltip: '断开连接',
                            icon: const Icon(Icons.logout, size: 18),
                            onPressed: () => widget.state.disconnect(),
                          ),
                        ),
                      ),
                    ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            );
            return Row(
              children: [
                if (short)
                  SizedBox(
                    width: 88,
                    child: SingleChildScrollView(child: rail),
                  )
                else
                  rail,
                const VerticalDivider(width: 1),
                Expanded(
                  child: Scaffold(
                    backgroundColor: Colors.transparent,
                    appBar: AppBar(
                      title: Text(_destinations[_index].label),
                      actions: _actions(context),
                    ),
                    body: body,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
