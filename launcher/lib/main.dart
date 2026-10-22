import 'package:flutter/material.dart';

import 'pages/cards_page.dart';
import 'pages/lives_page.dart';
import 'pages/overview_page.dart';
import 'pages/players_page.dart';
import 'pages/tools_page.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(AdminApp(state: state));
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
          : CardsPage(key: const PageStorageKey('cards'), api: api),
      3 => api == null
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
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Icon(Icons.cloud_circle, size: 28),
            ),
            trailing: Expanded(
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
          ),
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
      ),
    );
  }
}
