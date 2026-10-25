import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../widgets.dart';
import 'card_art_dialog.dart';
import 'custom_cards_page.dart';

/// 卡池 = 查卡器：左侧列表 + 右侧详情（参考 PJSK / 邦多利社区查卡器）。
///
/// 筛选：属性（Smile/Pure/Cool）、稀有度、队伍（μ's/Aqours/虹咲/Liella!）。
/// 详情面板展示立绘（服务端从资源包实时解出 PNG）与数值，可直接发放 / 换卡面。
class CardsPage extends StatefulWidget {
  const CardsPage({super.key, required this.api, required this.state});

  final LocalApi api;
  final AppState state;

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  final _query = TextEditingController();
  int _rarity = 0;
  int _attribute = 0;
  int _team = 0;
  int _page = 1;
  static const _size = 30;

  int _total = 0;
  List<UnitItem> _units = const [];
  String? _error;
  bool _loading = false;

  UnitItem? _selected;

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
        attribute: _attribute,
        team: _team,
      );
      if (!mounted) return;
      setState(() {
        _total = r.total;
        _units = r.units;
        if (_selected != null && !_units.any((u) => u.unitId == _selected!.unitId)) {
          _selected = null;
        }
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

  void _openCardArt({int unitId = 0}) {
    showDialog<void>(
      context: context,
      builder: (_) => CardArtDialog(api: widget.api, initialUnitId: unitId),
    );
  }

  int get _maxPage => _total <= 0 ? 1 : ((_total + _size - 1) ~/ _size);

  @override
  Widget build(BuildContext context) {
    final communityOn = widget.state.communityOn;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final list = _listColumn(communityOn);
      final detail = _DetailPanel(
        api: widget.api,
        unit: _selected,
        onArtTap: () => _openCardArt(unitId: _selected?.unitId ?? 0),
        onGranted: _load,
      );
      if (!wide) {
        return Column(
          children: [
            _filters(communityOn),
            Expanded(child: list),
            _pager(),
          ],
        );
      }
      return Column(
        children: [
          _filters(communityOn),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: list),
                const VerticalDivider(width: 1),
                SizedBox(width: 340, child: detail),
              ],
            ),
          ),
          _pager(),
        ],
      );
    });
  }

  Widget _filters(bool communityOn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              const SizedBox(width: 4),
              // 社区内容开关：控制造卡入口 / 社区谱面板的显示。
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () =>
                    widget.state.setCommunityOn(!widget.state.communityOn),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: widget.state.communityOn,
                        onChanged: widget.state.setCommunityOn,
                      ),
                      const Text('社区'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final a in const [0, 1, 2, 3])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(a == 0 ? '全部属性' : attrName(a)),
                      selected: _attribute == a,
                      onSelected: (_) {
                        setState(() => _attribute = a);
                        _search();
                      },
                    ),
                  ),
                for (final t in const [0, 1, 2, 3, 4])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t == 0 ? '全部队伍' : teamName(t)),
                      selected: _team == t,
                      onSelected: (_) {
                        setState(() => _team = t);
                        _search();
                      },
                    ),
                  ),
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
    );
  }

  Widget _listColumn(bool communityOn) {
    Widget list;
    if (_loading && _units.isEmpty) {
      list = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      list = ErrorView(message: _error!, onRetry: _load);
    } else if (_units.isEmpty) {
      list = const EmptyView(message: '没有匹配的卡牌');
    } else {
      list = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _units.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _unitTile(context, _units[i]),
        ),
      );
    }
    if (!communityOn) return list;
    // 社区内容开：造卡入口横幅。
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('自定义卡片'),
              subtitle: const Text('做自己的卡面、选技能，导入游戏里玩'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CustomCardsPage(api: widget.api, state: widget.state),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Widget _unitTile(BuildContext context, UnitItem u) {
    final selected = _selected?.unitId == u.unitId;
    return Card(
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ListTile(
        leading: _UnitAvatar(api: widget.api, unit: u),
        title: Text(u.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'ID ${u.unitId} · ${attrName(u.attribute)} · '
          'S${u.smileMax} P${u.pureMax} C${u.coolMax}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _openCardArt(unitId: u.unitId),
              icon: const Icon(Icons.image_outlined, size: 18),
              tooltip: '给这张卡换卡面',
              visualDensity: VisualDensity.compact,
            ),
            u.owned
                ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                : const Icon(Icons.remove_circle_outline),
          ],
        ),
        selected: selected,
        onTap: () {
          setState(() => _selected = u);
          // 窄屏没有右侧详情，弹出底部详情。
          if (MediaQuery.sizeOf(context).width < 900) {
            showModalBottomSheet<void>(
              context: context,
              builder: (_) => _DetailSheet(api: widget.api, unit: u),
            );
          }
        },
      ),
    );
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

  static String attrName(int id) => switch (id) {
        1 => 'Smile',
        2 => 'Pure',
        3 => 'Cool',
        _ => '其他',
      };

  static Color attrColor(int id) => switch (id) {
        1 => Colors.redAccent,
        2 => Colors.greenAccent,
        3 => Colors.lightBlueAccent,
        _ => Colors.grey,
      };

  static String teamName(int id) => switch (id) {
        1 => "μ's",
        2 => 'Aqours',
        3 => '虹咲',
        4 => 'Liella!',
        _ => '其他',
      };
}

