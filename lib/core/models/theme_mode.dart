/// 主题模式枚举
enum AppThemeMode {
  light('浅色'),
  dark('深色'),
  system('跟随系统');

  final String label;
  const AppThemeMode(this.label);
}
