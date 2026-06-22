// lib/core/services/backup_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../models/backup_entry.dart';

/// 存档备份服务
/// 负责本地备份的创建、还原、删除、重命名、导入
class BackupService {
  /// 备份文件夹名称
  static const String _backupFolderName = 'HGMBackup';
  /// zip 内的存档位置元数据文件名
  static const String _metaFileName = 'save_location.txt';
  /// 自动导入的"存档"文件夹备份名称（不含 .zip）
  static const String _autoImportName = '导入存档';
  /// 还原前自动备份的名称前缀
  static const String _preRestorePrefix = '还原前备份';

  /// 获取游戏的 HGMBackup 目录
  Directory getBackupDir(String gamePath) {
    return Directory(p.join(gamePath, _backupFolderName));
  }

  /// 将实际存档路径编码为带占位符的便携格式
  /// [savePath] 实际绝对路径（如 C:\Users\xxx\AppData\LocalLow\...）
  /// [gamePath] 游戏根目录
  /// 返回带 %USERPROFILE% 或 %GameDir% 标识的路径字符串
  String encodeSavePath(String savePath, String gamePath) {
    final normalizedSave = savePath.replaceAll('/', '\\');
    final normalizedGame = gamePath.replaceAll('/', '\\');

    // 检查是否在 USERPROFILE 目录下
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    if (userProfile.isNotEmpty) {
      final normalizedUP = userProfile.replaceAll('/', '\\');
      if (normalizedSave.toLowerCase().startsWith(normalizedUP.toLowerCase())) {
        final relative = normalizedSave.substring(normalizedUP.length);
        return '%USERPROFILE%${relative.startsWith('\\') ? relative : '\\$relative'}';
      }
    }

    // 检查是否在游戏目录下
    if (normalizedSave.toLowerCase().startsWith(normalizedGame.toLowerCase())) {
      final relative = normalizedSave.substring(normalizedGame.length);
      return '%GameDir%${relative.startsWith('\\') ? relative : '\\$relative'}';
    }

    // 无法匹配占位符时返回原路径
    return normalizedSave;
  }

