import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// 乐曲页：一首曲一张卡（曲名 + 封面 + 难度标签），支持搜索、单曲/单难度上下线、谱面导入导出。
///
/// 「上线」的本质是谱面文件是否在 `assets/serverdata/beatmaps` 里 ——
/// 服务端只认这一条，所以开关做成了真的搬文件。
class LivesPage extends StatefulWidget {
  const LivesPage({super.key, required this.api});

  final LocalApi api;

  @override
  State<LivesPage> createState() => _LivesPageState();
}

enum _LiveFilter { all, partial, offline, unnamed }

class _LivesPageState extends State<LivesPage> {
  int _page = 1;
  static const _size = 20;

  int _total = 0;
  int _named = 0;
  List<LiveTrackItem> _tracks = const [];
  String? _error;
  bool _loading = false;
  bool _busy = false;
  _LiveFilter _filter = _LiveFilter.all;

  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.liveTracks(
        page: _page,
        size: _size,
        q: _search.text,
      );
      if (!mounted) return;
      setState(() {
        _total = r.total;
        _named = r.named;
        _tracks = r.tracks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchChanged() {
    _page = 1;
    _load();
  }

  List<LiveTrackItem> get _visible => switch (_filter) {
        _LiveFilter.all => _tracks,
        _LiveFilter.partial => _tracks.where((t) => t.partiallyOffline).toList(),
        _LiveFilter.offline => _tracks.where((t) => t.fullyOffline).toList(),
        _LiveFilter.unnamed => _tracks.where((t) => !t.hasName).toList(),
      };

  Future<void> _toggleDifficulties(List<int> ids, bool enabled) async {
    if (ids.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.toggleLives(ids, enabled);
      if (!mounted) return;
      if (r.failed.isNotEmpty) {
        showSnack(context, r.failed.join('; '), error: true);
      } else {
        showSnack(context, '已${enabled ? '上线' : '下线'} ${r.changed} 个难度');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleWholeTrack(LiveTrackItem t, bool enabled) async {
    await _toggleDifficulties(
      t.difficulties.map((d) => d.liveDifficultyId).toList(),
      enabled,
    );
  }

  Future<void> _unlockAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解锁全部乐曲？'),
        content: const Text(
          '会把主数据里所有普通曲的「默认解锁」位打开，对全部账号生效。\n'
          '这是修改器操作，不会自动回滚。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('解锁')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final j = await widget.api.unlock(lives: true);
      if (!mounted) return;
      showSnack(context, '已解锁 ${j['lives_unlocked'] ?? 0} 条乐曲');
      _page = 1;
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportBeatmap(LiveTrackItem t, LiveDifficultyItem d) async {
    setState(() => _busy = true);
    try {
      final b = await widget.api.beatmap(d.liveDifficultyId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => _BeatmapExportDialog(track: t, diff: d, data: b),
      );
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBeatmap(LiveTrackItem t, LiveDifficultyItem d) async {
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => _BeatmapImportDialog(track: t, diff: d),
    );
    if (content == null) return;

    setState(() => _busy = true);
    try {
      final r = await widget.api.saveBeatmap(d.liveDifficultyId, content);
      if (!mounted) return;
      showSnack(context, '已写入谱面：${r.notes} 个音符，${r.size} 字节');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 曲名导入：粘 `{"1":"曲名"}` 就能批量补名字。
  Future<void> _importNames() async {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => const _NamesImportDialog(),
    );
    if (text == null) return;

    final Map<String, String> names = {};
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      // 支持 "12=曲名"、"12,曲名"、"12<TAB>曲名" 三种写法
      final m = RegExp(r'^(\d+)\s*[=,\t|]\s*(.+)$').firstMatch(t);
      if (m != null) names[m.group(1)!] = m.group(2)!.trim();
    }
    if (names.isEmpty) {
      if (!mounted) return;
      showSnack(context, '没解析出「曲目ID=曲名」的行', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final n = await widget.api.setLiveNames(names);
      if (!mounted) return;
      showSnack(context, '已写入 $n 条曲名');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _maxPage => _total <= 0 ? 1 : ((_total + _size - 1) ~/ _size);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '乐曲管理'),
              Tab(text: '社区谱面'),
            ],
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            isScrollable: true,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _manageTab(),
                _CommunityPanel(api: widget.api),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 原「乐曲管理」内容（搜索 / 过滤 / 列表 / 分页）。
  Widget _manageTab() {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: '搜索曲名 / 曲目 ID / 谱面文件名',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _search.clear();
                                  _searchChanged();
                                },
                              ),
                      ),
                      onSubmitted: (_) => _searchChanged(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '搜索',
                    onPressed: _searchChanged,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '共 $_total 首（$_named 首有曲名）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _unlockAll,
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: const Text('解锁全部'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importNames,
                    icon: const Icon(Icons.translate, size: 16),
                    label: const Text('导入曲名'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final f in _LiveFilter.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        _LiveFilter.all => '全部',
                        _LiveFilter.partial => '部分下线',
                        _LiveFilter.offline => '已下线',
                        _LiveFilter.unnamed => '缺曲名',
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _tracks.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : _visible.isEmpty
                      ? const EmptyView(
                          message: '没有匹配的曲目', icon: Icons.music_off)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) =>
                                _trackCard(context, _visible[i], colors),
                          ),
                        ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Text('第 $_page / $_maxPage 页',
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
        ),
      ],
    );
  }

  Widget _trackCard(BuildContext context, LiveTrackItem t, AppColors colors) {
    final allOn = t.enabledCount == t.difficultyCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(
                  api: widget.api,
                  track: t,
                  colors: colors,
                  enabled: t.enabledCount > 0,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              t.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (t.hasName && t.nameEn.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                t.nameEn,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${t.liveTrackId} · ${t.difficultyCount} 个难度 · '
                        '上线 ${t.enabledCount}/${t.difficultyCount}',
                        style: TextStyle(
                            fontSize: 11, color: colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: allOn ? '整首下线' : '整首上线',
                  child: Switch(
                    value: t.enabledCount > 0,
                    onChanged: _busy ? null : (v) => _toggleWholeTrack(t, v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in t.difficulties)
                  _DiffChip(
                    diff: d,
                    colors: colors,
                    busy: _busy,
                    onToggle: (v) =>
                        _toggleDifficulties([d.liveDifficultyId], v),
                    onExport: () => _exportBeatmap(t, d),
                    onImport: () => _importBeatmap(t, d),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面：有图就显示图，没有就画一个柔和占位（不假装有图）。
class _Cover extends StatelessWidget {
  const _Cover({
    required this.api,
    required this.track,
    required this.colors,
    required this.enabled,
  });

  final LocalApi api;
  final LiveTrackItem track;
  final AppColors colors;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final url = api.coverUrl(track.coverUrl);
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 64,
        height: 64,
        color: colors.muted,
        child: url.isEmpty
            ? Center(
                child: Icon(
                  Icons.album_outlined,
                  size: 22,
                  color: enabled ? colors.mutedForeground : colors.destructive,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.album_outlined,
                      size: 22, color: colors.mutedForeground),
                ),
              ),
      ),
    );
    // 整首下线的曲子封面压暗，和难度 chip 的视觉语言保持一致。
    if (!enabled) {
      return Opacity(opacity: 0.45, child: cover);
    }
    return cover;
  }
}

/// 一个难度：点一下切换上/下线，长按菜单里有谱面导入导出。
class _DiffChip extends StatelessWidget {
  const _DiffChip({
    required this.diff,
    required this.colors,
    required this.busy,
    required this.onToggle,
    required this.onExport,
    required this.onImport,
  });

  final LiveDifficultyItem diff;
  final AppColors colors;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onExport;
  final VoidCallback onImport;

  static String _label(int d) => switch (d) {
        1 => 'E',
        2 => 'N',
        3 => 'H',
        4 => 'EX',
        5 => 'MW',
        _ => 'R$d',
      };

  static Color _color(int d) => switch (d) {
        1 => const Color(0xFF3DBE7C),
        2 => const Color(0xFF4A9FE0),
        3 => const Color(0xFFE0A34A),
        4 => const Color(0xFFE06A8B),
        5 => const Color(0xFF8E6AE0),
        _ => const Color(0xFF8A94A0),
      };

  @override
  Widget build(BuildContext context) {
    final c = _color(diff.difficulty);
    return PopupMenuButton<String>(
      enabled: !busy,
      tooltip: '${_label(diff.difficulty)} Lv.${diff.stageLevel}',
      onSelected: (v) {
        if (v == 'toggle') onToggle(!diff.enabled);
        if (v == 'export') onExport();
        if (v == 'import') onImport();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'toggle',
          child: Text(diff.enabled ? '下线这个难度' : '上线这个难度'),
        ),
        const PopupMenuItem(value: 'export', child: Text('导出谱面')),
        const PopupMenuItem(value: 'import', child: Text('导入谱面（会备份）')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: diff.enabled ? 0.16 : 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: c.withValues(alpha: diff.enabled ? 0.55 : 0.22),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label(diff.difficulty),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: diff.enabled ? c : colors.mutedForeground,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${diff.stageLevel}',
              style: TextStyle(
                fontSize: 11.5,
                color: diff.enabled ? colors.foreground : colors.mutedForeground,
              ),
            ),
            if (diff.special) ...[
              const SizedBox(width: 4),
              Icon(Icons.star, size: 10, color: colors.primary),
            ],
            if (!diff.enabled) ...[
              const SizedBox(width: 4),
              Icon(Icons.visibility_off, size: 11, color: colors.mutedForeground),
            ],
          ],
        ),
      ),
    );
  }
}

class _NamesImportDialog extends StatefulWidget {
  const _NamesImportDialog();

  @override
  State<_NamesImportDialog> createState() => _NamesImportDialogState();
}

class _NamesImportDialogState extends State<_NamesImportDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入曲名'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '每行一条，格式「曲目ID=曲名」，例如：\n'
              '3=Snow halation\n'
              '1=僕らのLIVE 君とのLIFE\n\n'
              '曲名不在服务端主数据里（官方主数据只有资源路径），'
              '所以要么手动补，要么跑 tools/import_live_names.py 从完整主数据导入。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                    fontFamily: AppFonts.mono, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '3=Snow halation',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final text = _ctrl.text.trim();
            if (text.isEmpty) {
              setState(() => _error = '内容为空');
              return;
            }
            Navigator.pop(context, text);
          },
          child: const Text('导入'),
        ),
      ],
    );
  }
}

