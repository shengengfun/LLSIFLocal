import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../server_control.dart';
import '../state.dart';
import '../theme.dart';

/// 总览页：服务端控制 + 网络与端口 + 数据规模 + 能力清单 + 终端输出。
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.state});

  final AppState state;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  final _portCtrl = TextEditingController();
  final _exeCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();

  Overview? _overview;
  String? _overviewError;

  ServerInfo? _info;
  String? _infoError;

  final List<LogLine> _logs = [];
  final Set<String> _seenLog = {};
  int _logSeq = 0;

  Timer? _timer;
  bool _busy = false;
  bool _autoScroll = true;
  bool _paused = false;
  bool _showLaunchLog = false;
  bool _portDirty = false;
  String? _actionError;
  String? _actionOk;

  final _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _exeCtrl.text = widget.state.exePath;
    _dirCtrl.text = widget.state.workDir;
    _portCtrl.text = '${widget.state.port}';
    _refreshOverview();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _timer?.cancel();
    _logScroll.dispose();
    _portCtrl.dispose();
    _exeCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _tick() async {
    if (_busy || _paused) return;
    final api = widget.state.api;
    if (api == null) return;

    try {
      final info = await api.serverInfo();
      if (mounted) setState(() => _info = info);
    } on Object catch (e) {
      if (mounted) setState(() => _infoError = '$e');
    }

    try {
      final page = await api.logs(after: _logSeq);
      _logSeq = page.next;
      if (page.lines.isNotEmpty && mounted) {
        setState(() {
          for (final line in page.lines) {
            if (_seenLog.add('${line.seq}')) _logs.add(line);
          }
          if (_logs.length > 1200) {
            _logs.removeRange(0, _logs.length - 1200);
          }
        });
        _stickToBottom();
      }
    } on Object catch (e) {
      if (mounted) setState(() => _infoError = '$e');
    }
  }

  void _stickToBottom() {
    if (!_autoScroll || !_logScroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  Future<void> _refreshOverview() async {
    final api = widget.state.api;
    if (api == null) return;
    try {
      final data = await api.overview();
      if (!mounted) return;
      setState(() {
        _overview = data;
        _overviewError = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _overviewError = '$e');
    }
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _actionError = null;
      _actionOk = null;
    });
    final err = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err != null) {
        _actionError = err;
      }
    });
    if (err == null) await _refreshOverview();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() => _run(() async {
        final err = await widget.state.startServer();
        if (err == null) _toast('服务端已启动');
        return err;
      });

  Future<void> _stop() => _run(() async {
        final err = await widget.state.stopServer();
        if (err == null) _toast('服务端已停止');
        return err;
      });

  Future<void> _restart() => _run(() async {
        final err = await widget.state.restartServer();
        if (err == null) _toast('服务端已重启');
        return err;
      });

  /// 用本机 IP 一键修正 cdn_server，避免 DHCP 换 IP 后客户端下载失败。
  Future<void> _fixCdn() async {
    final ip = widget.state.lanIps.isNotEmpty
        ? widget.state.lanIps.first
        : _info?.lanIps.isNotEmpty == true
            ? _info!.lanIps.first
            : '';
    if (ip.isEmpty) {
      setState(() => _actionError = '没探测到局域网 IP，先手动填 cdn_server');
      return;
    }
    final port = _info?.listenPort.isNotEmpty == true ? _info!.listenPort : '8080';
    await _run(() async {
      try {
        final r = await widget.state.api!
            .patchConfig(cdnServer: 'http://$ip:$port/static');
        setState(() => _actionOk = r.message);
        return null;
      } on Object catch (e) {
        return '$e';
      }
    });
  }

  Future<void> _saveServerPort() async {
    final text = _portCtrl.text.trim();
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 65535) {
      setState(() => _actionError = '端口必须是 1-65535 的整数');
      return;
    }
    await _run(() async {
      try {
        final r = await widget.state.api!.patchConfig(listenPort: '$value');
        setState(() {
          _actionOk = r.message;
          _portDirty = false;
        });
        return null;
      } on Object catch (e) {
        return '$e';
      }
    });
  }

  Future<void> _saveServerPortAndRestart() async {
    final text = _portCtrl.text.trim();
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 65535) {
      setState(() => _actionError = '端口必须是 1-65535 的整数');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.state.api!.patchConfig(listenPort: '$value');
    } on Object catch (e) {
      setState(() {
        _busy = false;
        _actionError = '$e';
      });
      return;
    }
    // 服务端换了端口，App 这边也得跟着改，否则重启后连不上。
    await widget.state.saveConnection(widget.state.host, value);
    setState(() {
      _busy = false;
      _portDirty = false;
    });
    await _restart();
  }

  Future<void> _saveConnection() async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null) {
      setState(() => _actionError = '端口不合法');
      return;
    }
    await widget.state.saveConnection(widget.state.host, port);
    final ok = await widget.state.connect();
    if (!mounted) return;
    setState(() {
      _actionError = ok ? null : widget.state.connectionError;
      _actionOk = ok ? '已重新连接' : null;
    });
  }

  Future<void> _applyPaths() async {
    await widget.state.saveServerPaths(
      _exeCtrl.text.trim(),
      _dirCtrl.text.trim(),
    );
    if (!mounted) return;
    _toast('服务端位置已保存');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;

    return RefreshIndicator(
      onRefresh: () async {
        await _tick();
        await _refreshOverview();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          _buildServerCard(colors),
          const SizedBox(height: 14),
          _buildNetworkCard(colors),
          const SizedBox(height: 14),
          _buildDataCard(colors),
          const SizedBox(height: 14),
          _buildCapabilityCard(colors),
          const SizedBox(height: 14),
          _buildTerminalCard(colors),
        ],
      ),
    );
  }

  Widget _buildServerCard(AppColors colors) {
    final state = widget.state;
    final info = _info;
    final (label, color) = switch (state.runtime) {
      ServerRuntime.managed => ('运行中 · 本App托管', colors.success),
      ServerRuntime.external => ('运行中 · 外部进程', colors.primary),
      ServerRuntime.stopped => ('已停止', colors.mutedForeground),
    };

    final canStart = state.process.supported &&
        state.runtime == ServerRuntime.stopped &&
        !_busy;
    final canStop = state.runtime != ServerRuntime.stopped && !_busy;
    final canRestart = state.runtime != ServerRuntime.stopped && !_busy;

    return _Card(
      title: '服务端',
      subtitle: state.runtime == ServerRuntime.external
          ? '当前服务端不是本 App 启动的，能连上就可以正常管理'
          : null,
      trailing: _StatusPill(label: label, color: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!state.connected) ...[
            _Hint(
              colors: colors,
              icon: Icons.wifi_off,
              text: '还没连上 ${state.baseUrl}'
                  '${state.connectionError == null ? '' : '（${state.connectionError}）'}'
                  '${state.autoStartError == null ? '' : '\n自动启动服务端失败：${state.autoStartError}'}',
              tint: colors.destructive,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (state.process.supported)
                  FilledButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('启动服务端'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final ok = await state.connect();
                            return ok
                                ? null
                                : (state.connectionError ?? '连接失败');
                          }),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试连接'),
                ),
              ],
            ),
            if (state.process.supported)
              Row(
                children: [
                  Switch(
                    value: state.autoStartServer,
                    onChanged: (v) => state.setAutoStart(v),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '打开 App 时自动拉起服务端'
                      '（${state.exePath.isEmpty ? '还没设置可执行文件' : state.exePath}）',
                      style: TextStyle(
                          fontSize: 11.5, color: colors.mutedForeground),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: canStart ? _start : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('启动服务'),
              ),
              OutlinedButton.icon(
                onPressed: canStop ? _stop : null,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('终止服务'),
              ),
              OutlinedButton.icon(
                onPressed: canRestart ? _restart : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('重启'),
              ),
            ],
          ),
          if (_infoError != null)
            _InlineError(message: '读取服务端信息失败：$_infoError'),
          if (!state.process.supported)
            _Hint(
              colors: colors,
              icon: Icons.info_outline,
              text: 'Android 不能直接运行 PC 版 honoka-chan.exe（它是 Windows 可执行文件），'
                  '所以这个平台上「启动服务端」不可用，只能连局域网里的 PC 服务端；'
                  '「终止服务」仍然可以调用服务端的关闭接口。',
            ),
          const SizedBox(height: 14),
          _KvTable(
            rows: [
              ('进程 PID', info == null ? '—' : '${info.pid}'),
              ('运行时长', info == null ? '—' : _duration(info.uptimeSec)),
              ('监听端口', info == null ? '—' : info.listenPort),
              ('服务端根目录', info == null ? '—' : info.root),
              ('可执行文件', info == null ? '—' : info.exePath),
              ('运行环境', info == null
                  ? '—'
                  : '${info.os}/${info.arch} · ${info.goVersion}'),
              ('包版本', info == null || info.packageVersion.isEmpty
                  ? '—'
                  : info.packageVersion),
            ],
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: '可执行文件',
            controller: _exeCtrl,
            hint: r'例如 D:\LLSIFLocal\honoka-chan-dev\honoka-chan.exe',
          ),
          const SizedBox(height: 10),
          _LabeledField(
            label: '工作目录',
            controller: _dirCtrl,
            hint: r'例如 D:\LLSIFLocal\honoka-chan-dev',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _applyPaths,
                child: const Text('保存路径'),
              ),
              TextButton(
                onPressed: () async {
                  final guess = await guessServerPaths();
                  if (guess == null) {
                    _toast('没找到 honoka-chan，请手动填写');
                    return;
                  }
                  setState(() {
                    _exeCtrl.text = guess.exe;
                    _dirCtrl.text = guess.workDir;
                  });
                },
                child: const Text('自动探测'),
              ),
            ],
          ),
          if (_actionError != null) _InlineError(message: _actionError!),
          if (_actionOk != null)
            _Hint(
              colors: colors,
              icon: Icons.check_circle_outline,
              text: _actionOk!,
              tint: colors.success,
            ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard(AppColors colors) {
    final info = _info;
    final ips = widget.state.lanIps.isNotEmpty
        ? widget.state.lanIps
        : (info?.lanIps ?? const <String>[]);
    final expected = ips.isEmpty ? '' : 'http://${ips.first}:${info?.listenPort ?? '8080'}/static';
    final mismatch = expected.isNotEmpty &&
        info != null &&
        info.cdnServer.isNotEmpty &&
        info.cdnServer != expected;

    return _Card(
      title: '网络与端口',
      subtitle: '客户端下载资源走 cdn_server，本机 IP 变了必须同步修改',
      trailing: IconButton(
        tooltip: '重新探测本机 IP',
        onPressed: () => widget.state.refreshLanIps(),
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('本机 IPv4'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ip in ips)
                _CopyChip(
                  text: ip,
                  label: ip,
                  onCopied: () => _toast('已复制 $ip'),
                ),
              if (ips.isEmpty)
                _Hint(
                  colors: colors,
                  icon: Icons.wifi_off,
                  text: '没探测到局域网 IPv4 地址',
                ),
            ],
          ),
          const SizedBox(height: 14),
          _KvTable(
            rows: [
              ('cdn_server', info?.cdnServer.isNotEmpty == true ? info!.cdnServer : '—'),
              ('数据目录', info == null || info.dataDb.isEmpty ? '—' : info.dataDb),
              ('账号库', info == null || info.mainDb.isEmpty ? '—' : info.mainDb),
            ],
          ),
          if (mismatch) ...[
            const SizedBox(height: 10),
            _Hint(
              colors: colors,
              icon: Icons.warning_amber_rounded,
              text: '客户端将要访问 $expected，与服务端当前配置不一致，'
                  '会导致资源下载失败。',
              tint: colors.destructive,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _fixCdn,
              icon: const Icon(Icons.build_circle_outlined, size: 18),
              label: Text('一键改为 $expected'),
            ),
          ],
          const SizedBox(height: 14),
          const _SectionLabel('设备连接（客户端走 localhost）'),
          _KvTable(
            rows: [
              (
                'adb 反向转发',
                !widget.state.adbReverse.supported
                    ? '本平台不适用（App 自己就是设备）'
                    : widget.state.adbForwardOk
                        ? '已就绪 tcp:${widget.state.port} → 本机 ${widget.state.port}'
                        : '未建立${widget.state.adbReverse.lastError == null ? '（没检测到设备或 adb）' : '：${widget.state.adbReverse.lastError}'}'
              ),
            ],
          ),
          if (widget.state.adbReverse.supported && !widget.state.adbForwardOk)
            _Hint(
              colors: colors,
              icon: Icons.usb,
              text: '客户端把服务端地址打成了 http://localhost，需要 adb 反向转发才能连到这台电脑。'
                  'App 每 5 秒会自动补一次；如果一直未就绪，检查 USB 调试是否开启、设备是否授权。',
            ),
          const SizedBox(height: 14),
          const _SectionLabel('服务端监听端口'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _portCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '端口'),
                  onChanged: (_) => setState(() => _portDirty = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _saveServerPort,
                      child: const Text('保存'),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _saveServerPortAndRestart,
                      child: const Text('保存并重启'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _Hint(
            colors: colors,
            icon: Icons.info_outline,
            text: _portDirty
                ? '改端口要重启服务端才生效；「保存并重启」会同时把 App 的连接端口改过去。'
                : '当前 App 连接地址：${widget.state.baseUrl}',
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _saveConnection,
                child: const Text('用此端口重新连接'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _portCtrl.text = '${widget.state.port}';
                  _portDirty = false;
                }),
                child: const Text('重置'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard(AppColors colors) {
    final o = _overview;
    if (_overviewError != null) {
      return _Card(
        title: '数据规模',
        child: _InlineError(message: _overviewError!),
      );
    }
    if (o == null) {
      return const _Card(
        title: '数据规模',
        child: SizedBox(
          height: 90,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return _Card(
      title: '数据规模',
      subtitle: 'Master 数据版本 ${o.appVersion}',
      trailing: IconButton(
        tooltip: '刷新',
        onPressed: _refreshOverview,
        icon: const Icon(Icons.refresh, size: 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatTile(label: '账号', value: '${o.userCount}', colors: colors),
              _StatTile(label: '部员模板', value: '${o.unitMaster}', colors: colors),
              _StatTile(label: '持有卡', value: '${o.cardOwned}', colors: colors),
              _StatTile(label: '饰品', value: '${o.accessories}', colors: colors),
              _StatTile(
                label: '乐曲（已解/总）',
                value: '${o.liveUnlocked}/${o.liveTotal}',
                colors: colors,
              ),
              _StatTile(label: '剧情', value: '${o.scenarios}', colors: colors),
              _StatTile(
                label: '磁盘可用',
                value: _bytes(o.diskFree),
                colors: colors,
              ),
            ],
          ),
          if (o.missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Hint(
              colors: colors,
              icon: Icons.report_gmailerrorred_outlined,
              text: '缺少主数据：${o.missing.join('、')}',
              tint: colors.destructive,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCapabilityCard(AppColors colors) {
    const caps = <({String label, bool ok, String note})>[
      (label: '账号与登录', ok: true, note: '手机号换绑、设备解绑'),
      (label: '玩家修改', ok: true, note: '等级/金币/爱心'),
      (label: '发卡与饰品', ok: true, note: '全量或指定 ID'),
      (label: '发道具', ok: true, note: '写 user_item_data，游戏内背包可见'),
      (label: '邮箱发件', ok: true, note: '礼物箱投递 / 撤回 / 领取'),
      (label: '乐曲上线', ok: true, note: '含活动曲，搬谱面文件实现'),
      (label: '谱面导入导出', ok: true, note: '导入自动备份'),
      (label: '自定义卡面', ok: false, note: '需外部 texb 加密步骤'),
      (label: '活动开关', ok: false, note: '缺 event_m 主数据'),
    ];
    return _Card(
      title: '能力清单',
      subtitle: '灰色表示还缺条件或没做，避免看到按钮以为能用',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in caps)
            _CapabilityChip(
              label: c.label,
              note: c.note,
              ok: c.ok,
              colors: colors,
            ),
        ],
      ),
    );
  }

  Widget _buildTerminalCard(AppColors colors) {
    final launchLines = widget.state.process.launchLog;
    final lines = _showLaunchLog ? launchLines : _logs.map((e) => e.text).toList();

    return _Card(
      title: '服务器终端输出',
      subtitle: _showLaunchLog
          ? '本 App 拉起进程时捕获的 stdout/stderr'
          : '服务端环形日志缓冲（/local/admin/logs），每 2 秒增量拉取',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniToggle(
            options: const ['服务端日志', '启动输出'],
            index: _showLaunchLog ? 1 : 0,
            onChanged: (i) => setState(() => _showLaunchLog = i == 1),
            colors: colors,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _paused ? '继续刷新' : '暂停刷新',
            onPressed: () => setState(() => _paused = !_paused),
            icon: Icon(
              _paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
              size: 18,
            ),
          ),
          IconButton(
            tooltip: _autoScroll ? '取消自动滚动' : '自动滚动到底部',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
              if (_autoScroll) _stickToBottom();
            },
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.swap_vert,
              size: 18,
            ),
          ),
          IconButton(
            tooltip: '复制全部',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: lines.join('\n')));
              _toast('已复制 ${lines.length} 行');
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
          ),
          IconButton(
            tooltip: '清空显示',
            onPressed: () => setState(() {
              _logs.clear();
              _seenLog.clear();
            }),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          ),
        ],
      ),
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          color: colors.isDark ? const Color(0xFF0D1014) : const Color(0xFF15202B),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.border.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: lines.isEmpty
            ? Center(
                child: Text(
                  _paused ? '已暂停' : '暂无输出',
                  style: const TextStyle(
                    color: Color(0xFF7A8794),
                    fontSize: 12,
                    fontFamily: AppFonts.mono,
                  ),
                ),
              )
            : ListView.builder(
                controller: _logScroll,
                itemCount: lines.length,
                itemBuilder: (context, i) {
                  final text = lines[i];
                  final kind = _showLaunchLog
                      ? (text.startsWith('!')
                          ? LogKind.error
                          : text.startsWith('>')
                              ? LogKind.notice
                              : LogKind.info)
                      : (_logs.length > i ? _logs[i].kind : LogKind.info);
                  return SelectableText(
                    text,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.5,
                      height: 1.5,
                      color: switch (kind) {
                        LogKind.error => const Color(0xFFFF8A8A),
                        LogKind.warn => const Color(0xFFF5C97B),
                        LogKind.notice => const Color(0xFF7FD1F5),
                        LogKind.info => const Color(0xFFC8D3DC),
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

String _duration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final m = seconds ~/ 60;
  if (m < 60) return '$m 分 ${seconds % 60} 秒';
  final h = m ~/ 60;
  return '$h 时 ${m % 60} 分';
}

String _bytes(int v) {
  if (v <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = v.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _KvTable extends StatelessWidget {
  const _KvTable({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    k,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    v,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: colors.isDark ? 0.6 : 0.85),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.label,
    required this.note,
    required this.ok,
    required this.colors,
  });

  final String label;
  final String note;
  final bool ok;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final tint = ok ? colors.success : colors.mutedForeground;
    return Tooltip(
      message: note,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: ok ? 0.12 : 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.remove_circle_outline,
              size: 13,
              color: tint,
            ),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11.5, color: tint)),
          ],
        ),
      ),
    );
  }
}

class _CopyChip extends StatelessWidget {
  const _CopyChip({
    required this.text,
    required this.label,
    required this.onCopied,
  });

  final String text;
  final String label;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.lan_outlined, size: 14),
      label: Text(label),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: text));
        onCopied();
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.colors,
    required this.icon,
    required this.text,
    this.tint,
  });

  final AppColors colors;
  final IconData icon;
  final String text;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? colors.mutedForeground;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, height: 1.45, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: hint),
      style: const TextStyle(fontSize: 12.5),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.options,
    required this.index,
    required this.onChanged,
    required this.colors,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: colors.isDark ? 0.7 : 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: i == index ? colors.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  options[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                    color: i == index ? colors.foreground : colors.mutedForeground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
