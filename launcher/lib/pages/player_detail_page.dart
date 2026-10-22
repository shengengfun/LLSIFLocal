import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';

class PlayerDetailPage extends StatefulWidget {
  const PlayerDetailPage({super.key, required this.api, required this.userId});

  final LocalApi api;
  final int userId;

  @override
  State<PlayerDetailPage> createState() => _PlayerDetailPageState();
}

class _PlayerDetailPageState extends State<PlayerDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  Player? _player;
  List<BackupItem> _backups = const [];
  String? _error;
  bool _loading = false;
  bool _saving = false;

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _level = TextEditingController();
  final _exp = TextEditingController();
  final _nextExp = TextEditingController();
  final _gameCoin = TextEditingController();
  final _snsCoin = TextEditingController();
  final _energyMax = TextEditingController();
  final _overMax = TextEditingController();

  final _grantUnitIds = TextEditingController();
  final _grantAccessoryIds = TextEditingController();
  final _itemSpec = TextEditingController();

  List<MailBoxItem> _mailItems = const [];
  int _mailPending = 0;

  /// 投递到礼物箱时把 ID 当作部员（1000）而不是道具（3001）。
  bool _mailAsUnit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _name,
      _desc,
      _level,
      _exp,
      _nextExp,
      _gameCoin,
      _snsCoin,
      _energyMax,
      _overMax,
      _grantUnitIds,
      _grantAccessoryIds,
      _itemSpec,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Player p) {
    _name.text = p.name;
    _desc.text = p.desc;
    _level.text = '${p.level}';
    _exp.text = '${p.exp}';
    _nextExp.text = '${p.nextExp}';
    _gameCoin.text = '${p.gameCoin}';
    _snsCoin.text = '${p.snsCoin}';
    _energyMax.text = '${p.energyMax}';
    _overMax.text = '${p.overMaxEnergy}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await widget.api.player(widget.userId);
      List<BackupItem> backups = const [];
      try {
        backups = await widget.api.backups(widget.userId);
      } catch (_) {
        // 备份接口单独失败不影响主信息展示。
      }
      if (!mounted) return;
      setState(() {
        _player = p;
        _backups = backups;
      });
      _fill(p);
      await _loadMail();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    int? asInt(TextEditingController c) => int.tryParse(c.text.trim());
    final patch = <String, Object?>{
      'name': _name.text.trim().isEmpty ? null : _name.text.trim(),
      'desc': _desc.text,
      'level': asInt(_level),
      'exp': asInt(_exp),
      'next_exp': asInt(_nextExp),
      'game_coin': asInt(_gameCoin),
      'sns_coin': asInt(_snsCoin),
      'energy_max': asInt(_energyMax),
      'over_max_energy': asInt(_overMax),
    };
    setState(() => _saving = true);
    try {
      final p = await widget.api.patchPlayer(widget.userId, patch);
      if (!mounted) return;
      setState(() => _player = p);
      _fill(p);
      showSnack(context, '已保存，客户端需重新登录才生效');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _grantUnits({bool all = false}) async {
    setState(() => _saving = true);
    try {
      final ids = _grantUnitIds.text
          .split(RegExp(r'[^0-9]+'))
          .where((s) => s.isNotEmpty)
          .map(int.parse)
          .toList();
      final n = await widget.api.grantUnits(widget.userId, ids: ids, all: all);
      if (!mounted) return;
      showSnack(context, '已发放 $n 张卡');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _grantAccessories({bool all = false}) async {
    setState(() => _saving = true);
    try {
      final ids = _grantAccessoryIds.text
          .split(RegExp(r'[^0-9]+'))
          .where((s) => s.isNotEmpty)
          .map(int.parse)
          .toList();
      final n =
          await widget.api.grantAccessories(widget.userId, ids: ids, all: all);
      if (!mounted) return;
      showSnack(context, '已发放 $n 件饰品');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _grantItems(bool toMail) async {
    final items = _parseItems();
    if (items.isEmpty) {
      showSnack(context, '没解析出道具 ID，格式如 4*10, 5', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (toMail) {
        final addType = _mailAsUnit ? 1000 : 3001;
        final n = await widget.api.sendMail(
          widget.userId,
          subject: '管理员赠送',
          items: [
            for (final it in items)
              (addType: addType, itemId: it.itemId, amount: it.amount)
          ],
        );
        if (!mounted) return;
        showSnack(context, '已投递 $n 条邮件，进游戏后可在礼物箱领取');
        await _loadMail();
      } else {
        final n = await widget.api.grantItems(widget.userId, items);
        if (!mounted) return;
        showSnack(context, '已发放 $n 种道具到背包');
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadMail() async {
    try {
      final r = await widget.api.mailBox(widget.userId);
      if (!mounted) return;
      setState(() {
        _mailItems = r.items;
        _mailPending = r.pending;
      });
    } catch (_) {
      // 礼物箱读失败不阻塞其它信息展示。
    }
  }

  Future<void> _deleteMail(int presentBoxId) async {
    setState(() => _saving = true);
    try {
      await widget.api.deleteMail(widget.userId, presentBoxId);
      await _loadMail();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _backup() async {
    setState(() => _saving = true);
    try {
      await widget.api.createBackup(widget.userId);
      await _load();
      if (!mounted) return;
      showSnack(context, '备份完成');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restore([String file = '']) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复存档？'),
        content: Text(
          file.isEmpty
              ? '将用最新一份备份覆盖该账号的全部数据。\n恢复前会自动留存当前状态。'
              : '将用 $file 覆盖该账号的全部数据。\n恢复前会自动留存当前状态。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await widget.api.restoreBackup(widget.userId, file: file);
      await _load();
      if (!mounted) return;
      showSnack(context, '已恢复');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? '玩家 ${widget.userId}' : p.name),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '属性', icon: Icon(Icons.tune, size: 18)),
            Tab(text: '发放', icon: Icon(Icons.card_giftcard, size: 18)),
            Tab(text: '备份', icon: Icon(Icons.restore, size: 18)),
          ],
        ),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : TabBarView(
              controller: _tabs,
              children: [
                _profileTab(),
                _grantTab(),
                _backupTab(),
              ],
            ),
    );
  }

  Widget _profileTab() {
    final p = _player;
    if (p == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('账号信息', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _kv('手机号', p.phone),
                _kv('用户 ID', '${p.userId}'),
                _kv('最后登录', formatTimestamp(p.lastLoginTime)),
                _kv('拥有卡牌', '${p.unitCount}'),
                _kv('拥有饰品', '${p.accessoryCount}'),
                _kv('队伍数', '${p.deckCount}'),
                _kv('设备绑定',
                    p.bound ? '已绑定 ${p.boundDevice}' : '未绑定'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('属性修改', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '改完客户端需重新登录才会刷新。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desc,
                  decoration: const InputDecoration(
                    labelText: '简介',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final f in <(String, TextEditingController)>[
                      ('等级', _level),
                      ('经验', _exp),
                      ('升级所需经验', _nextExp),
                      ('金币', _gameCoin),
                      ('爱心', _snsCoin),
                      ('LP 上限', _energyMax),
                      ('超出 LP', _overMax),
                    ])
                      SizedBox(
                        width: 168,
                        child: NumberField(controller: f.$2, label: f.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveProfile,
                      icon: const Icon(Icons.save),
                      label: const Text('保存'),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: _saving ? null : () => _fill(p),
                      icon: const Icon(Icons.undo),
                      label: const Text('还原为当前值'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _grantTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发放卡牌', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('填 unit_id，用逗号或空格分隔；也可一键补齐全卡池。',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _grantUnitIds,
                  decoration: const InputDecoration(
                    labelText: '例如 31, 40, 49',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _grantUnits(),
                      icon: const Icon(Icons.add),
                      label: const Text('发放'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _grantUnits(all: true),
                      icon: const Icon(Icons.library_add),
                      label: const Text('补齐全卡池'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发放饰品', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('填 accessory_id，用逗号或空格分隔；同一饰品可多份。',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _grantAccessoryIds,
                  decoration: const InputDecoration(
                    labelText: '例如 1, 2, 3',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _grantAccessories(),
                      icon: const Icon(Icons.add),
                      label: const Text('发放'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _saving ? null : () => _grantAccessories(all: true),
                      icon: const Icon(Icons.library_add),
                      label: const Text('补齐全饰品池'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildItemCard(),
        const SizedBox(height: 12),
        _buildMailCard(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '说明：道具进的是 user_item_data，游戏内 /item/itemList 会带上；'
            '礼物箱走 user_present_box，点「领取」时服务端把道具/部员落库。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// 发道具：支持 `4*10, 5` 这种写法，省略数量按 1 发。
  List<({int itemId, int amount})> _parseItems() {
    final result = <({int itemId, int amount})>[];
    for (final part in _itemSpec.text.split(RegExp(r'[,，;；\s]+'))) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final m = RegExp(r'^(\d+)(?:\s*[*xX×]\s*(\d+))?$').firstMatch(t);
      if (m == null) continue;
      final id = int.parse(m.group(1)!);
      final amount = m.group(2) == null ? 1 : int.parse(m.group(2)!);
      if (id > 0 && amount > 0) result.add((itemId: id, amount: amount));
    }
    return result;
  }

  Widget _buildItemCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发放道具', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '格式：道具ID 或 道具ID*数量，逗号分隔，例如 4*10, 5, 6*3。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _itemSpec,
              decoration: const InputDecoration(
                labelText: '例如 4*10, 5',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(
                  value: _mailAsUnit,
                  onChanged: (v) => setState(() => _mailAsUnit = v),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _mailAsUnit
                        ? '投递到礼物箱时按「部员(卡)」处理（ID 填 unit_id）'
                        : '投递到礼物箱时按「道具」处理（ID 填 item_id）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : () => _grantItems(false),
                  icon: const Icon(Icons.backpack_outlined),
                  label: const Text('发到背包'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _grantItems(true),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('发到礼物箱'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMailCard() {
    final items = _mailItems;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('礼物箱', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                if (_mailPending > 0)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('$_mailPending 未领取'),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: '刷新礼物箱',
                  onPressed: _saving ? null : _loadMail,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '客户端进游戏后在「礼物箱」里能看到并领取。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text('还没有投递记录', style: Theme.of(context).textTheme.bodySmall)
            else
              for (final m in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    m.isUnit ? Icons.style : Icons.inventory_2_outlined,
                    size: 18,
                  ),
                  title: Text(
                    '${m.isUnit ? '部员' : '道具'} #${m.itemId} × ${m.amount}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${m.subject} · ${m.insertDate}'
                    '${m.opened ? ' · 已领取' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: '撤回',
                    onPressed:
                        _saving ? null : () => _deleteMail(m.presentBoxId),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _backupTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('存档备份', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '备份包含该账号的全部业务表行；滚动保留最近 7 份。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _backup,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('立即备份'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _restore(),
                      icon: const Icon(Icons.restore),
                      label: const Text('恢复最新一份'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_backups.isEmpty)
          const EmptyView(message: '还没有备份', icon: Icons.history)
        else
          for (final b in _backups)
            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(formatTimestamp(b.time)),
                subtitle: Text('${b.file} · ${formatBytes(b.size)}'),
                trailing: TextButton(
                  onPressed: _saving ? null : () => _restore(b.file),
                  child: const Text('恢复'),
                ),
              ),
            ),
      ],
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(key, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