class _BeatmapExportDialog extends StatelessWidget {
  const _BeatmapExportDialog({
    required this.track,
    required this.diff,
    required this.data,
  });

  final LiveTrackItem track;
  final LiveDifficultyItem diff;
  final ({String asset, int size, int notes, bool enabled, String content}) data;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('导出谱面 · ${track.displayName}'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '难度 ${diff.difficulty} · ${data.asset} · '
              '${data.notes} 个音符 · ${data.size} 字节'
              '${data.enabled ? '' : ' · 当前已下线'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF10161D),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  child: SelectableText(
                    data.content,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: Color(0xFFC8D3DC),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: data.content));
            if (context.mounted) {
              showSnack(context, '谱面已复制到剪贴板');
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.copy_all_outlined, size: 18),
          label: const Text('复制全文'),
        ),
      ],
    );
  }
}

class _BeatmapImportDialog extends StatefulWidget {
  const _BeatmapImportDialog({required this.track, required this.diff});

  final LiveTrackItem track;
  final LiveDifficultyItem diff;

  @override
  State<_BeatmapImportDialog> createState() => _BeatmapImportDialogState();
}

class _BeatmapImportDialogState extends State<_BeatmapImportDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('导入谱面 · ${widget.track.displayName}'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '覆盖 ${widget.diff.notesAsset}。服务端会先自动备份旧文件，'
              '导入成功后这个难度会立刻上线。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                    fontFamily: AppFonts.mono, fontSize: 11.5),
                decoration: const InputDecoration(
                  hintText: '在这里粘贴谱面 JSON（一个数组）',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final text = _ctrl.text.trim();
            if (text.isEmpty) {
              setState(() => _error = '内容为空');
              return;
            }
            Navigator.pop(context, text);
          },
          child: const Text('写入'),
        ),
      ],
    );
  }
}