/// 详情面板（宽屏右侧）。
class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.api,
    required this.unit,
    required this.onArtTap,
    required this.onGranted,
  });

  final LocalApi api;
  final UnitItem? unit;
  final VoidCallback onArtTap;
  final VoidCallback onGranted;

  @override
  Widget build(BuildContext context) {
    if (unit == null) {
      return const Center(
          child: Text('点左边的卡查看详情', textAlign: TextAlign.center));
    }
    return _DetailBody(
      api: api,
      unit: unit!,
      onArtTap: onArtTap,
      onGranted: onGranted,
      scrollable: true,
    );
  }
}

/// 详情（窄屏底部弹层）。
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.api, required this.unit});

  final LocalApi api;
  final UnitItem unit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 460,
        child: _DetailBody(
          api: api,
          unit: unit,
          onArtTap: () => Navigator.pop(context),
          onGranted: () {},
          scrollable: false,
        ),
      ),
    );
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({
    required this.api,
    required this.unit,
    required this.onArtTap,
    required this.onGranted,
    required this.scrollable,
  });

  final LocalApi api;
  final UnitItem unit;
  final VoidCallback onArtTap;
  final VoidCallback onGranted;
  final bool scrollable;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  bool _rankMax = false;
  bool _granting = false;

  String get _artUrl {
    final u = widget.unit;
    final icon = _rankMax ? u.rankMaxIcon ?? '' : u.normalIcon ?? '';
    // 图标列只进列表模型；这里尽量用立绘，缺了再退回图标。
    final navi = LocalApi.naviAssetOf(_rankMax
        ? (u.rankMaxIcon ?? u.normalIcon)
        : u.normalIcon);
    if (navi != null && navi.isNotEmpty) return widget.api.unitArtUrl(navi);
    return widget.api.unitIconUrl(u.unitId);
  }

  Future<void> _grant() async {
    final u = widget.unit;
    final accounts = await widget.api.accounts();
    if (!mounted) return;
    if (accounts.isEmpty) {
      showSnack(context, '还没有账号', error: true);
      return;
    }
    final selected = await showDialog<int>(
      context: context,
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
    setState(() => _granting = true);
    try {
      final n = await widget.api.grantUnits(selected, ids: [u.unitId]);
      if (!mounted) return;
      showSnack(context, n > 0 ? '已发放' : '该账号已拥有这张卡');
      widget.onGranted();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.unit;
    final theme = Theme.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: _CardsPageState.attrColor(u.attribute).withValues(alpha: 0.08),
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Image.network(
                  _artUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.image_not_supported_outlined,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  u.name,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _rankMax = !_rankMax),
                icon: Icon(_rankMax ? Icons.auto_awesome : Icons.star_border,
                    size: 16),
                label: Text(_rankMax ? '觉醒立绘' : '普通立绘'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip('ID ${u.unitId}'),
              _chip('R${u.rarity}'),
              _chip(_CardsPageState.attrName(u.attribute),
                  color: _CardsPageState.attrColor(u.attribute)),
              _chip('HP ${u.hpMax}'),
              _chip('技能 #${u.skillId}'),
              if (u.owned) _chip('已拥有', color: Colors.greenAccent),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'S ${u.smileMax} · P ${u.pureMax} · C ${u.coolMax}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _granting ? null : _grant,
                icon: const Icon(Icons.card_giftcard, size: 18),
                label: const Text('发放'),
              ),
              OutlinedButton.icon(
                onPressed: widget.onArtTap,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('换卡面 / 造卡'),
              ),
            ],
          ),
        ),
      ],
    );
    return widget.scrollable ? body : SingleChildScrollView(child: body);
  }

  Widget _chip(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (color ?? Theme.of(context).colorScheme.outline)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}

/// 卡片头像：服务端实时从资源包解出的 PNG（RGBA4444，带透明通道）。
/// 加载中 / 失败（404，如资源缺失）时回退成属性色 + 稀有度角标。
class _UnitAvatar extends StatelessWidget {
  const _UnitAvatar({required this.api, required this.unit});

  final LocalApi api;
  final UnitItem unit;

  @override
  Widget build(BuildContext context) {
    final fallback = _RarityBadge(
      rarity: unit.rarity,
      background:
          _CardsPageState.attrColor(unit.attribute).withValues(alpha: 0.25),
    );
    return SizedBox(
      width: 44,
      height: 44,
      child: ClipOval(
        child: ColoredBox(
          color: _CardsPageState.attrColor(unit.attribute)
              .withValues(alpha: 0.12),
          child: Image.network(
            api.unitIconUrl(unit.unitId),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                (frame != null || wasSynchronouslyLoaded) ? child : fallback,
          ),
        ),
      ),
    );
  }
}

class _RarityBadge extends StatelessWidget {
  const _RarityBadge({required this.rarity, required this.background});

  final int rarity;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      alignment: Alignment.center,
      child: Text(
        'R$rarity',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
