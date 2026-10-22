import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player_detail_page.dart';

class PlayersPage extends StatefulWidget {
  const PlayersPage({super.key, required this.api});

  final LocalApi api;

  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage> {
  List<AccountItem>? _accounts;
  String? _error;
  bool _loading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.accounts();
      if (!mounted) return;
      setState(() => _accounts = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final req = await showDialog<_CreateAccountInput>(
      context: context,
      builder: (_) => const _CreateAccountDialog(),
    );
    if (req == null) return;

    setState(() => _busy = true);
    try {
      final r = await widget.api.createAccount(
        phone: req.phone,
        password: req.password,
        name: req.name,
      );
      if (!mounted) return;
      showSnack(
        context,
        '已创建 #${r.userId}：等级 ${r.level}、'
        '${r.unitCount} 张卡、${r.accessoryCount} 件饰品',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AccountItem a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除账号「${a.name.isEmpty ? a.phone : a.name}」？'),
        content: Text(
          '会把这个账号的全部数据删掉：等级、卡、饰品、卡组、道具、礼物箱、'
          '好友关系、登录令牌，并解绑设备。\n\n'
          '手机号 ${a.phone}（ID ${a.userId}）\n'
          '这一步不可撤销，建议先到详情页做一次备份。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await widget.api.deleteAccount(a.userId);
      if (!mounted) return;
      showSnack(context, '已删除 ${a.phone}');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _accounts == null ? '读取中…' : '共 ${_accounts!.length} 个账号',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('新建账号'),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;

    if (_loading && _accounts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _accounts == null) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    final list = _accounts ?? const <AccountItem>[];
    if (list.isEmpty) {
      return Column(
        children: [
          _header(context),
          const Expanded(
            child: EmptyView(
              message: '还没有账号。点右上角「新建账号」，或直接在客户端登录一次也会自动建号。',
              icon: Icons.people_outline,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _header(context),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = list[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2),
                      child: Text('${a.level}'),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.name.isEmpty ? '（未命名）' : a.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (a.bound)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(Icons.smartphone,
                                size: 15,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '手机号 ${a.phone} · ID ${a.userId}\n'
                      '最后登录 ${formatTimestamp(a.lastLoginTime)}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '删除账号',
                          onPressed: _busy ? null : () => _delete(a),
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: colors.destructive),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PlayerDetailPage(api: widget.api, userId: a.userId),
                        ),
                      );
                      _load();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateAccountInput {
  const _CreateAccountInput({
    required this.phone,
    required this.password,
    required this.name,
  });

  final String phone;
  final String password;
  final String name;
}

class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog();

  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = _phone.text.trim();
    final password = _password.text;
    if (phone.isEmpty) {
      setState(() => _error = '手机号不能为空');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '密码不能为空');
      return;
    }
    Navigator.pop(
      context,
      _CreateAccountInput(
        phone: phone,
        password: password,
        name: _name.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建账号'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '账号按服务端当前的「新号模式」创建：原版从零则等级 1、只有 1 张初始卡；'
              '满配则直接拉满。卡和道具可以用「发放」补。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '手机号（客户端登录用这个）',
                hintText: '例如 13800001111',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '昵称（可留空）',
                hintText: '默认「音乃木坂学生」',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
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
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
