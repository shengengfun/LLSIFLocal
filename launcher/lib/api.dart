import 'dart:async';
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
    int attribute = 0,
    int team = 0,
    int userId = 0,
  }) async {
    final j = _ok(
      await _get('/local/admin/master/units', {
        'page': '$page',
        'size': '$size',
        if (query.isNotEmpty) 'q': query,
        if (rarity > 0) 'rarity': '$rarity',
        if (attribute > 0) 'attribute': '$attribute',
        if (team > 0) 'team': '$team',
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

  /// 通用纹理解码接口（立绘 / 大卡面），404 表示资源不存在。
  String unitArtUrl(String asset) =>
      '$baseUrl/local/admin/unit-art?asset=${Uri.encodeComponent(asset)}';

  /// 从图标资源路径推出立绘（navi）资源路径。
  /// 新卡：.../unit/<id>/u_<id>_normal_icon.png -> .../u_<id>_normal_navi.png
  /// 旧卡：.../units/u_normal_icon_<id>.png -> .../units/u_normal_navi_<id>.png
  static String? naviAssetOf(String? iconAsset) {
    if (iconAsset == null || iconAsset.isEmpty) return null;
    if (iconAsset.contains('_normal_icon')) {
      return iconAsset.replaceFirst('_normal_icon', '_normal_navi');
    }
    if (iconAsset.contains('_rankup_icon')) {
      return iconAsset.replaceFirst('_rankup_icon', '_rankup_navi');
    }
    return null;
  }

  /// 物品表（发放面板右侧的查询列表）。
  Future<({int total, List<ItemEntry> items})> masterItems({
    int page = 1,
    int size = 50,
    String query = '',
  }) async {
    final j = _ok(
      await _get('/local/admin/master/items', {
        'page': '$page',
        'size': '$size',
        if (query.isNotEmpty) 'q': query,
      }),
      '读取物品表',
    );
    final list = (j['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItemEntry.fromJson)
        .toList();
    return (total: (j['total'] as num?)?.toInt() ?? 0, items: list);
  }

  // ---------------------------------------------------------------- 社区谱面

  /// 社区谱库列表。
  Future<({int officialBackups, List<CommunityChart> charts})>
      communityCharts() async {
    final j = _ok(await _get('/local/admin/community/beatmaps'), '读取社区谱库');
    final charts = (j['charts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CommunityChart.fromJson)
        .toList();
    return (
      officialBackups: (j['official_backups'] as num?)?.toInt() ?? 0,
      charts: charts,
    );
  }

  /// 上传社区谱（content 为谱面 JSON 原文）。
  Future<({String name, int notes, double seconds})> uploadCommunityChart(
      String name, String content) async {
    final j = _ok(
      await _post('/local/admin/community/beatmaps',
          {'name': name, 'notes': jsonDecode(content)}),
      '导入社区谱',
    );
    return (
      name: (j['name'] ?? '').toString(),
      notes: (j['notes'] as num?)?.toInt() ?? 0,
      seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
    );
  }

  /// 附加社区谱到某个难度（detach=true 回滚官方谱）。
  Future<void> attachCommunityChart(String name, int liveDifficultyId,
      {bool detach = false}) async {
    _ok(
      await _post('/local/admin/community/beatmaps/attach',
          {'name': name, 'live_difficulty_id': liveDifficultyId, 'detach': detach}),
      detach ? '回滚社区谱' : '附加社区谱',
    );
  }

  /// 社区内容总开关（卡池 / 乐曲共用）。
  Future<bool> communityToggle() async {
    final j = _ok(await _get('/local/admin/community/toggle'), '读取社区开关');
    return j['enabled'] == true;
  }

  Future<bool> setCommunityToggle(bool enabled) async {
    final j = _ok(await _post('/local/admin/community/toggle', {'enabled': enabled}),
        '设置社区开关');
    return j['enabled'] == true;
  }

  /// 回滚全部社区谱到官方谱。
  Future<int> rollbackAllCommunity() async {
    final j = _ok(await _post('/local/admin/community/rollback-all', const {}),
        '回滚社区谱');
    return (j['rolled_back'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------- 社区曲目（发布 / 下发 / 回收）

  /// 已发布到服务端的社区曲 + 完整性体检。
  ///
  /// 每行的 missing / size_mismatch 是服务端按真实文件与 download_m 现算的，
  /// 界面直接据此显示「缺谱面 / 缺资源包 / 包大小不一致」。
  Future<({int count, List<CommunityPackage> tracks})> communityPackages() async {
    final j = _ok(await _get('/local/admin/community/packages'), '读取社区曲目');
    final list = (j['tracks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CommunityPackage.fromJson)
        .toList();
    return (count: (j['count'] as num?)?.toInt() ?? list.length, tracks: list);
  }

  /// 只解析、不发布：发布表单的预览（音符数 / 时长 / 密度 / 建议难度）。
  ///
  /// 服务端既能收 multipart 的 chart 文件，也能收 `{notes:[...]}`，
  /// 这里统一包成后者，同时兼容用户直接粘贴 `[...]` 或整份导出对象。
  Future<({ChartStat stat, int suggestedDifficulty})> communityChartStat(
      String chartJson) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(chartJson);
    } on FormatException catch (e) {
      throw ApiException('谱面不是合法 JSON：${e.message}');
    }
    final body = decoded is Map<String, dynamic> && decoded.containsKey('notes')
        ? decoded
        : <String, Object?>{'notes': decoded};
    final j = _ok(
        await _post('/local/admin/community/chart-stat', body), '解析谱面');
    final stat = j['stat'];
    if (stat is! Map<String, dynamic>) throw ApiException('谱面解析结果为空');
    return (
      stat: ChartStat.fromJson(stat),
      suggestedDifficulty: (j['suggested_difficulty'] as num?)?.toInt() ?? 0,
    );
  }

  /// 发布一首社区曲：入库 + 生成谱面/封面/标题/音频资源包 + 登记 download_m。
  ///
  /// 这是「推送到客户端」的唯一入口：成功后客户端在更新流程里能下载
  /// `1_<track>_1.zip` / `1_<track>_2.zip` 并开打。
  Future<PublishOutcome> publishCommunityTrack({
    required String name,
    required String chartJson,
    String nameEn = '',
    int difficulty = 0,
    int memberCategory = 4,
    int capitalValue = 0,
    String chartName = 'chart.json',
    List<int>? cover,
    String coverName = 'cover.png',
    List<int>? title,
    String titleName = 'title.png',
    List<int>? audio,
    String audioName = 'audio.ogg',
    void Function(double progress)? onProgress,
  }) async {
    // 谱面文件必须是裸音符数组（服务端按数组解析），把 {notes:[...]} 拆开。
    final Object? decoded;
    try {
      decoded = jsonDecode(chartJson);
    } on FormatException catch (e) {
      throw ApiException('谱面不是合法 JSON：${e.message}');
    }
    final notes = decoded is Map<String, dynamic> && decoded.containsKey('notes')
        ? decoded['notes']
        : decoded;

    final req = _ProgressMultipart(
      'POST',
      _uri('/local/admin/community/publish'),
      onProgress: onProgress,
    )
      ..fields['name'] = name
      ..fields['name_en'] = nameEn
      ..fields['difficulty'] = '$difficulty'
      ..fields['member_category'] = '$memberCategory'
      ..fields['capital_value'] = '$capitalValue';
    req.files.add(http.MultipartFile.fromBytes(
      'chart',
      utf8.encode(jsonEncode(notes)),
      filename: _fileName(chartName, 'chart.json'),
    ));
    if (cover != null && cover.isNotEmpty) {
      req.files.add(http.MultipartFile.fromBytes('cover', cover,
          filename: _fileName(coverName, 'cover.png')));
    }
    if (title != null && title.isNotEmpty) {
      req.files.add(http.MultipartFile.fromBytes('title', title,
          filename: _fileName(titleName, 'title.png')));
    }
    if (audio != null && audio.isNotEmpty) {
      req.files.add(http.MultipartFile.fromBytes('audio', audio,
          filename: _fileName(audioName, 'audio.ogg')));
    }

    final res = await _client
        .send(req)
        .timeout(const Duration(minutes: 3));
    final body = await http.Response.fromStream(res)
        .timeout(const Duration(minutes: 3));
    final j = _ok(await _decode(body), '发布社区曲');
    return PublishOutcome.fromJson(j);
  }

  /// 撤下一首社区曲：删 db 行、谱面与两个下发包。
  Future<int> withdrawCommunityTrack(int trackId) async {
    final j = _ok(
      await _post('/local/admin/community/withdraw', {'track_id': trackId}),
      '撤下社区曲',
    );
    return (j['track_id'] as num?)?.toInt() ?? trackId;
  }

  /// 社区曲封面（服务端从资源包里取该曲的 jacket）。
  String liveCoverUrl(int trackId) =>
      '$baseUrl/local/admin/live-cover/$trackId';

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

  /// 卡片头像的完整 URL。服务端从资源包里实时解出 PNG（128x128），
  /// 取不到时返回 404，界面回退成稀有度角标。
  String unitIconUrl(int unitId) => '$baseUrl/local/admin/unit-icon/$unitId';

  // ---------------------------------------------------------------- 自定义卡面

  /// 查一张卡在服务端资源包里有哪些纹理层（icon / card / navi / bust…）。
  Future<({int unitId, List<CardTexbLayer> layers, String message})> cardTexbLayers(
      int unitId) async {
    final j = await _get('/local/admin/cardart/texb', {'unit': '$unitId'});
    final list = (j['items'] as List<dynamic>? ?? const [])
        .map((e) => CardTexbLayer.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      unitId: (j['unit_id'] as num?)?.toInt() ?? unitId,
      layers: list,
      message: (j['message'] ?? '').toString(),
    );
  }

  /// 用本地路径收料（启动器与服务端同机时最省事）。
  Future<CardArtItem> importCardArtFromPath({
    required String path,
    String name = '',
    int unitId = 0,
    List<String> kinds = const [],
  }) async {
    final j = _ok(
      await _post('/local/admin/cardart/from-path', {
        'path': path,
        'name': name,
        'unit_id': unitId,
        'kinds': kinds,
      }),
      '收料',
    );
    return CardArtItem.fromJson(j);
  }

  /// 从设备直接上传一张 PNG 卡面到服务端归档（base64 内联，免去服务端路径依赖）。
  /// 移动端「制作卡面」的关键入口：手机里挑好图就能收料，不用把图先拷到服务器。
  Future<CardArtImportResult> uploadCardArtBase64({
    required String name,
    required List<int> pngBytes,
    int unitId = 0,
    List<String> kinds = const [],
  }) async {
    final body = <String, Object?>{
      'name': name,
      'png_base64': base64Encode(pngBytes),
      'unit_id': unitId,
      'kinds': kinds,
    };
    final j = _ok(await _post('/local/admin/cardart/import', body), '上传卡面');
    return CardArtImportResult.fromJson(j);
  }

  /// 落地。mode: command（只回命令）/ server（改写服务端资源包）/ push（推客户端）。
  Future<CardArtApplyResult> applyCardArt({
    required String name,
    int unitId = 0,
    List<String> kinds = const [],
    String mode = 'command',
  }) async {
    final j = await _post('/local/admin/cardart/apply', {
      'name': name,
      'unit_id': unitId,
      'kinds': kinds,
      'mode': mode,
    });
    return CardArtApplyResult.fromJson(j);
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

/// `MultipartRequest` 的进度版：包一层字节流统计已发送比例。
///
/// 用 `transform` 而不是自己 listen + 转发，是为了让暂停/恢复沿着流向上传导，
/// 大音频（几十 MB）上传时内存不会被整包缓存。
class _ProgressMultipart extends http.MultipartRequest {
  _ProgressMultipart(super.method, super.url, {this.onProgress});

  final void Function(double progress)? onProgress;

  @override
  http.ByteStream finalize() {
    final total = contentLength;
    var sent = 0;
    final counted = super.finalize().transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              sent += chunk.length;
              if (total > 0) {
                onProgress?.call((sent / total).clamp(0.0, 1.0).toDouble());
              }
              sink.add(chunk);
            },
          ),
        );
    return http.ByteStream(counted);
  }
}

/// 只取文件名：Android 选文件返回的可能是完整路径。
String _fileName(String name, String fallback) {
  final base = name.split(RegExp(r'[\\/]')).last.trim();
  return base.isEmpty ? fallback : base;
}