// ============================================================ 社区谱面

/// 社区谱面面板，分两块：
///
/// 1. **已发布曲目** —— 真正下发到客户端的那批（曲目/难度/下载登记 5 张表 +
///    谱面 + 资源包 + download_m 都已就位）。列表逐行给出体检结果，坏在哪
///    一眼能看出，并可单曲撤下。
/// 2. **谱面库** —— 只落在服务端 `community_beatmaps/` 的谱，还要再附加到某个
///    官方难度才会生效（老流程，保留）。
class _CommunityPanel extends StatefulWidget {
  const _CommunityPanel({required this.api});
  final LocalApi api;

  @override
  State<_CommunityPanel> createState() => _CommunityPanelState();
}

class _CommunityPanelState extends State<_CommunityPanel> {
  bool _enabled = true;
  bool _busy = false;
  bool _libExpanded = false;
  String? _error;
  ({int count, List<CommunityPackage> tracks}) _pkgs =
      (count: 0, tracks: const <CommunityPackage>[]);
  ({int officialBackups, List<CommunityChart> charts}) _lib =
      (officialBackups: 0, charts: const <CommunityChart>[]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final flag = await widget.api.communityToggle();
      final pkgs = await widget.api.communityPackages();
      final lib = await widget.api.communityCharts();
      if (!mounted) return;
      setState(() {
        _enabled = flag;
        _pkgs = pkgs;
        _lib = lib;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(bool v) async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.setCommunityToggle(v);
      if (!mounted) return;
      setState(() => _enabled = r);
      if (!v) {
        final n = await widget.api.rollbackAllCommunity();
        if (!mounted) return;
        showSnack(context, '已关闭社区内容，并回滚 $n 个被替换的官方谱');
      } else {
        showSnack(context, '社区内容已开启');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 发布 = 解析谱面 + 生成资源包 + 登记下载，客户端下次更新就能下到。
  Future<void> _publish() async {
    final res = await showDialog<PublishOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PublishDialog(api: widget.api),
    );
    if (res == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _PublishResultDialog(outcome: res),
    );
    await _load();
  }

  Future<void> _withdraw(CommunityPackage p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _NameConfirmDialog(
        title: '撤下「${p.name}」？',
        message: '会删除该曲在服务端的曲目 / 难度 / 下载登记行，以及谱面文件与两个下发包。\n'
            '已经下载到客户端的副本不会自动消失，要等客户端下次更新。此操作不可撤销。',
        expect: p.name,
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.withdrawCommunityTrack(p.trackId);
      if (!mounted) return;
      showSnack(context, '已撤下「${p.name}」');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ChartUploadDialog(),
    );
    if (res == null) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.uploadCommunityChart('', res);
      if (!mounted) return;
      showSnack(context, '已入库：${r.name}（${r.notes} 音符）');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(CommunityChart c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AttachDialog(api: widget.api, chart: c),
    );
    if (ok == true && mounted) {
      showSnack(context, '已附加到难度');
      await _load();
    }
  }

  Future<void> _detach(CommunityChart c, int diff) async {
    setState(() => _busy = true);
    try {
      await widget.api.attachCommunityChart(c.name, diff, detach: true);
      if (!mounted) return;
      showSnack(context, '已回滚难度 $diff 的社区谱');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openChartmaker() async {
    final url = '${widget.api.baseUrl}/admin/chartmaker';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else if (mounted) {
      showSnack(context, '打开失败：$url', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final colors = theme.brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    final problems =
        _pkgs.tracks.where((t) => !t.healthy).toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerCard(theme, muted),
          const SizedBox(height: 12),
          if (_error != null) ...[
            ErrorView(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 12),
          ],
          _healthBanner(colors, problems),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('已发布曲目（${_pkgs.tracks.length}）',
                    style: theme.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_pkgs.tracks.isEmpty)
            const EmptyView(
              message: '还没有发布过社区曲。点上方「发布社区曲」上传谱面与音频即可',
              icon: Icons.queue_music_outlined,
            )
          else
            for (final p in _pkgs.tracks)
              _packageCard(p, colors, muted),
          const SizedBox(height: 16),
          _libraryCard(theme, muted, colors),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _headerCard(ThemeData theme, TextStyle? muted) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('社区内容总开关',
                      style: theme.textTheme.titleMedium),
                ),
                Switch(
                  value: _enabled,
                  onChanged: _busy ? null : _setEnabled,
                ),
              ],
            ),
            Text(
              _enabled
                  ? '自定义卡 / 社区谱均已启用。关闭会回滚全部被替换的官方谱。'
                  : '已关闭：社区谱已回滚为官方谱，自定义卡仍按已发放记录保留。',
              style: muted,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _publish,
                  icon: const Icon(Icons.publish, size: 18),
                  label: const Text('发布社区曲'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openChartmaker,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('打开做谱器（网页）'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 体检横幅：把「能不能下、能不能开打」一次说清。
  Widget _healthBanner(AppColors colors, List<CommunityPackage> problems) {
    final ok = problems.isEmpty;
    final color = ok ? colors.success : colors.destructive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.verified_outlined : Icons.report_problem_outlined,
              size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok
                      ? '体检通过：${_pkgs.tracks.length} 首社区曲谱面、资源包、下载登记齐全'
                      : '${problems.length} 首有问题，客户端可能下不动或开打失败',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
                if (!ok) ...[
                  const SizedBox(height: 4),
                  for (final p in problems.take(6))
                    Text(
                      '${p.name}（#${p.trackId}）：${p.problemLabels.join('、')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (problems.length > 6)
                    Text('…另有 ${problems.length - 6} 首',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _packageCard(
      CommunityPackage p, AppColors colors, TextStyle? muted) {
    final cover = widget.api.liveCoverUrl(p.trackId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverThumb(url: cover, colors: colors),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '#${p.trackId} · ${p.memberLabel} · ${p.difficultyLabel}'
                        ' · 难度号 ${p.difficultyId}',
                        style: muted,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${p.notes} 音符 · ${p.seconds.toStringAsFixed(1)}s'
                        ' · ${formatBytes(p.pkgSize)} · ${p.notesAsset}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (p.healthy)
                      _Badge(label: '可下载', color: colors.success)
                    else
                      for (final t in p.problemLabels)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _Badge(label: t, color: colors.destructive),
                        ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _withdraw(p),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('撤下'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryCard(ThemeData theme, TextStyle? muted, AppColors colors) {
    final charts = _lib.charts;
    // 展开状态自己管：ExpansionTile 会把展开标志写进 PageStorage，
    // 而同一路径上还有 ListView 的滚动偏移（double），刷新后列表长度一变
    // 就会撞上「double 不能 cast 成 bool?」把整页渲染成空白。
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _libExpanded = !_libExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.library_music_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('谱面库（附加到官方难度）· ${charts.length} 张',
                            style: theme.textTheme.titleSmall),
                        Text(
                          '只入库、不改曲目表；附加后会用社区谱替换该官方难度的谱面',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  Icon(_libExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20),
                ],
              ),
            ),
          ),
          if (_libExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _upload,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('导入社区谱（粘贴 JSON）'),
                      ),
                      if (_lib.officialBackups > 0)
                        Chip(
                          avatar: const Icon(Icons.restore, size: 16),
                          label: Text('${_lib.officialBackups} 个官方谱已备份'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (charts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('谱面库为空', style: muted),
                    )
                  else
                    for (final c in charts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CoverThumb(
                                url: widget.api.coverUrl(c.coverUrl),
                                colors: colors,
                                size: 44),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    '${c.notes} 音符 · ${c.seconds.toStringAsFixed(1)}s',
                                    style: muted,
                                  ),
                                  if (c.attached.isEmpty)
                                    Text('尚未附加到任何难度', style: muted)
                                  else
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final d in c.attached)
                                          InputChip(
                                            label: Text('难度 $d'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            deleteIcon:
                                                const Icon(Icons.undo, size: 14),
                                            onDeleted: _busy
                                                ? null
                                                : () => _detach(c, d),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : () => _attach(c),
                              icon: const Icon(Icons.link, size: 16),
                              label: const Text('附加'),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 社区曲 / 谱面缩略图：取不到图时退回占位图标（不假装有图）。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({
    required this.url,
    required this.colors,
    this.size = 56,
  });

  final String url;
  final AppColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: size,
        height: size,
        color: colors.muted,
        child: url.isEmpty
            ? Center(
                child: Icon(Icons.library_music_outlined,
                    size: size * 0.4, color: colors.mutedForeground),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.library_music_outlined,
                      size: size * 0.4, color: colors.mutedForeground),
                ),
              ),
      ),
    );
  }
}

/// 状态徽章（语义色，不写死 RGB）。
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// 危险操作确认：必须把名字原样敲一遍才放手（撤下不可逆）。
class _NameConfirmDialog extends StatefulWidget {
  const _NameConfirmDialog({
    required this.title,
    required this.message,
    this.expect = '',
  });

  final String title;
  final String message;
  final String expect;

  @override
  State<_NameConfirmDialog> createState() => _NameConfirmDialogState();
}

class _NameConfirmDialogState extends State<_NameConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _ok =>
      widget.expect.isEmpty || _ctrl.text.trim() == widget.expect.trim();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            if (widget.expect.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('请输入曲名确认：${widget.expect}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '曲名',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
        FilledButton(
          onPressed: _ok ? () => Navigator.pop(context, true) : null,
          child: const Text('确认撤下'),
        ),
      ],
    );
  }
}

/// 上传谱面：粘 JSON（一个音符数组）。
class _ChartUploadDialog extends StatefulWidget {
  const _ChartUploadDialog();
  @override
  State<_ChartUploadDialog> createState() => _ChartUploadDialogState();
}

class _ChartUploadDialogState extends State<_ChartUploadDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入社区谱'),
      content: SizedBox(
        width: 620,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '粘贴谱面 JSON（一个数组，每个元素含 timing_sec / position / '
              'effect / effect_value / notes_attribute）。也可以从做谱器导出后粘过来。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11.5),
                decoration: const InputDecoration(
                  hintText: '[{"timing_sec":1.0,"position":5,"effect":1,...}]',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final t = _ctrl.text.trim();
            if (t.isEmpty) {
              setState(() => _error = '内容为空');
              return;
            }
            Navigator.pop(context, t);
          },
          child: const Text('写入'),
        ),
      ],
    );
  }
}

/// 发布结果：把服务端分配的 id 与生成的资源/下发包摊开，便于核对。
class _PublishResultDialog extends StatelessWidget {
  const _PublishResultDialog({required this.outcome});

  final PublishOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    final o = outcome;
    return AlertDialog(
      title: const Text('发布成功'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('曲目号 ${o.trackId} · 曲目设置 ${o.settingId} · '
                  '难度号 ${o.difficultyId} · 曲号 ${o.musicId}'),
              if (o.chart != null)
                Text('谱面：${o.chart!.notes} 音符 · ${o.chart!.duration} · '
                    '密度 ${o.chart!.density.toStringAsFixed(2)}/s',
                    style: muted),
              const SizedBox(height: 10),
              Text('生成的资源（${o.resources.length}）',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final r in o.resources) Text(r, style: muted),
              const SizedBox(height: 10),
              Text('下发包（${o.download.length}）',
                  style: Theme.of(context).textTheme.titleSmall),
              if (o.lacksPackages)
                Text('没有生成下发包：客户端能选到这首，但下载不到音频/封面。'
                    '补上音频与封面后重新发布即可。',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12))
              else
                for (final d in o.download) Text(d, style: muted),
              const SizedBox(height: 10),
              Text(
                '下一步：客户端重启（或进一次下载流程）后，这首歌会出现在演唱会列表里。',
                style: muted,
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('好')),
      ],
    );
  }
}

/// 单个本地文件（选好后立刻读成字节，避免 Android 临时路径过期）。
class _PickedBytes {
  const _PickedBytes({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  int get size => bytes.length;
}

/// 发布社区曲：填曲目信息 → 选谱面/封面/标题/音频 → 解析预览 → 带进度上传。
class _PublishDialog extends StatefulWidget {
  const _PublishDialog({required this.api});
  final LocalApi api;

  @override
  State<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends State<_PublishDialog> {
  final _name = TextEditingController();
  final _nameEn = TextEditingController();
  final _capital = TextEditingController();

  String _chartText = '';
  String _chartName = '';
  _PickedBytes? _cover;
  _PickedBytes? _title;
  _PickedBytes? _audio;

  /// 0 = 按密度自动判档（服务端 suggestDifficulty）。
  int _difficulty = 0;
  int _memberCat = 4;

  ChartStat? _stat;
  int _suggested = 0;
  bool _parsing = false;
  bool _busy = false;
  double _progress = 0;
  String? _error;

  static const _difficultyLabels = ['自动', '普通', '困难', '专家', '大师'];
  static const _memberLabels = ['其他', "μ's", 'Aqours', '虹咲', 'Liella'];

  @override
  void dispose() {
    _name.dispose();
    _nameEn.dispose();
    _capital.dispose();
    super.dispose();
  }

  Future<void> _pickChart() async {
    final f = await _pick(['json'], '选择谱面 JSON');
    if (f == null) return;
    setState(() {
      _chartText = utf8.decode(f.bytes, allowMalformed: true);
      _chartName = f.name;
      _stat = null;
    });
    await _parse();
  }

  Future<void> _pasteChart() async {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ChartUploadDialog(),
    );
    if (text == null) return;
    setState(() {
      _chartText = text;
      _chartName = 'pasted.json';
      _stat = null;
    });
    await _parse();
  }

  Future<_PickedBytes?> _pick(List<String> exts, String label,
      {bool any = false}) async {
    try {
      final f = await FilePicker.pickFile(
        dialogTitle: label,
        type: any ? FileType.any : FileType.custom,
        allowedExtensions: any ? null : exts,
      );
      if (f == null) return null;
      return _PickedBytes(name: f.name, bytes: await f.readAsBytes());
    } catch (e) {
      if (mounted) setState(() => _error = '选择文件失败：$e');
      return null;
    }
  }

  Future<void> _parse() async {
    if (_chartText.trim().isEmpty) {
      setState(() => _error = '先选谱面文件或粘贴谱面 JSON');
      return;
    }
    setState(() {
      _parsing = true;
      _error = null;
    });
    try {
      final r = await widget.api.communityChartStat(_chartText);
      if (!mounted) return;
      setState(() {
        _stat = r.stat;
        _suggested = r.suggestedDifficulty;
        if (_capital.text.trim().isEmpty && _suggested > 0) {
          const capital = [5, 10, 15, 20, 25];
          _capital.text =
              '${capital[(_suggested - 1).clamp(0, capital.length - 1)]}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stat = null;
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '曲名不能为空');
      return;
    }
    if (_chartText.trim().isEmpty) {
      setState(() => _error = '缺少谱面：选一个 JSON 文件或粘贴谱面');
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    try {
      final res = await widget.api.publishCommunityTrack(
        name: name,
        nameEn: _nameEn.text.trim(),
        chartJson: _chartText,
        chartName: _chartName.isEmpty ? 'chart.json' : _chartName,
        difficulty: _difficulty,
        memberCategory: _memberCat,
        capitalValue: int.tryParse(_capital.text.trim()) ?? 0,
        cover: _cover?.bytes,
        coverName: _cover?.name ?? 'cover.png',
        title: _title?.bytes,
        titleName: _title?.name ?? 'title.png',
        audio: _audio?.bytes,
        audioName: _audio?.name ?? 'audio.ogg',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      Navigator.pop(context, res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final warn = TextStyle(color: theme.colorScheme.error, fontSize: 12);

    return AlertDialog(
      title: const Text('发布社区曲'),
      content: SizedBox(
        width: 720,
        height: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '曲名（必填）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameEn,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '英文曲名（可空，默认与曲名相同）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<int>(
                      initialValue: _difficulty,
                      decoration: const InputDecoration(
                        labelText: '难度',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var i = 0; i < _difficultyLabels.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(_suggested > 0 && i == 0
                                ? '自动（建议 ${_difficultyLabels[_suggested.clamp(1, 4)]}）'
                                : _difficultyLabels[i]),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _difficulty = v ?? 0),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<int>(
                      initialValue: _memberCat,
                      decoration: const InputDecoration(
                        labelText: '成员组',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var i = 0; i < _memberLabels.length; i++)
                          DropdownMenuItem(
                              value: i, child: Text(_memberLabels[i])),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _memberCat = v ?? 4),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _capital,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'LP 消耗',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('谱面', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickChart,
                    icon: const Icon(Icons.file_open, size: 18),
                    label: const Text('选择 JSON 文件'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pasteChart,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('粘贴 JSON'),
                  ),
                  if (_chartName.isNotEmpty)
                    Text('$_chartName · ${_chartText.length} 字符', style: muted),
                ],
              ),
              const SizedBox(height: 10),
              if (_parsing)
                const LinearProgressIndicator(minHeight: 2)
              else if (_stat != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(label: Text('${_stat!.notes} 音符')),
                    Chip(label: Text('时长 ${_stat!.duration}')),
                    Chip(
                        label: Text(
                            '密度 ${_stat!.density.toStringAsFixed(2)}/s')),
                    Chip(label: Text('最大和弦 ${_stat!.maxChord}')),
                    if (_stat!.longNotes > 0)
                      Chip(label: Text('长条 ${_stat!.longNotes}')),
                    if (_stat!.starNotes > 0)
                      Chip(label: Text('星 ${_stat!.starNotes}')),
                    if (_stat!.swing)
                      const Chip(label: Text('Swing')),
                    if (_suggested > 0)
                      Chip(
                        label: Text(
                            '建议难度 ${_difficultyLabels[_suggested.clamp(1, 4)]}'),
                      ),
                  ],
                )
              else
                Text('选好谱面后会自动解析音符数 / 时长 / 密度', style: muted),
              const SizedBox(height: 14),
              Text('素材', style: theme.textTheme.titleSmall),
              _fileRow(
                label: '封面 PNG/JPG',
                picked: _cover,
                onPick: () async {
                  final f = await _pick(['png', 'jpg', 'jpeg'], '选择封面');
                  if (f != null) setState(() => _cover = f);
                },
                onClear: () => setState(() => _cover = null),
              ),
              _fileRow(
                label: '标题图 PNG（可空，默认用封面生成）',
                picked: _title,
                onPick: () async {
                  final f = await _pick(['png'], '选择标题图');
                  if (f != null) setState(() => _title = f);
                },
                onClear: () => setState(() => _title = null),
              ),
              _fileRow(
                label: '音频 OGG（44100Hz）',
                picked: _audio,
                onPick: () async {
                  final f = await _pick(const [], '选择音频', any: true);
                  if (f != null) setState(() => _audio = f);
                },
                onClear: () => setState(() => _audio = null),
              ),
              const SizedBox(height: 6),
              if (_audio == null)
                Text('没选音频：客户端能开打但没有声音（音频必须 44100Hz，否则解码全静音）',
                    style: warn),
              if (_cover == null)
                Text('没选封面：客户端没有封面/曲名条，列表里会是一块空白',
                    style: warn),
              if (_busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                const SizedBox(height: 4),
                Text('上传中 ${(_progress * 100).toStringAsFixed(0)}%', style: muted),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: warn),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.cloud_upload, size: 18),
          label: const Text('发布并下发'),
        ),
      ],
    );
  }

  Widget _fileRow({
    required String label,
    required _PickedBytes? picked,
    required Future<void> Function() onPick,
    required VoidCallback onClear,
  }) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              picked == null ? label : '$label：${picked.name}（${formatBytes(picked.size)}）',
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (picked != null)
            IconButton(
              tooltip: '清除',
              onPressed: _busy ? null : onClear,
              icon: const Icon(Icons.close, size: 16),
            ),
          TextButton(
            onPressed: _busy ? null : onPick,
            child: const Text('选择'),
          ),
        ],
      ),
    );
  }
}


/// 把社区谱附加到某个难度：先搜曲，再点难度。
class _AttachDialog extends StatefulWidget {
  const _AttachDialog({required this.api, required this.chart});
  final LocalApi api;
  final CommunityChart chart;

  @override
  State<_AttachDialog> createState() => _AttachDialogState();
}

class _AttachDialogState extends State<_AttachDialog> {
  final _q = TextEditingController();
  List<LiveTrackItem> _tracks = const [];
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.liveTracks(page: 1, size: 60, q: _q.text);
      if (!mounted) return;
      setState(() {
        _tracks = r.tracks;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _attachTo(int diff) async {
    setState(() => _loading = true);
    try {
      await widget.api.attachCommunityChart(widget.chart.name, diff);
      if (!mounted) return;
      setState(() {
        _done = true;
        _loading = false;
      });
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('附加「${widget.chart.name}」到难度'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    decoration: const InputDecoration(
                      hintText: '搜索曲名 / 曲目 ID',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loading ? null : _search, child: const Text('搜索')),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: ErrorView(message: _error!, onRetry: _search))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (context, i) {
                    final t = _tracks[i];
                    return ListTile(
                      dense: true,
                      title: Text(t.displayName, overflow: TextOverflow.ellipsis),
                      subtitle: Text('#${t.liveTrackId} · ${t.difficultyCount} 难度'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          for (final d in t.difficulties)
                            ActionChip(
                              label: Text(_DiffChip._label(d.difficulty)),
                              onPressed: _loading ? null : () => _attachTo(d.liveDifficultyId),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, _done),
            child: const Text('关闭')),
      ],
    );
  }
}
