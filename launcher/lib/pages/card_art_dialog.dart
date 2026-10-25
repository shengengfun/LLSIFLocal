import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';

/// 自定义卡面：一张卡在资源包里有 10 层纹理，换哪一层都行。
///
/// 流程刻意做成「收料 → 查纹理 → 落地」三步，且落地有三种模式：
///   * 只出命令 —— 不做任何副作用，复制的命令可以在任何机器上跑；
///   * 改写服务端资源包 —— 重新下载该包的玩家看到新图（有备份，可回滚）；
///   * 推送客户端 —— adb 直推 files/install，重启游戏立刻生效（要设备连着）。
///
/// 为什么不让 App 自己拼 texb：容器要重建 RGB565 + zlib，还要 honoka v4 加密，
/// Go/Dart 各写一遍都是重复劳动且容易出错，统一交给 tools/cardface.py。
class CardArtDialog extends StatefulWidget {
  const CardArtDialog({super.key, required this.api, this.initialUnitId = 0});

  final LocalApi api;
  final int initialUnitId;

  @override
  State<CardArtDialog> createState() => _CardArtDialogState();
}

class _CardArtDialogState extends State<CardArtDialog> {
  late final TextEditingController _unit =
      TextEditingController(text: widget.initialUnitId > 0 ? '${widget.initialUnitId}' : '');
  final _pngPath = TextEditingController();

  List<CardTexbLayer> _layers = const [];
  List<CardArtItem> _archive = const [];
  String? _layerMessage;
  String _selectedName = '';
  String _mode = 'command';
  bool _busy = false;
  String _output = '';

  @override
  void initState() {
    super.initState();
    _loadArchive();
    if (widget.initialUnitId > 0) _queryLayers();
  }

  @override
  void dispose() {
    _unit.dispose();
    _pngPath.dispose();
    super.dispose();
  }

  int get _unitId => int.tryParse(_unit.text.trim()) ?? 0;

  Future<void> _loadArchive() async {
    try {
      final r = await widget.api.cardArts();
      if (!mounted) return;
      setState(() {
        _archive = r.items;
        if (_selectedName.isEmpty && r.items.isNotEmpty) {
          _selectedName = r.items.first.name;
        }
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _queryLayers() async {
    final id = _unitId;
    if (id <= 0) {
      showSnack(context, '先填 unit_id（部员一览里那张卡的 ID）', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _output = '';
    });
    try {
      final r = await widget.api.cardTexbLayers(id);
      if (!mounted) return;
      setState(() {
        _layers = r.layers;
        _layerMessage = r.layers.isEmpty ? (r.message.isEmpty ? '这张卡没有可替换的纹理' : r.message) : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _layerMessage = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromPath() async {
    final path = _pngPath.text.trim();
    if (path.isEmpty) {
      showSnack(context, '填 PNG 的完整路径（服务端所在机器上能读到的）', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final item = await widget.api.importCardArtFromPath(
        path: path,
        name: 'unit_${_unitId > 0 ? _unitId : DateTime.now().millisecondsSinceEpoch}',
        unitId: _unitId,
      );
      if (!mounted) return;
      await _loadArchive();
      if (!mounted) return;
      setState(() => _selectedName = item.name);
      showSnack(context, '已收料：${item.width}×${item.height}');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_selectedName.isEmpty) {
      showSnack(context, '先选一张已归档的 PNG', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _output = '';
    });
    try {
      final r = await widget.api.applyCardArt(
        name: _selectedName,
        unitId: _unitId,
        mode: _mode,
      );
      if (!mounted) return;
      final parts = <String>[
        if (r.message.isNotEmpty) r.message,
        if (r.command.isNotEmpty) '${r.ran ? "已执行" : "命令"}：${r.command}',
        if (r.output.trim().isNotEmpty) r.output.trim(),
      ];
      setState(() => _output = parts.join('\n'));
      showSnack(context, r.ok ? r.message : r.message, error: !r.ok);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSnack(context, '已复制');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.image_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('自定义卡面', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle('1 · 查这张卡有哪些层'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _unit,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'unit_id',
                              helperText: '部员一览里显示的卡 ID，例如 41107008',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _queryLayers(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _queryLayers,
                          icon: const Icon(Icons.search),
                          label: const Text('查询'),
                        ),
                      ],
                    ),
                    if (_layerMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_layerMessage!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    if (_layers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          children: [
                            for (final l in _layers)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Text(l.kind,
                                    style: theme.textTheme.labelSmall),
                                title: Text(l.fileName,
                                    style: theme.textTheme.bodySmall),
                                subtitle: Text('资源包 ${l.archive}'
                                    '${l.signed ? ' · 签名卡' : ''}'),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    _sectionTitle('2 · 收料（PNG 放在服务端机器上）'),
                    TextField(
                      controller: _pngPath,
                      decoration: const InputDecoration(
                        labelText: 'PNG 路径',
                        helperText: r'例如 D:\pics\my_card.png；尺寸会被自动缩放到纹理尺寸',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _importFromPath,
                        icon: const Icon(Icons.drive_folder_upload),
                        label: const Text('收料并归档'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('3 · 落地'),
                    if (_archive.isEmpty)
                      Text('还没有归档的 PNG', style: theme.textTheme.bodySmall)
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _archive.any((e) => e.name == _selectedName)
                            ? _selectedName
                            : null,
                        decoration: const InputDecoration(
                          labelText: '已归档的 PNG',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final a in _archive)
                            DropdownMenuItem(
                              value: a.name,
                              child: Text(
                                '${a.name}  ${a.width}×${a.height}'
                                '${a.unitId > 0 ? '  → unit ${a.unitId}' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _selectedName = v ?? ''),
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('只出命令'),
                          selected: _mode == 'command',
                          onSelected: (_) => setState(() => _mode = 'command'),
                        ),
                        ChoiceChip(
                          label: const Text('改写服务端资源包'),
                          selected: _mode == 'server',
                          onSelected: (_) => setState(() => _mode = 'server'),
                        ),
                        ChoiceChip(
                          label: const Text('推送客户端'),
                          selected: _mode == 'push',
                          onSelected: (_) => setState(() => _mode = 'push'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _apply,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(_mode == 'command' ? '生成命令' : '执行'),
                        ),
                        const SizedBox(width: 8),
                        if (_output.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => _copy(_output),
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('复制结果'),
                          ),
                      ],
                    ),
                    if (_output.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _output,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '说明：\n'
                      '· 只出命令 —— 不改任何文件，命令里已经带好 unit_id / PNG 路径 / 层。\n'
                      '· 改写服务端资源包 —— 会先备份到 assets/cardface_backups；'
                      '客户端需要重新下载该资源包（或直接用推送）。\n'
                      '· 推送客户端 —— 需要设备已连 adb；推到 files/install/assets/image/units，'
                      '重启游戏立刻生效。\n'
                      '· 回滚：在服务端执行 python tools\\cardface.py restore --unit <unit_id>。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}
