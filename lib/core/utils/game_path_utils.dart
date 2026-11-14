import 'package:path/path.dart' as path;

class GamePathUtils {
  const GamePathUtils._();

  static String comparisonKey(String value) =>
      path.windows.normalize(value).toLowerCase();
}
