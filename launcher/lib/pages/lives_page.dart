import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 56,
        height: 56,
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
