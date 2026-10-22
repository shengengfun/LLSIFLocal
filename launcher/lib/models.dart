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

  /// add_type 1000 是部员（卡），其余按道具看。
  bool get isUnit => addType == 1000;
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

  const CardArtItem({
    required this.name,
    required this.pngPath,
    required this.size,
    required this.width,
    required this.height,
    required this.updatedAt,
  });

  factory CardArtItem.fromJson(Map<String, dynamic> j) => CardArtItem(
        name: _asString(j['name']),
        pngPath: _asString(j['png_path']),
        size: _asInt(j['size']),
        width: _asInt(j['width']),
        height: _asInt(j['height']),
        updatedAt: _asString(j['updated_at']),
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
