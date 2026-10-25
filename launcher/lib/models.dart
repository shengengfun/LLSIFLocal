/// 与服务端 `/local/*` 管理接口对应的数据模型。
library;

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String _asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  return v.toString();
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  return false;
}

double _asDouble(dynamic v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

class Overview {
  final String appVersion;
  final int userCount;
  final int unitMaster;
  final int cardOwned;
  final int accessories;
  final int liveTotal;
  final int liveUnlocked;
  final int scenarios;
  final int diskFree;
  final String dataDb;
  final List<String> missing;

  const Overview({
    required this.appVersion,
    required this.userCount,
    required this.unitMaster,
    required this.cardOwned,
    required this.accessories,
    required this.liveTotal,
    required this.liveUnlocked,
    required this.scenarios,
    required this.diskFree,
    required this.dataDb,
    required this.missing,
  });

  factory Overview.fromJson(Map<String, dynamic> j) => Overview(
        appVersion: _asString(j['app_version']),
        userCount: _asInt(j['user_count']),
        unitMaster: _asInt(j['unit_master']),
        cardOwned: _asInt(j['card_owned']),
        accessories: _asInt(j['accessories']),
        liveTotal: _asInt(j['live_total']),
        liveUnlocked: _asInt(j['live_unlocked']),
        scenarios: _asInt(j['scenarios']),
        diskFree: _asInt(j['disk_free']),
        dataDb: _asString(j['data_db']),
        missing: (j['missing'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  bool has(String capability) => !missing.contains(capability);
}

class AccountItem {
  final int userId;
  final String phone;
  final String name;
  final int level;
  final int lastLoginTime;
  final bool bound;

  const AccountItem({
    required this.userId,
    required this.phone,
    required this.name,
    required this.level,
    required this.lastLoginTime,
    required this.bound,
  });

  factory AccountItem.fromJson(Map<String, dynamic> j) => AccountItem(
        userId: _asInt(j['user_id']),
        phone: _asString(j['phone']),
        name: _asString(j['name']),
        level: _asInt(j['level']),
        lastLoginTime: _asInt(j['last_login_time']),
        bound: _asBool(j['bound']),
      );
}

class Player {
  final int userId;
  final String phone;
  final String name;
  final String desc;
  final int level;
  final int exp;
  final int nextExp;
  final int gameCoin;
  final int snsCoin;
  final int energyMax;
  final int overMaxEnergy;
  final int lastLoginTime;
  final int unitCount;
  final int accessoryCount;
  final int deckCount;
  final bool bound;
  final String boundDevice;

  const Player({
    required this.userId,
    required this.phone,
    required this.name,
    required this.desc,
    required this.level,
    required this.exp,
    required this.nextExp,
    required this.gameCoin,
    required this.snsCoin,
    required this.energyMax,
    required this.overMaxEnergy,
    required this.lastLoginTime,
    required this.unitCount,
    required this.accessoryCount,
    required this.deckCount,
    required this.bound,
    required this.boundDevice,
  });

  factory Player.fromJson(Map<String, dynamic> j) => Player(
        userId: _asInt(j['user_id']),
        phone: _asString(j['phone']),
        name: _asString(j['name']),
        desc: _asString(j['desc']),
        level: _asInt(j['level']),
        exp: _asInt(j['exp']),
        nextExp: _asInt(j['next_exp']),
        gameCoin: _asInt(j['game_coin']),
        snsCoin: _asInt(j['sns_coin']),
        energyMax: _asInt(j['energy_max']),
        overMaxEnergy: _asInt(j['over_max_energy']),
        lastLoginTime: _asInt(j['last_login_time']),
        unitCount: _asInt(j['unit_count']),
        accessoryCount: _asInt(j['accessory_count']),
        deckCount: _asInt(j['deck_count']),
        bound: _asBool(j['bound']),
        boundDevice: _asString(j['bound_device']),
      );
}

class UnitItem {
  final int unitId;
  final String name;
  final int rarity;
  final int attribute;
  final int hpMax;
  final int smileMax;
  final int pureMax;
  final int coolMax;
  final bool owned;
  final int skillId;
  final int unitNumber;
  final String normalIcon;
  final String rankMaxIcon;

  const UnitItem({
    required this.unitId,
    required this.name,
    required this.rarity,
    required this.attribute,
    required this.hpMax,
    required this.smileMax,
    required this.pureMax,
    required this.coolMax,
    required this.owned,
    this.skillId = 0,
    this.unitNumber = 0,
    this.normalIcon = '',
    this.rankMaxIcon = '',
  });

  factory UnitItem.fromJson(Map<String, dynamic> j) => UnitItem(
        unitId: _asInt(j['unit_id']),
        name: _asString(j['name']),
        rarity: _asInt(j['rarity']),
        attribute: _asInt(j['attribute']),
        hpMax: _asInt(j['hp_max']),
        smileMax: _asInt(j['smile_max']),
        pureMax: _asInt(j['pure_max']),
        coolMax: _asInt(j['cool_max']),
        owned: _asInt(j['owned_by_count']) > 0,
        skillId: _asInt(j['skill_id']),
        unitNumber: _asInt(j['unit_number']),
        normalIcon: _asString(j['normal_icon']),
        rankMaxIcon: _asString(j['rank_max_icon']),
      );
}

/// 物品表一行（发放面板右侧的查询列表）。
class ItemEntry {
  final int itemId;
  final String name;
  final String nameEn;
  final String desc;
  final String icon;
  final int category;

  const ItemEntry({
    required this.itemId,
    required this.name,
    required this.nameEn,
    required this.desc,
    required this.icon,
    required this.category,
  });

  factory ItemEntry.fromJson(Map<String, dynamic> j) => ItemEntry(
        itemId: _asInt(j['item_id']),
        name: _asString(j['name']),
        nameEn: _asString(j['name_en']),
        desc: _asString(j['desc']),
        icon: _asString(j['icon']),
        category: _asInt(j['category']),
      );
}

/// 社区谱库的一张谱。
class CommunityChart {
  final String name;
  final int notes;
  final double seconds;
  final List<int> attached;
  /// 附加到的曲目（第一个命中），0 = 尚未附加。
  final int trackId;
  /// 封面相对路径（/local/admin/live-cover/:track），空 = 未附加无封面。
  final String coverUrl;

  const CommunityChart({
    required this.name,
    required this.notes,
    required this.seconds,
    required this.attached,
    this.trackId = 0,
    this.coverUrl = '',
  });

  factory CommunityChart.fromJson(Map<String, dynamic> j) => CommunityChart(
        name: _asString(j['name']),
        notes: _asInt(j['notes']),
        seconds: _asDouble(j['seconds']),
        attached: (j['attached'] as List<dynamic>? ?? const [])
            .map((e) => _asInt(e))
            .toList(),
        trackId: _asInt(j['track_id']),
        coverUrl: _asString(j['cover_url']),
      );
}

class AccessoryItem {
  final int accessoryId;
  final String name;
  final int rarity;
  final int smileMax;
  final int pureMax;
  final int coolMax;

  const AccessoryItem({
    required this.accessoryId,
    required this.name,
    required this.rarity,
    required this.smileMax,
    required this.pureMax,
    required this.coolMax,
  });

  factory AccessoryItem.fromJson(Map<String, dynamic> j) => AccessoryItem(
        accessoryId: _asInt(j['accessory_id']),
        name: _asString(j['name']),
        rarity: _asInt(j['rarity']),
        smileMax: _asInt(j['smile_max']),
        pureMax: _asInt(j['pure_max']),
        coolMax: _asInt(j['cool_max']),
      );
}

class LiveItem {
  final int liveDifficultyId;
  final int liveSettingId;
  final int liveTrackId;
  final int difficulty;
  final int stageLevel;
  final String notesAsset;
  final int sRankScore;
  final int sRankCombo;
  final bool unlocked;
  final bool special;
  final bool enabled;

  const LiveItem({
    required this.liveDifficultyId,
    required this.liveSettingId,
    required this.liveTrackId,
    required this.difficulty,
    required this.stageLevel,
    required this.notesAsset,
    required this.sRankScore,
    required this.sRankCombo,
    required this.unlocked,
    this.special = false,
    this.enabled = true,
  });

  factory LiveItem.fromJson(Map<String, dynamic> j) => LiveItem(
        liveDifficultyId: _asInt(j['live_difficulty_id']),
        liveSettingId: _asInt(j['live_setting_id']),
        liveTrackId: _asInt(j['live_track_id']),
        difficulty: _asInt(j['difficulty']),
        stageLevel: _asInt(j['stage_level']),
        notesAsset: _asString(j['notes_asset']),
        sRankScore: _asInt(j['s_rank_score']),
        sRankCombo: _asInt(j['s_rank_combo']),
        unlocked: _asBool(j['unlocked']),
        special: _asBool(j['special']),
        // 老服务端没有这个字段，按「上线」处理避免误报。
        enabled: j.containsKey('enabled') ? _asBool(j['enabled']) : true,
      );
}

/// 礼物箱里的一条。
class MailBoxItem {
  final int presentBoxId;
  final int addType;
  final int itemId;
  final int amount;
  final String subject;
  final String insertDate;
  final bool opened;

  const MailBoxItem({
    required this.presentBoxId,
    required this.addType,
    required this.itemId,
    required this.amount,
    required this.subject,
    required this.insertDate,
    required this.opened,
  });

  factory MailBoxItem.fromJson(Map<String, dynamic> j) => MailBoxItem(
        presentBoxId: _asInt(j['present_box_id']),
        addType: _asInt(j['add_type']),
        itemId: _asInt(j['item_id']),
        amount: _asInt(j['amount']),
        subject: _asString(j['subject']),
        insertDate: _asString(j['insert_date']),
        opened: _asBool(j['opened']),
      );

  /// add_type 1001 是部员（卡），1000 是道具（与客户端 const.lua 的
  /// ADD_TYPES 对齐）。
  bool get isUnit => addType == 1001;
}

/// 一首曲子下的一个难度。
class LiveDifficultyItem {
  final int liveDifficultyId;
  final int difficulty;
  final int stageLevel;
  final String notesAsset;
  final int sRankScore;
  final int sRankCombo;
  final bool unlocked;
  final bool special;
  final bool enabled;

  const LiveDifficultyItem({
    required this.liveDifficultyId,
    required this.difficulty,
    required this.stageLevel,
    required this.notesAsset,
    required this.sRankScore,
    required this.sRankCombo,
    required this.unlocked,
    required this.special,
    required this.enabled,
  });

  factory LiveDifficultyItem.fromJson(Map<String, dynamic> j) =>
      LiveDifficultyItem(
        liveDifficultyId: _asInt(j['live_difficulty_id']),
        difficulty: _asInt(j['difficulty']),
        stageLevel: _asInt(j['stage_level']),
        notesAsset: _asString(j['notes_setting_asset']),
        sRankScore: _asInt(j['s_rank_score']),
        sRankCombo: _asInt(j['s_rank_combo']),
        unlocked: _asBool(j['unlocked']),
        special: _asBool(j['special']),
        enabled: j.containsKey('enabled') ? _asBool(j['enabled']) : true,
      );
}

/// 一首曲子（聚合所有难度）。曲名来自服务端 `live_meta`，缺失时界面回退到「曲目 #id」。
class LiveTrackItem {
  final int liveTrackId;
  final String name;
  final String nameEn;
  final String coverAsset;
  final String coverUrl;
  final bool hasCover;
  final int difficultyCount;
  final int enabledCount;
  final List<LiveDifficultyItem> difficulties;

  const LiveTrackItem({
    required this.liveTrackId,
    required this.name,
    required this.nameEn,
    required this.coverAsset,
    required this.coverUrl,
    required this.hasCover,
    required this.difficultyCount,
    required this.enabledCount,
    required this.difficulties,
  });

  /// 界面显示用的标题：优先日文原名，其次英文，最后回退曲目号。
  String get displayName {
    if (name.isNotEmpty) return name;
    if (nameEn.isNotEmpty) return nameEn;
    return '曲目 #$liveTrackId';
  }

  bool get hasName => name.isNotEmpty || nameEn.isNotEmpty;

  /// 已上线的难度数 / 总数，用于「部分下线」标记。
  bool get partiallyOffline => enabledCount > 0 && enabledCount < difficultyCount;
  bool get fullyOffline => enabledCount == 0;

  factory LiveTrackItem.fromJson(Map<String, dynamic> j) {
    final diffs = (j['difficulties'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LiveDifficultyItem.fromJson)
        .toList();
    return LiveTrackItem(
      liveTrackId: _asInt(j['live_track_id']),
      name: _asString(j['name']),
      nameEn: _asString(j['name_en']),
      coverAsset: _asString(j['cover_asset']),
      coverUrl: _asString(j['cover_url']),
      hasCover: _asBool(j['has_cover']),
      difficultyCount: _asInt(j['difficulty_count']),
      enabledCount: _asInt(j['enabled_count']),
      difficulties: diffs,
    );
  }
}

/// 卡面库条目。
class CardArtItem {
  final String name;
  final String pngPath;
  final int size;
  final int width;
  final int height;
  final String updatedAt;
  final int unitId;
  final List<String> kinds;

  const CardArtItem({
    required this.name,
    required this.pngPath,
    required this.size,
    required this.width,
    required this.height,
    required this.updatedAt,
    this.unitId = 0,
    this.kinds = const [],
  });

  factory CardArtItem.fromJson(Map<String, dynamic> j) => CardArtItem(
        name: _asString(j['name']),
        pngPath: _asString(j['png_path']),
        size: _asInt(j['size']),
        width: _asInt(j['width']),
        height: _asInt(j['height']),
        updatedAt: _asString(j['updated_at']),
        unitId: _asInt(j['unit_id']),
        kinds: (j['kinds'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// 从设备上传卡面后的返回。
class CardArtImportResult {
  final bool ok;
  final String message;
  final String name;
  final String pngPath;
  final int width;
  final int height;
  final String nextSteps;

  const CardArtImportResult({
    required this.ok,
    this.message = '',
    this.name = '',
    this.pngPath = '',
    this.width = 0,
    this.height = 0,
    this.nextSteps = '',
  });

  factory CardArtImportResult.fromJson(Map<String, dynamic> j) =>
      CardArtImportResult(
        ok: j['ok'] == true,
        message: _asString(j['message']),
        name: _asString(j['name']),
        pngPath: _asString(j['png_path']),
        width: _asInt(j['width']),
        height: _asInt(j['height']),
        nextSteps: _asString(j['next_steps'] ?? j['nextSteps']),
      );
}

/// 一张卡在服务端资源包里的一层纹理。
class CardTexbLayer {
  final String kind;
  final String entry;
  final String archive;
  final bool signed;

  const CardTexbLayer({
    required this.kind,
    required this.entry,
    required this.archive,
    required this.signed,
  });

  String get fileName {
    final i = entry.lastIndexOf('/');
    return i < 0 ? entry : entry.substring(i + 1);
  }

  factory CardTexbLayer.fromJson(Map<String, dynamic> j) => CardTexbLayer(
        kind: _asString(j['kind']),
        entry: _asString(j['entry']),
        archive: _asString(j['archive']),
        signed: j['signed'] == true,
      );
}

/// 卡面落地的结果。
class CardArtApplyResult {
  final bool ok;
  final String message;
  final String mode;
  final String command;
  final String output;
  final bool ran;

  const CardArtApplyResult({
    required this.ok,
    required this.message,
    required this.mode,
    required this.command,
    required this.output,
    required this.ran,
  });

  factory CardArtApplyResult.fromJson(Map<String, dynamic> j) =>
      CardArtApplyResult(
        ok: j['ok'] == true,
        message: _asString(j['message']),
        mode: _asString(j['mode']),
        command: _asString(j['command']),
        output: _asString(j['output']),
        ran: j['ran'] == true,
      );
}

class BackupItem {
  final String file;
  final int size;
  final int time;

  const BackupItem({required this.file, required this.size, required this.time});

  factory BackupItem.fromJson(Map<String, dynamic> j) => BackupItem(
        file: _asString(j['file']),
        size: _asInt(j['size']),
        time: _asInt(j['time']),
      );
}

/// 谱面解析结果（`/local/admin/community/chart-stat`）。
class ChartStat {
  final int notes;
  final double seconds;
  final double density;
  final int maxChord;
  final int chords;
  final int longNotes;
  final int starNotes;
  final bool swing;
  final int lanes;

  const ChartStat({
    required this.notes,
    required this.seconds,
    this.density = 0,
    this.maxChord = 0,
    this.chords = 0,
    this.longNotes = 0,
    this.starNotes = 0,
    this.swing = false,
    this.lanes = 0,
  });

  factory ChartStat.fromJson(Map<String, dynamic> j) => ChartStat(
        notes: _asInt(j['notes']),
        seconds: _asDouble(j['seconds']),
        density: _asDouble(j['notes_per_sec']),
        maxChord: _asInt(j['max_chord']),
        chords: _asInt(j['chord_count']),
        longNotes: _asInt(j['long_notes']),
        starNotes: _asInt(j['star_notes']),
        swing: _asInt(j['swing_flag']) != 0,
        lanes: _asInt(j['lanes']),
      );

  /// `m:ss`，用于卡片上显示时长。
  String get duration {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 已发布到服务端的社区曲（`/local/admin/community/packages` 的一行）。
///
/// 这些是真正下发给客户端的曲目：谱面在 beatmaps/、资源在
/// `1_<track>_1.zip`、安装信息在 `1_<track>_2.zip`，并在 download_m 登记。
class CommunityPackage {
  final int trackId;
  final String name;
  final int memberCategory;
  final int difficulty;
  final int difficultyId;
  final String notesAsset;
  final int notes;
  final double seconds;
  final int pkgSize;
  final bool chartOk;
  final bool pkg1Ok;
  final bool pkg2Ok;
  final bool downloadOk;
  final bool sizeMismatch;
  final List<String> missing;

  const CommunityPackage({
    required this.trackId,
    required this.name,
    this.memberCategory = 0,
    this.difficulty = 0,
    this.difficultyId = 0,
    this.notesAsset = '',
    this.notes = 0,
    this.seconds = 0,
    this.pkgSize = 0,
    this.chartOk = false,
    this.pkg1Ok = false,
    this.pkg2Ok = false,
    this.downloadOk = false,
    this.sizeMismatch = false,
    this.missing = const [],
  });

  factory CommunityPackage.fromJson(Map<String, dynamic> j) => CommunityPackage(
        trackId: _asInt(j['track_id']),
        name: _asString(j['name']),
        memberCategory: _asInt(j['member_category']),
        difficulty: _asInt(j['difficulty']),
        difficultyId: _asInt(j['difficulty_id']),
        notesAsset: _asString(j['notes_asset']),
        notes: _asInt(j['notes']),
        seconds: _asDouble(j['seconds']),
        pkgSize: _asInt(j['pkg_size']),
        chartOk: _asBool(j['chart_ok']),
        pkg1Ok: _asBool(j['pkg1_ok']),
        pkg2Ok: _asBool(j['pkg2_ok']),
        downloadOk: _asBool(j['download_ok']),
        sizeMismatch: _asBool(j['size_mismatch']),
        missing: (j['missing'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  /// 体检全绿：客户端能正常下载并开打。
  bool get healthy => missing.isEmpty && !sizeMismatch;

  /// 包大小与 download_m 登记不一致 —— 客户端会判定下载失败并弹「通信中断」。
  bool get breaksClient => sizeMismatch;

  static const _difficultyLabels = [
    '未标注',
    '普通',
    '困难',
    '专家',
    '大师',
    '特殊 1',
    '特殊 2',
  ];

  String get difficultyLabel =>
      _difficultyLabels[difficulty.clamp(0, _difficultyLabels.length - 1)];

  static const _memberLabels = ['其他', "μ's", 'Aqours', '虹咲', 'Liella'];

  String get memberLabel =>
      _memberLabels[memberCategory.clamp(0, _memberLabels.length - 1)];

  /// 徽章用：把 missing 翻成人话（顺序即严重度）。
  List<String> get problemLabels {
    final out = <String>[];
    if (sizeMismatch) out.add('包大小不一致（客户端会「通信中断」）');
    for (final m in missing) {
      switch (m) {
        case 'chart':
          out.add('缺谱面文件');
        case '1_T_1.zip':
          out.add('缺资源包');
        case '1_T_2.zip':
          out.add('缺安装信息包');
        case 'download_m':
          out.add('未登记下载（客户端看不到）');
        case 'download_m.pkg_size':
          break; // 已由 sizeMismatch 覆盖，避免重复两行
        default:
          out.add(m);
      }
    }
    return out;
  }
}

/// 发布结果（`/local/admin/community/publish`）。
class PublishOutcome {
  final int trackId;
  final int settingId;
  final int difficultyId;
  final int musicId;
  final ChartStat? chart;
  final List<String> resources;
  final List<String> download;

  const PublishOutcome({
    required this.trackId,
    required this.settingId,
    required this.difficultyId,
    required this.musicId,
    this.chart,
    this.resources = const [],
    this.download = const [],
  });

  factory PublishOutcome.fromJson(Map<String, dynamic> j) => PublishOutcome(
        trackId: _asInt(j['track_id']),
        settingId: _asInt(j['setting_id']),
        difficultyId: _asInt(j['difficulty_id']),
        musicId: _asInt(j['music_id']),
        chart: j['chart'] is Map<String, dynamic>
            ? ChartStat.fromJson(j['chart'] as Map<String, dynamic>)
            : null,
        resources: (j['resources'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        download: (j['download'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  /// 没生成下发包 = 客户端下载不到资源（通常是没给音频/封面）。
  bool get lacksPackages => download.isEmpty;
}
