import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets.dart';
import 'card_art_dialog.dart';

/// 自定义卡片（造卡页）。
///
/// 实现思路（服务端与客户端资源链路决定的唯一可行解）：
/// 自定义卡 = **选一张现役卡当「基底」**（技能 / 数值 / 卡号都继承它），
/// 再把它的纹理层换成自己的图 —— 服务端把 PNG 重新封装成 texb 并写回资源包
/// （或推送到客户端），游戏里这张卡的技能照常触发，等于「自制卡面 + 自选技能」。
/// 想要哪种技能，就挑带那种技能的基底卡；技能效果定义在客户端本机主数据库里，
/// 服务端发放的只是 unit_id，所以换技能 = 换基底。
class CustomCardsPage extends StatefulWidget {
  const CustomCardsPage({super.key, required this.api, required this.state});

  final LocalApi api;
  final AppState state;

  @override
  State<CustomCardsPage> createState() => _CustomCardsPageState();
}

class _CustomCardsPageState extends State<CustomCardsPage> {
  final _query = TextEditingController();
  int _rarity = 0;
  int _team = 0;

  List<UnitItem> _units = const [];
  UnitItem? _base;
  List<CardArtItem> _archive = const [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadArchive();
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
        page: 1,
        size: 40,
        query: _query.text.trim(),
        rarity: _rarity,
        team: _team,
      );
      if (!mounted) return;
      setState(() => _units = r.units);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadArchive() async {
    try {
      final r = await widget.api.cardArts();
      if (!mounted) return;
      setState(() => _archive = r.items);
    } catch (_) {
      // 卡面库读失败不阻塞基底卡选择。
    }
  }

  void _openMaker({int unitId = 0}) {
    showDialog<void>(
      context: context,
      builder: (_) => CardArtDialog(api: widget.api, initialUnitId: unitId),
    ).then((_) => _loadArchive());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('自定义卡片')),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 760;
        final picker = _basePicker();
        final maker = _makerPane(theme);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: picker),
              const VerticalDivider(width: 1),
              Expanded(flex: 5, child: maker),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SizedBox(height: 420, child: picker),
            const SizedBox(height: 12),
            maker,
          ],
        );
      }),
    );
  }

  // ------------------------------------------------------------ 左：挑基底卡

  Widget _basePicker() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1 · 挑一张「基底卡」', style: Theme.of(context).textTheme.titleMedium),
              Text(
                '自定义卡继承基底卡的技能与数值 —— 想要什么技能就挑哪张卡',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      decoration: const InputDecoration(
                        hintText: '搜索卡名 / ID',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _team,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('全部队伍')),
                      DropdownMenuItem(value: 1, child: Text("μ's")),
                      DropdownMenuItem(value: 2, child: Text('Aqours')),
                      DropdownMenuItem(value: 3, child: Text('虹咲')),
                      DropdownMenuItem(value: 4, child: Text('Liella!')),
                    ],
                    onChanged: (v) {
                      setState(() => _team = v ?? 0);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _rarity,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('全部R')),
                      DropdownMenuItem(value: 2, child: Text('R2')),
                      DropdownMenuItem(value: 3, child: Text('R3')),
                      DropdownMenuItem(value: 4, child: Text('R4')),
                      DropdownMenuItem(value: 5, child: Text('R5')),
                    ],
                    onChanged: (v) {
                      setState(() => _rarity = v ?? 0);
                      _load();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _units.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _units.length,
                      itemBuilder: (context, i) {
                        final u = _units[i];
                        final sel = _base?.unitId == u.unitId;
                        return Card(
                          color: sel
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                          child: ListTile(
                            leading: SizedBox(
                              width: 44,
                              height: 44,
                              child: ClipOval(
                                child: Image.network(
                                  widget.api.unitIconUrl(u.unitId),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.person_outline),
                                ),
                              ),
                            ),
                            title: Text(u.name, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              'ID ${u.unitId} · R${u.rarity} · 技能 #${u.skillId}',
                            ),
                            selected: sel,
                            onTap: () => setState(() => _base = u),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 右：做卡

  Widget _makerPane(ThemeData theme) {
    final base = _base;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('2 · 换上自己的卡面', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (base == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('先在左边选一张基底卡',
                  style: theme.textTheme.bodySmall),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: ClipOval(
                          child: Image.network(
                            widget.api.unitIconUrl(base.unitId),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.person_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(base.name, style: theme.textTheme.titleSmall),
                            Text(
                              '基底 ID ${base.unitId} · R${base.rarity} · '
                              '技能 #${base.skillId} · '
                              'S${base.smileMax} P${base.pureMax} C${base.coolMax}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _openMaker(unitId: base.unitId),
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: const Text('收料并落地（icon/navi/卡面）'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _granting ? null : _grantBase,
                        icon: const Icon(Icons.card_giftcard, size: 18),
                        label: const Text('把这张卡发给账号'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('3 · 卡面归档库（${_archive.length}）', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '流程：查层 → 收料（PNG 路径）→ 落地。三种落地模式：只出命令 / '
          '改写服务端资源包 / adb 推送客户端。技能说明在客户端本机主数据库里，'
          '游戏内按 unit_id 触发，所以自制卡的技能与基底卡完全一致。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_archive.isEmpty)
          Text('还没有归档的 PNG', style: theme.textTheme.bodySmall)
        else
          ..._archive.map((a) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined),
                title: Text('${a.name}  ${a.width}×${a.height}'),
                subtitle: a.unitId > 0 ? Text('已关联 unit ${a.unitId}') : null,
                trailing: a.unitId > 0
                    ? TextButton(
                        onPressed: () => _openMaker(unitId: a.unitId),
                        child: const Text('继续做'),
                      )
                    : TextButton(
                        onPressed: () => _openMaker(),
                        child: const Text('关联卡'),
                      ),
              )),
      ],
    );
  }

  bool _granting = false;

  Future<void> _grantBase() async {
    final base = _base;
    if (base == null) return;
    try {
      final accounts = await widget.api.accounts();
      if (!mounted) return;
      if (accounts.isEmpty) {
        showSnack(context, '还没有账号', error: true);
        return;
      }
      final selected = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('把自定义卡（基底 ${base.name}）发给谁'),
          children: [
            for (final a in accounts)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, a.userId),
                child: Text('${a.name}（${a.phone}）'),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      setState(() => _granting = true);
      final n = await widget.api.grantUnits(selected, ids: [base.unitId]);
      if (!mounted) return;
      showSnack(context, n > 0 ? '已发放，进游戏即可看到自制卡面' : '该账号已拥有这张卡');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }
}
