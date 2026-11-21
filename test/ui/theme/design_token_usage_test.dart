import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('界面颜色、字号、图标、圆角和常用间距统一使用主题 token', () {
    final violations = <String>[];
    final rules = {
      '颜色字面量':
          RegExp(r'\bColor(?:\(|\.from\w+\()|\bColors\.(?!transparent\b)\w+'),
      '固定主题色': RegExp(
          r'AppTheme\.(?:primaryColor|primaryLightColor|secondaryColor|darkPrimaryColor|darkSurfaceColor|darkBorderColor|textPrimary|textSecondary|surfaceColor|backgroundColor|borderColor|primaryGradient)\b'),
      '字号或图标尺寸': RegExp(r'\b(?:fontSize|iconSize|size):\s*\d'),
      '字号、图标和间距默认值': RegExp(
          r'\b(?:_?\w*[Ff]ontSize|\w*[Ii]conSize|spacing|starGap)\s*=\s*\d'),
      '圆角': RegExp(r'\b(?:BorderRadius|Radius)\.circular\(\s*[1-9]'),
      '间距': RegExp(
          r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^()]*?(?<![\w.])[1-9]\d*(?:\.\d+)?\b[^()]*?\)'),
      '短间隔': RegExp(
          r'SizedBox\((?:width|height):\s*(?:[1-9]|[1-3]\d|40)(?:\.0)?\s*\)'),
      '页面按钮样式': RegExp(r'\b\w+Button\s*\.\s*styleFrom\s*\(|\bButtonStyle\s*\('),
      '页面字重或行高': RegExp(r'\bFontWeight\.|\bheight:\s*1\.\d+\b'),
      '页面控件字体': RegExp(r'\btextStyle:\s*(?:const\s+)?TextStyle\s*\('),
      '按钮与控件字体覆盖': RegExp(
          r'textStyle:\s*(?:const\s+)?(?:WidgetStatePropertyAll\s*\(\s*)?(?:const\s+)?TextStyle\s*\('),
    };
    for (final file in [
      ...Directory('lib/ui').listSync(recursive: true).whereType<File>(),
      File('lib/main.dart'),
    ]) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('app_theme.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final rule in rules.entries) {
        for (final match in rule.value.allMatches(source)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          violations.add('${file.path}:$line ${rule.key}');
        }
      }
      for (final match in RegExp(r'''fontFamily\s*:\s*['"][^'"]+['"]''')
          .allMatches(source)) {
        if (file.path.endsWith('settings_page.dart') &&
            match.group(0) == "fontFamily: 'MapleMonoNL-NF-CN'") {
          continue;
        }
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        violations.add('${file.path}:$line 固定字体');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
