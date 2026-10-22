import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'server_control.dart';

/// 服务端返回的业务错误（HTTP 200 但 ok=false，或预期外的响应）。
class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `/local/*` 接口客户端。baseUrl 形如 `http://192.168.0.107:8080`。
class LocalApi {
  LocalApi({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 15),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> _decode(http.Response res) async {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('HTTP ${res.statusCode}: ${res.reasonPhrase ?? ''}');
    }
    final text = utf8.decode(res.bodyBytes);
    if (text.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException('响应格式异常');
  }

  Map<String, dynamic> _ok(Map<String, dynamic> j, String action) {
    if (j['ok'] == true || j['ok'] == null) return j;
    throw ApiException((j['message'] ?? '$action 失败').toString());
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final res = await _client.get(_uri(path, query)).timeout(timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await _client
        .post(
          _uri(path),
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: utf8.encode(jsonEncode(body)),
        )
        .timeout(timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final res = await _client.delete(_uri(path)).timeout(timeout);
    return _decode(res);
  }

  /// 连通性探测，返回 ping 原始字段。
  Future<Map<String, dynamic>> ping() async {
    final j = await _get('/local/ping');
    if (j['ok'] != true) throw ApiException('服务端未就绪');
    return j;
  }

  Future<Overview> overview() async {
    final j = _ok(await _get('/local/admin/overview'), '读取总览');
    return Overview.fromJson(j);
  }

  Future<List<AccountItem>> accounts() async {
    final j = _ok(await _get('/local/accounts'), '读取账号');
    final list = (j['accounts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AccountItem.fromJson)
        .toList();
    return list;
  }

  Future<Player> player(int userId) async {
    final j = _ok(await _get('/local/admin/players/$userId'), '读取玩家');
    return Player.fromJson(j['player'] as Map<String, dynamic>);
  }

  /// 只提交非 null 字段，避免误改其他属性。
  Future<Player> patchPlayer(int userId, Map<String, Object?> patch) async {
    final body = <String, Object?>{};
    patch.forEach((k, v) {
      if (v != null) body[k] = v;
    });
    if (body.isEmpty) throw ApiException('没有要修改的字段');
    final j = _ok(await _post('/local/admin/players/$userId/profile', body), '修改玩家');
    return Player.fromJson(j['player'] as Map<String, dynamic>);
  }

  Future<int> grantUnits(int userId, {List<int> ids = const [], bool all = false}) async {
    final j = _ok(
      await _post('/local/admin/players/$userId/grant-units',
          {'unit_ids': ids, 'all': all}),
      '发放卡牌',
    );
    return (j['granted'] as num?)?.toInt() ?? 0;
  }

  Future<int> grantAccessories(int userId,
      {List<int> ids = const [], bool all = false}) async {
    final j = _ok(
      await _post('/local/admin/players/$userId/grant-accessories',
          {'accessory_ids': ids, 'all': all}),
      '发放饰品',
    );
    return (j['granted'] as num?)?.toInt() ?? 0;
  }

  Future<({int total, List<UnitItem> units})> units({
    int page = 1,
    int size = 30,
    String query = '',
    int rarity = 0,
    int userId = 0,
  }) async {
    final j = _ok(
      await _get('/local/admin/master/units', {
        'page': '$page',
        'size': '$size',
        if (query.isNotEmpty) 'q': query,
        if (rarity > 0) 'rarity': '$rarity',
        if (userId > 0) 'user_id': '$userId',
      }),
      '读取卡表',
    );
    final list = (j['units'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UnitItem.fromJson)
        .toList();
    return (total: (j['total'] as num?)?.toInt() ?? 0, units: list);
  }

  Future<({int total, List<AccessoryItem> items})> accessories(
      {int page = 1, int size = 30, String query = ''}) async {
    final j = _ok(
      await _get('/local/admin/master/accessories', {
        'page': '$page',
        'size': '$size',
        if (query.isNotEmpty) 'q': query,
      }),
      '读取饰品表',
    );
    final list = (j['accessories'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AccessoryItem.fromJson)
        .toList();
    return (total: (j['total'] as num?)?.toInt() ?? 0, items: list);
  }

  Future<({int total, List<LiveItem> lives})> lives(
      {int page = 1, int size = 50}) async {
    final j = _ok(
      await _get('/local/admin/master/lives', {'page': '$page', 'size': '$size'}),
      '读取乐曲表',
    );
    final list = (j['lives'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LiveItem.fromJson)
        .toList();
    return (total: (j['total'] as num?)?.toInt() ?? 0, lives: list);
  }

  /// 按曲子聚合的乐曲列表（一首曲一张卡，难度挂在里面）。`q` 支持曲名 / 曲目 ID / 谱面名。
  Future<({int total, int named, List<LiveTrackItem> tracks})> liveTracks({
    int page = 1,
    int size = 20,
    String q = '',
  }) async {
    final j = _ok(
      await _get('/local/admin/lives/tracks', {
        'page': '$page',
        'size': '$size',
        if (q.trim().isNotEmpty) 'q': q.trim(),
      }),
      '读取乐曲表',
    );
    final tracks = (j['tracks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LiveTrackItem.fromJson)
        .toList();
    return (
      total: (j['total'] as num?)?.toInt() ?? 0,
      named: (j['named'] as num?)?.toInt() ?? 0,
      tracks: tracks,
    );
  }

  /// 曲名映射（导出用）。
  Future<Map<String, String>> liveNames() async {
    final j = _ok(await _get('/local/admin/live-names'), '读取曲名');
    final raw = j['names'] as Map<String, dynamic>? ?? const {};
    return raw.map((k, v) => MapEntry(k, v.toString()));
  }

  /// 导入曲名映射（`{"1":"曲名"}`），合并不删除。
  Future<int> setLiveNames(Map<String, String> names) async {
    final j = _ok(
      await _post('/local/admin/live-names', {'names': names}),
      '导入曲名',
    );
    return (j['total'] as num?)?.toInt() ?? 0;
  }

  /// 上传某首曲子的封面 PNG。
  Future<void> uploadLiveCover(int trackId, String pngBase64) async {
    _ok(
      await _post('/local/admin/live-cover/$trackId', {
        'name': 't$trackId',
        'png_base64': pngBase64,
      }),
      '上传封面',
    );
  }

  /// 封面的完整 URL（没有封面时返回空）。
  String coverUrl(String relative) {
    if (relative.isEmpty) return '';
    return relative.startsWith('http') ? relative : '$baseUrl$relative';
  }

  Future<Map<String, dynamic>> unlock(
      {bool lives = false, bool scenarios = false}) async {
    return _ok(
      await _post('/local/admin/unlock', {'lives': lives, 'scenarios': scenarios}),
      '解锁内容',
    );
  }

  Future<void> switchAccount(String phone, String password,
      {String deviceId = ''}) async {
    _ok(
      await _post('/local/switch', {
        'phone': phone,
        'password': password,
        if (deviceId.isNotEmpty) 'device_id': deviceId,
      }),
      '切换账号',
    );
  }

  Future<void> unbind({String deviceId = ''}) async {
    _ok(
      await _get('/local/unbind',
          deviceId.isEmpty ? null : {'device_id': deviceId}),
      '解绑设备',
    );
  }

  Future<List<BackupItem>> backups(int userId) async {
    final j = _ok(
        await _get('/local/accounts/$userId/backups'), '读取备份列表');
    return (j['backups'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BackupItem.fromJson)
        .toList();
  }

  /// 服务端自身状态。
  Future<ServerInfo> serverInfo() async {
    final j = _ok(await _get('/local/admin/server'), '读取服务端信息');
    return ServerInfo.fromJson(j);
  }

  /// 增量拉取服务端输出。`after` 传上次的 next 序号。
  Future<({List<LogLine> lines, int next})> logs({
    int after = 0,
    int limit = 400,
  }) async {
    final j = _ok(
      await _get('/local/admin/logs', {'after': '$after', 'limit': '$limit'}),
      '读取服务端日志',
    );
    final lines = (j['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LogLine.fromJson)
        .toList();
    return (lines: lines, next: (j['next'] as num?)?.toInt() ?? after);
  }

  /// 修改服务端配置（端口 / CDN）。端口改动需要重启才生效。
  Future<({bool restartRequired, String message, String port, String cdn})>
      patchConfig({String? listenPort, String? cdnServer}) async {
    final body = <String, Object?>{};
    if (listenPort != null) body['listen_port'] = listenPort;
    if (cdnServer != null) body['cdn_server'] = cdnServer;
    if (body.isEmpty) throw ApiException('没有要修改的配置');

    final j = await _post('/local/admin/config', body);
    // 这个接口在失败时也带当前值，便于界面回填。
    final ok = j['ok'] == true;
    final result = (
      restartRequired: j['restart_required'] == true,
      message: (j['message'] ?? (ok ? '已保存' : '保存失败')).toString(),
      port: (j['listen_port'] ?? '').toString(),
      cdn: (j['cdn_server'] ?? '').toString(),
    );
    if (!ok) throw ApiException(result.message);
    return result;
  }

  /// 请求服务端优雅退出。
  Future<void> shutdownServer() async {
    _ok(await _post('/local/admin/shutdown', const {}), '关闭服务端');
  }

  /// 上线 / 下线乐曲。谱面文件会被搬进/搬出 `beatmaps` 目录，服务端据此判定可否游玩。
  Future<({int changed, List<String> failed})> toggleLives(
    List<int> ids,
    bool enabled,
  ) async {
    final j = await _post('/local/admin/lives/toggle', {
      'live_difficulty_ids': ids,
      'enabled': enabled,
    });
    final failed = (j['failed'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    if (j['ok'] != true) {
      throw ApiException((j['message'] ?? '操作失败').toString());
    }
    return (changed: (j['changed'] as num?)?.toInt() ?? 0, failed: failed);
  }

  /// 导出谱面原文。
  Future<({String asset, int size, int notes, bool enabled, String content})>
      beatmap(int liveDifficultyId) async {
    final j = _ok(
      await _get('/local/admin/lives/beatmap', {'id': '$liveDifficultyId'}),
      '读取谱面',
    );
    return (
      asset: (j['notes_setting_asset'] ?? '').toString(),
      size: (j['size'] as num?)?.toInt() ?? 0,
      notes: (j['notes'] as num?)?.toInt() ?? 0,
      enabled: j['enabled'] == true,
      content: (j['content'] ?? '').toString(),
    );
  }

  /// 上传谱面（会先自动备份旧文件）。
  Future<({int notes, int size})> saveBeatmap(
      int liveDifficultyId, String content) async {
    final j = _ok(
      await _post('/local/admin/lives/$liveDifficultyId/beatmap',
          {'content': content}),
      '保存谱面',
    );
    return (
      notes: (j['notes'] as num?)?.toInt() ?? 0,
      size: (j['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// 读取「新号从零开始」设置。
  Future<({bool vanilla, int initialUnitId, int sampleUserId, int sampleLevel, int sampleUnitCount})>
      newUserSetting() async {
    final j = _ok(await _get('/local/admin/new-user'), '读取新号设置');
    return (
      vanilla: j['vanilla'] == true,
      initialUnitId: (j['initial_unit_id'] as num?)?.toInt() ?? 31,
      sampleUserId: (j['sample_user_id'] as num?)?.toInt() ?? 0,
      sampleLevel: (j['sample_level'] as num?)?.toInt() ?? 0,
      sampleUnitCount: (j['sample_unit_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 修改「新号从零开始」设置（只影响之后新建的账号）。
  Future<String> setNewUserSetting({bool? vanilla, int? initialUnitId}) async {
    final body = <String, Object?>{};
    if (vanilla != null) body['vanilla'] = vanilla;
    if (initialUnitId != null) body['initial_unit_id'] = initialUnitId;
    if (body.isEmpty) throw ApiException('没有要修改的项');
    final j = await _post('/local/admin/new-user', body);
    if (j['ok'] != true) {
      throw ApiException((j['message'] ?? '保存失败').toString());
    }
    return (j['message'] ?? '已保存').toString();
  }

  /// 新建账号。新号的等级/卡数取决于服务端的「新号模式」开关。
  Future<({int userId, int level, int unitCount, int accessoryCount})>
      createAccount({
    required String phone,
    required String password,
    String name = '',
  }) async {
    final j = _ok(
      await _post('/local/admin/accounts', {
        'phone': phone,
        'password': password,
        if (name.isNotEmpty) 'name': name,
      }),
      '新建账号',
    );
    return (
      userId: (j['user_id'] as num?)?.toInt() ?? 0,
      level: (j['level'] as num?)?.toInt() ?? 0,
      unitCount: (j['unit_count'] as num?)?.toInt() ?? 0,
      accessoryCount: (j['accessory_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 删除账号（服务端会清掉所有带 user_id 的表并解绑设备）。
  Future<void> deleteAccount(int userId) async {
    _ok(await _delete('/local/admin/accounts/$userId'), '删除账号');
  }

  /// 卡面库列表。
  Future<({String dir, List<CardArtItem> items})> cardArts() async {
    final j = _ok(await _get('/local/admin/cardart'), '读取卡面库');
    final items = (j['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CardArtItem.fromJson)
        .toList();
    return (dir: (j['dir'] ?? '').toString(), items: items);
  }

  /// 删除一张自定义卡面。
  Future<void> deleteCardArt(String name) async {
    _ok(await _delete('/local/admin/cardart/${Uri.encodeComponent(name)}'),
        '删除卡面');
  }

  /// 往礼物箱投递奖励。
  Future<int> sendMail(
    int userId, {
    required List<({int addType, int itemId, int amount})> items,
    String subject = '',
  }) async {
    final j = _ok(
      await _post('/local/admin/players/$userId/mail', {
        'subject': subject,
        'items': [
          for (final it in items)
            {'add_type': it.addType, 'item_id': it.itemId, 'amount': it.amount}
        ],
      }),
      '投递邮件',
    );
    return (j['sent'] as num?)?.toInt() ?? 0;
  }

  /// 礼物箱列表。
  Future<({int pending, List<MailBoxItem> items})> mailBox(int userId) async {
    final j = _ok(await _get('/local/admin/players/$userId/mail'), '读取礼物箱');
    final items = (j['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MailBoxItem.fromJson)
        .toList();
    return (pending: (j['pending'] as num?)?.toInt() ?? 0, items: items);
  }

  /// 撤回一条邮件。
  Future<void> deleteMail(int userId, int presentBoxId) async {
    _ok(
      await _delete('/local/admin/players/$userId/mail/$presentBoxId'),
      '撤回邮件',
    );
  }

  /// 直接发道具到背包。
  Future<int> grantItems(
    int userId,
    List<({int itemId, int amount})> items,
  ) async {
    final j = _ok(
      await _post('/local/admin/players/$userId/grant-items', {
        'items': [
          for (final it in items) {'item_id': it.itemId, 'amount': it.amount}
        ],
      }),
      '发放道具',
    );
    return (j['granted'] as num?)?.toInt() ?? 0;
  }

  Future<void> createBackup(int userId) async {
    _ok(await _get('/local/accounts/$userId/backup'), '创建备份');
  }

  Future<void> restoreBackup(int userId, {String file = ''}) async {
    _ok(
      await _post('/local/accounts/$userId/restore',
          {if (file.isNotEmpty) 'file': file}),
      '恢复备份',
    );
  }
}
