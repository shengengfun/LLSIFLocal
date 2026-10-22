import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({super.key, required this.api});

  final LocalApi api;

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  final _query = TextEditingController();
  int _rarity = 0;
  int _page = 1;
  static const _size = 30;

  int _total = 0;
  List<UnitItem> _units = const [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.units(
        page: _page,
        size: _size,
        query: _query.text.trim(),
        rarity: _rarity,
      );
      if (!mounted) return;
      setState(() {
        _total = r.total;
        _units = r.units;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _search() {
    _page = 1;
    _load();
  }

  int get _maxPage => _total <= 0 ? 1 : ((_total + _size - 1) ~/ _size);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      decoration: const InputDecoration(
                        hintText: '搜索卡名 / unit_id / 卡号',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _search,
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in const [0, 1, 2, 3, 4, 5])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(r == 0 ? '全部稀有度' : 'R$r'),
                          selected: _rarity == r,
                          onSelected: (_) {
                            setState(() => _rarity = r);
                            _search();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _units.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : _units.isEmpty
                      ? const EmptyView(message: '没有匹配的卡牌')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _units.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) =>
                                _unitTile(context, _units[i]),
                          ),
                        ),
        ),
        _pager(),
      ],
    );
  }

  Widget _unitTile(BuildContext context, UnitItem u) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _attrColor(u.attribute).withValues(alpha: 0.25),
          child: Text(
            'R${u.rarity}',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        title: Text(u.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'ID ${u.unitId} · ${_attrName(u.attribute)} · '
          'S${u.smileMax} P${u.pureMax} C${u.coolMax}',
        ),
        trailing: u.owned
            ? const Icon(Icons.check_circle, color: Colors.greenAccent)
            : const Icon(Icons.remove_circle_outline),
        onTap: () => _showGrantDialog(u),
      ),
    );
  }

  Future<void> _showGrantDialog(UnitItem u) async {
    final accounts = await widget.api.accounts();
    if (!mounted) return;
    if (accounts.isEmpty) {
      showSnack(context, '还没有账号', error: true);
      return;
    }

    final dialogContext = context;
    if (!dialogContext.mounted) return;
    final selected = await showDialog<int>(
      context: dialogContext,
      builder: (ctx) => SimpleDialog(
        title: Text('把 ${u.name}（ID ${u.unitId}）发给谁'),
        children: [
          for (final a in accounts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a.userId),
              child: Row(
                children: [
                  Text('${a.name}（${a.phone}）'),
                  const Spacer(),
                  Text('Lv.${a.level}',
                      style: Theme.of(ctx).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    try {
      final n = await widget.api.grantUnits(selected, ids: [u.unitId]);
      if (!mounted) return;
      showSnack(context, n > 0 ? '已发放' : '该账号已拥有这张卡');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    }
  }

  Widget _pager() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Text('共 $_total 张 · 第 $_page / $_maxPage 页',
              style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          IconButton(
            onPressed: _page > 1 && !_loading
                ? () {
                    _page--;
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: _page < _maxPage && !_loading
                ? () {
                    _page++;
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  static String _attrName(int id) => switch (id) {
        1 => 'Smile',
        2 => 'Pure',
        3 => 'Cool',
        _ => '其他',
      };

  static Color _attrColor(int id) => switch (id) {
        1 => Colors.redAccent,
        2 => Colors.greenAccent,
        3 => Colors.lightBlueAccent,
        _ => Colors.grey,
      };
}