  /// 将带占位符的便携路径解码为实际绝对路径
  /// [portablePath] 包含 %USERPROFILE% 或 %GameDir% 占位符的路径
  /// [gamePath] 当前游戏根目录
  String decodeSavePath(String portablePath, String gamePath) {
    if (portablePath.startsWith('%USERPROFILE%')) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final relative = portablePath.substring('%USERPROFILE%'.length);
      return p.join(userProfile, relative.replaceAll('\\', p.separator));
    }
    if (portablePath.startsWith('%GameDir%')) {
      final relative = portablePath.substring('%GameDir%'.length);
      return p.join(gamePath, relative.replaceAll('\\', p.separator));
    }
    return portablePath;
  }

  /// 列出游戏的所有本地备份
  Future<List<BackupEntry>> listBackups(String gamePath) async {
    final backupDir = getBackupDir(gamePath);
    if (!await backupDir.exists()) return [];

    final entries = <BackupEntry>[];
    await for (final entity in backupDir.list()) {
      if (entity is File && entity.path.endsWith('.zip')) {
        final fileName = p.basename(entity.path);
        final stat = await entity.stat();
        final name = fileName.substring(0, fileName.length - 4); // 去掉 .zip

        // 判断备份来源：
        // - 还原前备份：以"还原前备份"开头
        // - 手动备份：文件名为时间戳格式（YYYY-MM-DD HH-MM）
        // - 导入备份：其他所有（自动导入的"导入存档"和用户自选导入的文件）
        BackupSource source;
        if (name.startsWith(_preRestorePrefix)) {
          source = BackupSource.preRestore;
        } else if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}-\d{2}').hasMatch(name)) {
          source = BackupSource.manual;
        } else {
          source = BackupSource.imported;
        }

        DateTime? date;
        // 尝试从文件名解析日期，格式：YYYY-MM-DD HH-MM
        try {
          final dateMatch = RegExp(r'^(\d{4}-\d{2}-\d{2} \d{2}-\d{2})').firstMatch(name);
          if (dateMatch != null) {
            final parts = dateMatch.group(1)!.split(' ');
            final dateParts = parts[0].split('-');
            final timeParts = parts[1].split('-');
            date = DateTime(
              int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]),
              int.parse(timeParts[0]), int.parse(timeParts[1]),
            );
          }
        } catch (_) {}
        // 回退到文件修改时间
        date ??= stat.modified;

        entries.add(BackupEntry(
          name: name,
          fileName: fileName,
          sizeBytes: stat.size,
          date: date,
          source: source,
          filePath: entity.path,
        ));
      }
    }

    // 按日期降序排列
    entries.sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    return entries;
  }

  /// 创建存档备份
  /// 成功返回 BackupEntry，失败返回 null
  Future<BackupEntry?> createBackup({
    required String gamePath,
    required String savePath,
    String? customName,
  }) async {
    final saveDir = Directory(savePath);
    if (!await saveDir.exists()) {
      debugPrint('[BackupService] 存档目录不存在: $savePath');
      return null;
    }

    final backupDir = getBackupDir(gamePath);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    // 生成备份名称
    final now = DateTime.now();
    final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
    final name = customName ?? timestamp;
    final fileName = '$name.zip';
    final filePath = p.join(backupDir.path, fileName);

    // "还原前备份"始终只保留一个，已存在则覆盖
    if (customName == _preRestorePrefix && await File(filePath).exists()) {
      await File(filePath).delete();
    } else if (await File(filePath).exists()) {
      // 其他备份不允许重复
      debugPrint('[BackupService] 备份已存在: $filePath');
      return null;
    }

    // 检查存档文件夹大小，防止内存溢出（限制 500MB）
    int totalSize = 0;
    await for (final entity in saveDir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        totalSize += stat.size;
        if (totalSize > 500 * 1024 * 1024) {
          debugPrint('[BackupService] 存档文件夹过大，无法内存压缩: ${totalSize ~/ (1024*1024)}MB');
          return null;
        }
      }
    }

    try {
      final archive = Archive();

      // 添加存档位置元数据文件（带占位符的便携路径）
      final portablePath = encodeSavePath(savePath, gamePath);
      final metaBytes = utf8.encode(portablePath);
      archive.addFile(ArchiveFile(_metaFileName, metaBytes.length, metaBytes));

      // 将存档目录下的所有内容添加到压缩包（不包含存档文件夹本身）
      await _addDirectoryToArchive(archive, saveDir, '');

      // 编码为 zip
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        debugPrint('[BackupService] Zip 编码失败');
        return null;
      }

      await File(filePath).writeAsBytes(zipBytes);

      return BackupEntry(
        name: name,
        fileName: fileName,
        sizeBytes: zipBytes.length,
        date: now,
        source: customName == _preRestorePrefix ? BackupSource.preRestore : BackupSource.manual,
        filePath: filePath,
      );
    } catch (e) {
      debugPrint('[BackupService] createBackup 错误: $e');
      return null;
    }
  }

  /// 还原备份到存档目录
  /// 还原前会自动创建"还原前备份"
  /// 成功返回 true
  Future<bool> restoreBackup({
    required String gamePath,
    required String backupFilePath,
    required String savePath,
  }) async {
    try {
      final backupFile = File(backupFilePath);
      if (!await backupFile.exists()) {
        debugPrint('[BackupService] 备份文件不存在: $backupFilePath');
        return false;
      }

      final saveDir = Directory(savePath);

      // 如果存档目录存在且有内容，先创建还原前备份
      if (await saveDir.exists()) {
        final hasContent = await saveDir.list().any((_) => true);
        if (hasContent) {
          await createBackup(
            gamePath: gamePath,
            savePath: savePath,
            customName: _preRestorePrefix,
          );
        }
      }

      // 读取并解压 zip
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 解压到存档目录
      for (final file in archive) {
        final filePath = p.join(savePath, file.name);
        if (file.isFile) {
          final parentDir = Directory(p.dirname(filePath));
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          await File(filePath).writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      return true;
    } catch (e) {
      debugPrint('[BackupService] restoreBackup 错误: $e');
      return false;
    }
  }

  /// 删除备份文件
  Future<bool> deleteBackup(String backupFilePath) async {
    try {
      final file = File(backupFilePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BackupService] deleteBackup 错误: $e');
      return false;
    }
  }

  /// 重命名备份文件（同时修改显示名和文件名）
  Future<bool> renameBackup(String oldFilePath, String newName) async {
    try {
      final file = File(oldFilePath);
      if (!await file.exists()) return false;

      final dir = p.dirname(oldFilePath);
      final newFilePath = p.join(dir, '$newName.zip');

      // 检查目标名称是否已存在
      if (await File(newFilePath).exists()) {
        debugPrint('[BackupService] 目标名称已存在: $newFilePath');
        return false;
      }

      await file.rename(newFilePath);
      return true;
    } catch (e) {
      debugPrint('[BackupService] renameBackup 错误: $e');
      return false;
    }
  }

  /// 导入自定义备份（zip 文件或文件夹）
  /// [sourcePath] 源文件/文件夹路径
  /// [targetName] 目标名称（不含 .zip），为空时自动从源路径推导
  /// 成功返回 BackupEntry
  Future<BackupEntry?> importBackup({
    required String gamePath,
    required String sourcePath,
    String? targetName,
  }) async {
    final backupDir = getBackupDir(gamePath);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final sourceEntity = FileSystemEntity.typeSync(sourcePath);

    // 确定目标文件名
    String name;
    if (targetName != null) {
      name = targetName;
    } else if (sourceEntity == FileSystemEntityType.file) {
      // 从 zip 文件名推导（去掉 .zip 后缀）
      name = p.basenameWithoutExtension(sourcePath);
    } else {
      // 从文件夹名推导
      name = p.basename(sourcePath);
    }

    // 处理名称冲突：如果同名文件已存在，添加序号
    String fileName = '$name.zip';
    String targetPath = p.join(backupDir.path, fileName);
    int counter = 1;
    while (await File(targetPath).exists()) {
      counter++;
      fileName = '$name ($counter).zip';
      targetPath = p.join(backupDir.path, fileName);
    }

    if (sourceEntity == FileSystemEntityType.directory) {
      // 将文件夹压缩为 zip
      try {
        final sourceDir = Directory(sourcePath);
        final archive = Archive();

        await _addDirectoryToArchive(archive, sourceDir, '');

        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes == null) return null;

        await File(targetPath).writeAsBytes(zipBytes);

        return BackupEntry(
          name: name,
          fileName: fileName,
          sizeBytes: zipBytes.length,
          date: DateTime.now(),
          source: BackupSource.imported,
          filePath: targetPath,
        );
      } catch (e) {
        debugPrint('[BackupService] importBackup（文件夹）错误: $e');
        return null;
      }
    } else if (sourceEntity == FileSystemEntityType.file) {
      // 验证是否为有效的 zip 文件
      try {
        final bytes = await File(sourcePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        if (archive.isEmpty) {
          debugPrint('[BackupService] 空的 zip 文件');
          return null;
        }

        await File(sourcePath).copy(targetPath);
        final stat = await File(targetPath).stat();

        return BackupEntry(
          name: name,
          fileName: fileName,
          sizeBytes: stat.size,
          date: DateTime.now(),
          source: BackupSource.imported,
          filePath: targetPath,
        );
      } catch (e) {
        debugPrint('[BackupService] importBackup（zip）错误: $e');
        return null;
      }
    }

    return null;
  }

  /// 自动检测并导入游戏目录下的"存档"文件夹
  /// 条件：文件夹存在、包含文件、尚未导入
  /// 自动导入的固定命名为"导入存档"，只允许存在一个
  Future<BackupEntry?> autoImportSaveFolder(String gamePath) async {
    final saveDir = Directory(p.join(gamePath, '存档'));
    if (!await saveDir.exists()) return null;

    // 检查文件夹是否有内容（非空）
    final hasContent = await saveDir.list().any((_) => true);
    if (!hasContent) return null;

    // 检查是否已经导入过（固定文件名为"导入存档.zip"）
    final backupDir = getBackupDir(gamePath);
    final importFile = File(p.join(backupDir.path, '$_autoImportName.zip'));
    if (await importFile.exists()) return null;

    return importBackup(gamePath: gamePath, sourcePath: saveDir.path, targetName: _autoImportName);
  }

  /// 智能还原自定义/导入备份
  /// 通过文件名匹配找到正确的目标位置
  Future<bool> restoreCustomBackup({
    required String gamePath,
    required String backupFilePath,
    required String savePath,
  }) async {
    try {
      final saveDir = Directory(savePath);

      // 如果存档目录存在且有内容，先创建还原前备份
      if (await saveDir.exists()) {
        final hasContent = await saveDir.list().any((_) => true);
        if (hasContent) {
          await createBackup(
            gamePath: gamePath,
            savePath: savePath,
            customName: _preRestorePrefix,
          );
        }
      }

      final bytes = await File(backupFilePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 收集压缩包中的所有文件（排除元数据文件）
      final archiveFiles = <ArchiveFile>[];
      for (final file in archive) {
        if (file.isFile && file.name != _metaFileName) {
          archiveFiles.add(file);
        }
      }

      if (archiveFiles.isEmpty) return false;

      // 策略 1：检查顶层文件是否直接存在于 savePath
      final topLevelFiles = archiveFiles.where((f) => !f.name.contains('/') && !f.name.contains('\\')).toList();
      if (topLevelFiles.isNotEmpty) {
        for (final file in topLevelFiles) {
          if (await File(p.join(savePath, file.name)).exists()) {
            // 直接匹配成功 - 保留结构还原到 savePath
            await _extractArchiveToPath(archiveFiles, savePath);
            return true;
          }
        }
      }

      // 策略 2：递归搜索 savePath 子目录查找匹配文件
      if (await saveDir.exists()) {
        for (final archiveFile in archiveFiles) {
          final archiveFileName = p.basename(archiveFile.name);
          // 在 savePath 中递归搜索此文件
          final match = await _findFileInDirectory(saveDir, archiveFileName);
          if (match != null) {
            // 找到匹配 - 使用其父目录作为目标
            final targetDir = p.dirname(match);
            await _extractArchiveToPath(archiveFiles, targetDir);
            return true;
          }
        }
      }

      // 策略 3：回退 - 直接解压到 savePath
      await _extractArchiveToPath(archiveFiles, savePath);
      return true;
    } catch (e) {
      debugPrint('[BackupService] restoreCustomBackup 错误: $e');
      return false;
    }
  }

  /// 递归搜索目录中的指定文件名
  Future<String?> _findFileInDirectory(Directory dir, String fileName) async {
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && p.basename(entity.path) == fileName) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 将压缩包文件解压到目标路径，保留目录结构
  Future<void> _extractArchiveToPath(List<ArchiveFile> files, String targetPath) async {
    for (final file in files) {
      final filePath = p.join(targetPath, file.name);
      final parentDir = Directory(p.dirname(filePath));
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await File(filePath).writeAsBytes(file.content as List<int>);
    }
  }

  /// 递归将目录内容添加到压缩包
  Future<void> _addDirectoryToArchive(Archive archive, Directory dir, String prefix) async {
    await for (final entity in dir.list()) {
      final name = prefix.isEmpty
          ? p.basename(entity.path)
          : '$prefix${p.separator}${p.basename(entity.path)}';

      if (entity is File) {
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(name.replaceAll('\\', '/'), bytes.length, bytes));
      } else if (entity is Directory) {
        await _addDirectoryToArchive(archive, entity, name);
      }
    }
  }
}
