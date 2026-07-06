import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/cleared_game_path_utils.dart';

void main() {
  group('ClearedGamePathUtils', () {
    test('detects backup as an exact path segment', () {
      expect(
        ClearedGamePathUtils.hasBackupSegment(
          r'E:\Games\Cleared\Backup\Some Game',
        ),
        isTrue,
      );
      expect(
        ClearedGamePathUtils.hasBackupSegment(
          r'E:\Games\Cleared\Not a Backup Game',
        ),
        isFalse,
      );
    });

    test('normalizes backup folder and local folder names for matching', () {
      expect(
        ClearedGamePathUtils.isLikelyBackupForLocalName(
          '寻找魅魔_Not a Succubus',
          'Not a Succubus',
        ),
        isTrue,
      );
    });

    test('matches local folder and database title in either direction', () {
      expect(
        ClearedGamePathUtils.isLikelySameGameName(
          'Not a Succubus',
          '寻找魅魔_Not a Succubus',
        ),
        isTrue,
      );
    });
  });
}
