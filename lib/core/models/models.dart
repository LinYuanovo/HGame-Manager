export 'tool.dart';

const _undefined = Object();

enum ViewMode {
  poster,
  list,
}

enum SortMode {
  titleAsc,
  titleDesc,
  addedTimeAsc,
  addedTimeDesc,
  lastPlayedTimeDesc,
  lastPlayedTimeAsc,
}

class Game {
  final int? id;
  final String path;
  final String? title;
  final String? version;
  final String? intro;
  final String? features;
  final String? changelog;
  final String? downloadUrl;
  final String? sourceUrl;
  final int playCount;
  final DateTime? lastPlayedTime;
  final DateTime? addedTime;
  final bool isFavorite;
  final bool isPlayed;
  final List<Tag> tags;
  final List<GameImage> images;
  final int coverIndex;
  final double rating;        // 评分 0-5，支持半星
  final String? review;       // 评论内容
  final String? savePath;  // 新增：存档路径
  final String? gameLauncher;
  final bool launcherLocked;

  Game({
    this.id,
    required this.path,
    this.title,
    this.version,
    this.intro,
    this.features,
    this.changelog,
    this.downloadUrl,
    this.sourceUrl,
    this.playCount = 0,
    this.lastPlayedTime,
    this.addedTime,
    this.isFavorite = false,
    this.isPlayed = false,
    this.tags = const [],
    this.images = const [],
    this.coverIndex = 0,
    this.rating = 0.0,
    this.review,
    this.savePath,  // 新增
    this.gameLauncher,
    this.launcherLocked = false,
  });

  factory Game.fromMap(Map<String, dynamic> map) {
    return Game(
      id: map['id'] as int?,
      path: map['path'] as String,
      title: map['title'] as String?,
      version: map['version'] as String?,
      intro: map['intro'] as String?,
      features: map['features'] as String?,
      changelog: map['changelog'] as String?,
      downloadUrl: map['download_url'] as String?,
      sourceUrl: map['source_url'] as String?,
      playCount: map['play_count'] as int? ?? 0,
      lastPlayedTime: map['last_played_time'] != null
          ? DateTime.parse(map['last_played_time'] as String)
          : null,
      addedTime: map['added_time'] != null
          ? DateTime.parse(map['added_time'] as String)
          : null,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      isPlayed: (map['is_played'] as int? ?? 0) == 1,
      coverIndex: map['cover_index'] as int? ?? 0,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      review: map['review'] as String?,
      savePath: map['save_path'] as String?,  // 新增
      gameLauncher: map['game_launcher'] as String?,
      launcherLocked: (map['launcher_locked'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'path': path,
      'title': title,
      'version': version,
      'intro': intro,
      'features': features,
      'changelog': changelog,
      'download_url': downloadUrl,
      'source_url': sourceUrl,
      'play_count': playCount,
      'last_played_time': lastPlayedTime?.toIso8601String(),
      'added_time': addedTime?.toIso8601String(),
      'is_favorite': isFavorite ? 1 : 0,
      'is_played': isPlayed ? 1 : 0,
      'cover_index': coverIndex,
      'rating': rating,
      if (review != null) 'review': review,
      if (savePath != null) 'save_path': savePath,  // 新增
      'game_launcher': gameLauncher,
      'launcher_locked': launcherLocked ? 1 : 0,
    };
  }

  Game copyWith({
    int? id,
    String? path,
    Object? title = _undefined,
    Object? version = _undefined,
    Object? intro = _undefined,
    Object? features = _undefined,
    Object? changelog = _undefined,
    Object? downloadUrl = _undefined,
    Object? sourceUrl = _undefined,
    int? playCount,
    DateTime? lastPlayedTime,
    DateTime? addedTime,
    bool? isFavorite,
    bool? isPlayed,
    List<Tag>? tags,
    List<GameImage>? images,
    int? coverIndex,
    Object? rating = _undefined,
    Object? review = _undefined,
    Object? savePath = _undefined,  // 新增
    Object? gameLauncher = _undefined,
    Object? launcherLocked = _undefined,
  }) {
    return Game(
      id: id ?? this.id,
      path: path ?? this.path,
      title: identical(title, _undefined) ? this.title : title as String?,
      version: identical(version, _undefined) ? this.version : version as String?,
      intro: identical(intro, _undefined) ? this.intro : intro as String?,
      features: identical(features, _undefined) ? this.features : features as String?,
      changelog: identical(changelog, _undefined) ? this.changelog : changelog as String?,
      downloadUrl: identical(downloadUrl, _undefined) ? this.downloadUrl : downloadUrl as String?,
      sourceUrl: identical(sourceUrl, _undefined) ? this.sourceUrl : sourceUrl as String?,
      playCount: playCount ?? this.playCount,
      lastPlayedTime: lastPlayedTime ?? this.lastPlayedTime,
      addedTime: addedTime ?? this.addedTime,
      isFavorite: isFavorite ?? this.isFavorite,
      isPlayed: isPlayed ?? this.isPlayed,
      tags: tags ?? this.tags,
      images: images ?? this.images,
      coverIndex: coverIndex ?? this.coverIndex,
      rating: identical(rating, _undefined) ? this.rating : rating as double,
      review: identical(review, _undefined) ? this.review : review as String?,
      savePath: identical(savePath, _undefined) ? this.savePath : savePath as String?,  // 新增
      gameLauncher: identical(gameLauncher, _undefined) ? this.gameLauncher : gameLauncher as String?,
      launcherLocked: identical(launcherLocked, _undefined) ? this.launcherLocked : launcherLocked as bool,
    );
  }
}

class Tag {
  final int? id;
  final String name;
  final String type; // 'custom' | 'series'
  final String? displayName;
  final bool isFavorite;
  final DateTime? createdAt;
  final int gameCount;

  static const String typeCustom = 'custom';
  static const String typeSeries = 'series';

  Tag({
    this.id,
    required this.name,
    required this.type,
    this.displayName,
    this.isFavorite = false,
    this.createdAt,
    this.gameCount = 0,
  });

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      displayName: map['display_name'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      gameCount: map['game_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'display_name': displayName,
      'is_favorite': isFavorite ? 1 : 0,
    };
  }

  Tag copyWith({
    int? id,
    String? name,
    String? type,
    Object? displayName = _undefined,
    bool? isFavorite,
    DateTime? createdAt,
    int? gameCount,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      displayName: identical(displayName, _undefined) ? this.displayName : displayName as String?,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      gameCount: gameCount ?? this.gameCount,
    );
  }
}

class GameImage {
  final int? id;
  final int gameId;
  final String imagePath;
  final int sortOrder;

  GameImage({
    this.id,
    required this.gameId,
    required this.imagePath,
    this.sortOrder = 0,
  });

  factory GameImage.fromMap(Map<String, dynamic> map) {
    return GameImage(
      id: map['id'] as int?,
      gameId: map['game_id'] as int,
      imagePath: map['image_path'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'game_id': gameId,
      'image_path': imagePath,
      'sort_order': sortOrder,
    };
  }
}
