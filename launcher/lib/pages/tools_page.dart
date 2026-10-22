import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.state});

  final AppState state;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCardArts();
    _loadNewUserSetting();
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  String _cardArtDir = '';
  List<CardArtItem> _cardArts = const [];
  bool _cardArtLoading = false;

  bool _newUserVanilla = true;
  int _newUserUnit = 31;
  int _sampleUserId = 0;
  int _sampleLevel = 0;
  int _sampleUnits = 0;
  bool _newUserBusy = false;

  Future<void> _loadNewUserSetting() async {
    final api = widget.state.api;
    if (api == null) return;
    try {
      final r = await api.newUserSetting();
      if (!mounted) return;
      setState(() {
        _newUserVanilla = r.vanilla;
        _newUserUnit = r.initialUnitId;
        _sampleUserId = r.sampleUserId;
        _sampleLevel = r.sampleLevel;
        _sampleUnits = r.sampleUnitCount;
      });
    } catch (_) {
      // 老服务端没有这个接口，忽略即可。
    }
  }

  Future<void> _setNewUserMode(bool vanilla) async {
    final api = widget.state.api;
    if (api == null) return;
    setState(() => _newUserBusy = true);
    try {
      final msg = await api.setNewUserSetting(vanilla: vanilla);
      if (!mounted) return;
      setState(() => _newUserVanilla = vanilla);
      showSnack(context, msg);
      await _loadNewUserSetting();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _newUserBusy = false);
    }
  }

  /// 新号模式：原版从零 / 满配。只影响此后新建的账号。
  Widget _buildNewUserCard() {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新号模式', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              _newUserVanilla
                  ? '原版从零：等级 1、LP 25、金币 0，只持有 1 张初始卡'
                      '（unit_id=$_newUserUnit），无饰品。其余卡和道具用「账号 → 发放」补。'
                  : '满配：建号即等级 1028、金币 1.1 亿、持有全部卡与全部饰品（旧行为）。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Switch(
                  value: _newUserVanilla,
                  onChanged: _newUserBusy ? null : _setNewUserMode,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _newUserVanilla ? '按原版从零开始（推荐）' : '直接拉满',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (_sampleUserId > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '对照：最近一个账号（no.$_sampleUserId）等级 $_sampleLevel、'
                  '持有 $_sampleUnits 张卡',
                  style: TextStyle(
                      fontSize: 11.5, color: colors.mutedForeground),
                ),
              ),
            Text(
              '开关只影响之后新建的账号，已有账号不会被改动。',
              style:
                  TextStyle(fontSize: 11.5, color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCardArts() async {
    final api = widget.state.api;
    if (api == null) return;
    setState(() => _cardArtLoading = true);
    try {
      final r = await api.cardArts();
      if (!mounted) return;
      setState(() {
        _cardArts = r.items;
        _cardArtDir = r.dir;
      });
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _cardArtLoading = false);
    }
  }

  Future<void> _deleteCardArt(CardArtItem item) async {
    final api = widget.state.api;
    if (api == null) return;
    try {
      await api.deleteCardArt(item.name);
      if (!mounted) return;
      showSnack(context, '已删除 ${item.name}');
      await _loadCardArts();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    }
  }

  /// 卡面库：PNG 收料目录。真正能被客户端读的是加密后的 texb，
  /// 所以这里给出一键可复制的转换命令，而不是假装能直接替换。
  Widget _buildCardArtCard() {
    final dir = _cardArtDir.isEmpty ? '（点刷新获取目录）' : _cardArtDir;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('自定义卡面库', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _cardArtLoading ? null : _loadCardArts,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '把 PNG 放进服务端的 cardart 目录即可在这里看到；'
              '客户端实际读的是加密 texb，需要用 tools/texb.py + honoka2 转一次。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: dir));
                if (!mounted) return;
                showSnack(context, '目录已复制');
              },
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dir,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  const Icon(Icons.copy, size: 14),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_cardArts.isEmpty)
              Text(
                _cardArtLoading ? '读取中…' : '还没有自定义卡面',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (final c in _cardArts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined, size: 18),
                  title: Text(c.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    '${c.width}×${c.height} · ${formatBytes(c.size)} · ${c.updatedAt}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: '删除',
                    onPressed: () => _deleteCardArt(c),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _cardArtLoading ? null : _loadCardArts,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('扫描卡面目录'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(
                      text: 'python tools/texb.py encode --png <PNG> '
                          '--template <原版.texb> --out <输出.texb>\n'
                          'honoka2.exe -e -c <输出.texb>',
                    ));
                    if (!mounted) return;
                    showSnack(context, '转换命令已复制');
                  },
                  icon: const Icon(Icons.terminal, size: 18),
                  label: const Text('复制 texb 转换命令'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switch() async {
    final api = widget.state.api;
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.switchAccount(_phone.text.trim(), _password.text);
      if (!mounted) return;
      showSnack(context, '已切换，客户端重启后生效');
      _password.clear();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbind() async {
    final api = widget.state.api;
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑设备？'),
        content: const Text('解绑后客户端下次启动会回到原生登录页。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('解绑')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await api.unbind();
      if (!mounted) return;
      showSnack(context, '已解绑');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAccounts() async {
    final api = widget.state.api;
    if (api == null) return;
    setState(() => _busy = true);
    List<AccountItem> accounts = const [];
    String? error;
    try {
      accounts = await api.accounts();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('账号一览'),
        content: SizedBox(
          width: 420,
          child: error != null
              ? Text(error)
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in accounts)
                      ListTile(
                        dense: true,
                        title: Text('${a.name}（${a.phone}）'),
                        subtitle: Text('ID ${a.userId} · Lv.${a.level}'),
                        trailing: a.bound
                            ? const Icon(Icons.smartphone, size: 16)
                            : null,
                        onTap: () {
                          _phone.text = a.phone;
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _copyPingUrl() async {
    final url = '${widget.state.baseUrl}/local/ping';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showSnack(context, '??? $url');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('快速切换账号', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '校验手机号 + 密码后，把该账号登记为下一台登录设备的目标账号。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _switch(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _switch,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('切换'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _showAccounts,
                      icon: const Icon(Icons.list),
                      label: const Text('账号一览'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('解绑设备'),
                subtitle: const Text('让客户端回到原生登录页'),
                onTap: _busy ? null : _unbind,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: const Text('当前连接'),
                subtitle: Text(state.baseUrl),
                trailing: TextButton(
                  onPressed: state.disconnect,
                  child: const Text('断开'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制接口地址'),
                subtitle: const Text('方便用 curl / 浏览器排查'),
                onTap: _copyPingUrl,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildNewUserCard(),
        const SizedBox(height: 12),
        _buildCardArtCard(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('关于', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'LLSIF 本地服务端管理端，Windows 与 Android 共用同一套 UI。\n'
                  '服务端本体（honoka-chan）单独运行，本应用通过 /local/* 接口管理它。',
                ),
                const SizedBox(height: 8),
                Text(
                  '提示：Android 需要与 PC 同网段；Windows 可直接连 127.0.0.1。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
