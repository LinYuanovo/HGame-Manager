import 'package:flutter/foundation.dart' show immutable;

enum FolderMovePhase { scanning, copying, verifying, cleaning, done }

@immutable
class FolderMoveProgress {
  final FolderMovePhase phase;
  final int filesDone;
  final int filesTotal;
  final int bytesDone;
  final int bytesTotal;
  final String? currentFile;

  const FolderMoveProgress({
    required this.phase,
    this.filesDone = 0,
    this.filesTotal = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.currentFile,
  });

  double get fraction {
    if (bytesTotal > 0) return (bytesDone / bytesTotal).clamp(0.0, 1.0);
    if (filesTotal > 0) return (filesDone / filesTotal).clamp(0.0, 1.0);
    return 0.0;
  }
}

@immutable
class FolderMoveResult {
  final int fileCount;
  final int dirCount;
  final int totalBytes;
  final Duration elapsed;
  final String? warning;

  const FolderMoveResult({
    required this.fileCount,
    required this.dirCount,
    required this.totalBytes,
    required this.elapsed,
    this.warning,
  });
}

class FolderMoveException implements Exception {
  final String message;
  final String? relativePath;
  final int? bytesWritten;
  final int? expectedBytes;
  final String? cleanupWarning;

  /// 文件是否已经搬到目标位置（仅数据库记录更新失败时为 true）。
  final bool filesMoved;

  const FolderMoveException(
    this.message, {
    this.relativePath,
    this.bytesWritten,
    this.expectedBytes,
    this.cleanupWarning,
    this.filesMoved = false,
  });

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (relativePath != null) buffer.write('（文件: $relativePath）');
    if (bytesWritten != null && expectedBytes != null) {
      buffer.write('（已写入 $bytesWritten / $expectedBytes 字节）');
    }
    if (cleanupWarning != null) buffer.write('；$cleanupWarning');
    return buffer.toString();
  }
}

class FolderMoveCancelledException implements Exception {
  final String? cleanupWarning;

  const FolderMoveCancelledException({this.cleanupWarning});

  @override
  String toString() =>
      cleanupWarning == null ? '移动已取消' : '移动已取消；$cleanupWarning';
}
