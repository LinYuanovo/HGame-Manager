enum ScrapeMode {
  quickScrape('quick_scrape', '快速刮削'),
  rescrape('rescrape', '重新刮削'),
  scraperCenter('scraper_center', '刮削中心'),
  singleAdd('single_add', '单个添加'),
  batchAdd('batch_add', '批量添加');

  final String key;
  final String label;
  const ScrapeMode(this.key, this.label);
}

class ScrapeModeConfig {
  final bool renameFolder;
  final bool moveToSorted;

  const ScrapeModeConfig({this.renameFolder = false, this.moveToSorted = false});

  ScrapeModeConfig copyWith({bool? renameFolder, bool? moveToSorted}) =>
    ScrapeModeConfig(
      renameFolder: renameFolder ?? this.renameFolder,
      moveToSorted: moveToSorted ?? this.moveToSorted,
    );

  Map<String, dynamic> toMap() => {'renameFolder': renameFolder, 'moveToSorted': moveToSorted};

  factory ScrapeModeConfig.fromMap(Map<String, dynamic> map) =>
    ScrapeModeConfig(
      renameFolder: map['renameFolder'] as bool? ?? false,
      moveToSorted: map['moveToSorted'] as bool? ?? false,
    );
}

class ScrapeModeConfigs {
  final Map<ScrapeMode, ScrapeModeConfig> configs;
  const ScrapeModeConfigs({required this.configs});

  ScrapeModeConfig getConfig(ScrapeMode mode) => configs[mode] ?? const ScrapeModeConfig();
  bool shouldRename(ScrapeMode mode) => getConfig(mode).renameFolder;
  bool shouldMove(ScrapeMode mode) => getConfig(mode).moveToSorted;

  Map<String, dynamic> toMap() => {
    for (final entry in configs.entries) entry.key.key: entry.value.toMap(),
  };

  factory ScrapeModeConfigs.fromMap(Map<String, dynamic> map) {
    final configs = <ScrapeMode, ScrapeModeConfig>{};
    for (final mode in ScrapeMode.values) {
      final modeMap = map[mode.key];
      if (modeMap is Map<String, dynamic>) {
        configs[mode] = ScrapeModeConfig.fromMap(modeMap);
      }
    }
    return ScrapeModeConfigs(configs: configs);
  }

  factory ScrapeModeConfigs.defaults() => ScrapeModeConfigs(
    configs: {for (final mode in ScrapeMode.values) mode: const ScrapeModeConfig()},
  );
}
