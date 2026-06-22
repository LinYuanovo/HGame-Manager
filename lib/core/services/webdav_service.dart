import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WebDavFile {
  final String name;
  final int sizeBytes;
  final DateTime? modifiedDate;

  const WebDavFile({
    required this.name,
    required this.sizeBytes,
    this.modifiedDate,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class WebdavService {
  static const String _backupFolder = 'hgame_manager_backups';

  Uri _buildUri(String serverUrl, String path) {
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return Uri.parse('$base/$path');
  }

  Map<String, String> _authHeaders(String username, String password) {
    final basicAuth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    return {'Authorization': basicAuth};
  }

  Future<List<WebDavFile>> listBackups({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final uri = _buildUri(serverUrl, _backupFolder);
      final headers = {
        ..._authHeaders(username, password),
        'Depth': '1',
      };

      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(headers);
      final response = await request.send();

      final statusCode = response.statusCode;
      if (statusCode == 207) {
        final body = await response.stream.bytesToString();
        return _parsePropfindResponse(body);
      } else if (statusCode == 404) {
        await response.stream.drain<void>();
        await _createFolder(serverUrl, username, password);
        return [];
      } else {
        debugPrint('[WebDAV] PROPFIND failed: $statusCode');
        await response.stream.drain<void>();
        return [];
      }
    } catch (e) {
      debugPrint('[WebDAV] listBackups error: $e');
      return [];
    }
  }

  Future<bool> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String localFilePath,
  }) async {
    try {
      final file = File(localFilePath);
      if (!await file.exists()) {
        debugPrint('[WebDAV] Local file not found: $localFilePath');
        return false;
      }

      final fileName = localFilePath.split(Platform.pathSeparator).last;
      final uri = _buildUri(serverUrl, '$_backupFolder/$fileName');
      final bytes = await file.readAsBytes();

      await _createFolder(serverUrl, username, password);

      final response = await http.put(
        uri,
        headers: {
          ..._authHeaders(username, password),
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode == 201 || response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[WebDAV] Backup uploaded: $fileName');
        return true;
      } else {
        debugPrint('[WebDAV] Upload failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] uploadBackup error: $e');
      return false;
    }
  }

  Future<bool> downloadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFileName,
    required String localPath,
  }) async {
    try {
      final uri = _buildUri(serverUrl, '$_backupFolder/$remoteFileName');
      final response = await http.get(
        uri,
        headers: _authHeaders(username, password),
      );

      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[WebDAV] Downloaded: $remoteFileName -> $localPath');
        return true;
      } else {
        debugPrint('[WebDAV] Download failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] downloadBackup error: $e');
      return false;
    }
  }

  Future<bool> deleteBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFileName,
  }) async {
    try {
      final uri = _buildUri(serverUrl, '$_backupFolder/$remoteFileName');
      final response = await http.delete(
        uri,
        headers: _authHeaders(username, password),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[WebDAV] Deleted: $remoteFileName');
        return true;
      } else {
        debugPrint('[WebDAV] Delete failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] deleteBackup error: $e');
      return false;
    }
  }

  /// 将游戏标题转换为安全的文件夹名（替换特殊字符为下划线）
  static String sanitizeGameTitle(String title) {
    return title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// 列出 hgame_manager_backups/ 下的游戏文件夹
  Future<List<String>> listGameFolders({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final uri = _buildUri(serverUrl, _backupFolder);
      final headers = {
        ..._authHeaders(username, password),
        'Depth': '1',
      };

      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(headers);
      final response = await request.send();

      if (response.statusCode == 207) {
        final body = await response.stream.bytesToString();
        return _parseFolderNames(body);
      } else if (response.statusCode == 404) {
        await response.stream.drain<void>();
        await _createFolder(serverUrl, username, password);
        return [];
      } else {
        await response.stream.drain<void>();
        return [];
      }
    } catch (e) {
      debugPrint('[WebDAV] listGameFolders 错误: $e');
      return [];
    }
  }

  /// 列出 WebDAV 上指定游戏文件夹中的备份文件
  Future<List<WebDavFile>> listGameBackups({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
  }) async {
    try {
      final sanitizedFolder = sanitizeGameTitle(gameFolder);
      final uri = _buildUri(serverUrl, '$_backupFolder/$sanitizedFolder');
      final headers = {
        ..._authHeaders(username, password),
        'Depth': '1',
      };

      final request = http.Request('PROPFIND', uri);
      request.headers.addAll(headers);
      final response = await request.send();

      if (response.statusCode == 207) {
        final body = await response.stream.bytesToString();
        return _parsePropfindResponse(body);
      } else if (response.statusCode == 404) {
        await response.stream.drain<void>();
        return [];
      } else {
        await response.stream.drain<void>();
        return [];
      }
    } catch (e) {
      debugPrint('[WebDAV] listGameBackups 错误: $e');
      return [];
    }
  }

  /// 上传备份文件到 WebDAV 上的游戏文件夹
  Future<bool> uploadGameBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
    required String localFilePath,
  }) async {
    try {
      final file = File(localFilePath);
      if (!await file.exists()) {
        debugPrint('[WebDAV] 本地文件不存在: $localFilePath');
        return false;
      }

      final sanitizedFolder = sanitizeGameTitle(gameFolder);
      final fileName = localFilePath.split(Platform.pathSeparator).last;
      final remotePath = '$_backupFolder/$sanitizedFolder/$fileName';

      // 先创建游戏文件夹
      await _createSubFolder(serverUrl, username, password, sanitizedFolder);

      final uri = _buildUri(serverUrl, remotePath);
      final bytes = await file.readAsBytes();

      final response = await http.put(
        uri,
        headers: {
          ..._authHeaders(username, password),
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode == 201 || response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[WebDAV] 游戏备份已上传: $fileName -> $sanitizedFolder');
        return true;
      } else {
        debugPrint('[WebDAV] 上传失败: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] uploadGameBackup 错误: $e');
      return false;
    }
  }

  /// 从 WebDAV 下载游戏备份
  Future<bool> downloadGameBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
    required String remoteFileName,
    required String localPath,
  }) async {
    try {
      final sanitizedFolder = sanitizeGameTitle(gameFolder);
      final uri = _buildUri(serverUrl, '$_backupFolder/$sanitizedFolder/$remoteFileName');
      final response = await http.get(
        uri,
        headers: _authHeaders(username, password),
      );

      if (response.statusCode == 200) {
        final file = File(localPath);
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[WebDAV] 游戏备份已下载: $remoteFileName -> $localPath');
        return true;
      } else {
        debugPrint('[WebDAV] 下载失败: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] downloadGameBackup 错误: $e');
      return false;
    }
  }

  /// 从 WebDAV 删除游戏备份
  Future<bool> deleteGameBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
    required String remoteFileName,
  }) async {
    try {
      final sanitizedFolder = sanitizeGameTitle(gameFolder);
      final uri = _buildUri(serverUrl, '$_backupFolder/$sanitizedFolder/$remoteFileName');
      final response = await http.delete(
        uri,
        headers: _authHeaders(username, password),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[WebDAV] 游戏备份已删除: $remoteFileName');
        return true;
      } else {
        debugPrint('[WebDAV] 删除失败: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[WebDAV] deleteGameBackup 错误: $e');
      return false;
    }
  }

  /// 在 hgame_manager_backups/ 下创建子文件夹
  Future<void> _createSubFolder(String serverUrl, String username, String password, String folderName) async {
    try {
      // 确保父目录存在
      await _createFolder(serverUrl, username, password);

      final uri = _buildUri(serverUrl, '$_backupFolder/$folderName');
      final request = http.Request('MKCOL', uri);
      request.headers.addAll(_authHeaders(username, password));
      final response = await request.send();
      await response.stream.drain<void>();
    } catch (e) {
      debugPrint('[WebDAV] _createSubFolder 错误: $e');
    }
  }

  /// 从 PROPFIND 响应中解析文件夹名（仅目录）
  List<String> _parseFolderNames(String xmlBody) {
    final folders = <String>[];
    try {
      final document = XmlDocument.parse(xmlBody);
      final responses = _findResponseElements(document);

      for (final response in responses) {
        var href = _findChildText(response, ['D:href', 'd:href', 'lp1:href']);
        if (href == null) continue;

        // URL 解码
        href = Uri.decodeComponent(href);

        // 仅目录以 / 结尾
        if (!href.endsWith('/')) continue;

        // 提取文件夹名（倒数第二段）
        final segments = href.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length < 2) continue;

        // 跳过根文件夹本身
        if (segments.last == _backupFolder || segments.last.isEmpty) continue;

        folders.add(segments[segments.length - 2]);
      }
    } catch (e) {
      debugPrint('[WebDAV] _parseFolderNames 错误: $e');
    }
    return folders;
  }

  /// 模糊匹配游戏标题与云端文件夹名
  /// 返回最佳匹配的文件夹名，无匹配返回 null
  static String? fuzzyMatchGameFolder(String gameTitle, List<String> cloudFolders) {
    if (cloudFolders.isEmpty || gameTitle.isEmpty) return null;

    final normalizedTitle = gameTitle.toLowerCase().trim();
    String? bestMatch;
    double bestScore = 0;

    for (final folder in cloudFolders) {
      final normalizedFolder = folder.toLowerCase().trim();
      double score = 0;

      // 完全匹配
      if (normalizedTitle == normalizedFolder) {
        return folder;
      }

      // 标题包含文件夹名 或 文件夹名包含标题
      if (normalizedTitle.contains(normalizedFolder)) {
        score = 0.8 + (normalizedFolder.length / normalizedTitle.length) * 0.2;
      } else if (normalizedFolder.contains(normalizedTitle)) {
        score = 0.7 + (normalizedTitle.length / normalizedFolder.length) * 0.3;
      } else {
        // 基于词元的匹配
        final titleTokens = normalizedTitle.split(RegExp(r'[\s_\-]+'));
        final folderTokens = normalizedFolder.split(RegExp(r'[\s_\-]+'));
        int matchCount = 0;
        for (final token in titleTokens) {
          if (token.length < 2) continue;
          for (final fToken in folderTokens) {
            if (fToken.contains(token) || token.contains(fToken)) {
              matchCount++;
              break;
            }
          }
        }
        final totalTokens = titleTokens.where((t) => t.length >= 2).length;
        if (totalTokens > 0) {
          score = (matchCount / totalTokens) * 0.6;
        }
      }

      if (score > bestScore && score >= 0.5) {
        bestScore = score;
        bestMatch = folder;
      }
    }

    return bestMatch;
  }

  Future<String?> importBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remoteFileName,
    required String localDbPath,
  }) async {
    try {
      final tempPath = '$localDbPath.restored';
      final success = await downloadBackup(
        serverUrl: serverUrl,
        username: username,
        password: password,
        remoteFileName: remoteFileName,
        localPath: tempPath,
      );

      if (success) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          debugPrint('[WebDAV] Downloaded backup to: $tempPath');
          return tempPath;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[WebDAV] importBackup error: $e');
      return null;
    }
  }

  Future<void> _createFolder(String serverUrl, String username, String password) async {
    try {
      final uri = _buildUri(serverUrl, _backupFolder);
      final request = http.Request('MKCOL', uri);
      request.headers.addAll(_authHeaders(username, password));
      final response = await request.send();
      await response.stream.drain<void>();
      debugPrint('[WebDAV] MKCOL status: ${response.statusCode}');
    } catch (e) {
      debugPrint('[WebDAV] _createFolder error: $e');
    }
  }

  List<WebDavFile> _parsePropfindResponse(String xmlBody) {
    final files = <WebDavFile>[];
    try {
      final document = XmlDocument.parse(xmlBody);
      final responses = _findResponseElements(document);

      for (final response in responses) {
        var href = _findChildText(response, ['D:href', 'd:href', 'lp1:href']);
        if (href == null) continue;

        // URL 解码（处理 %20 等编码字符）
        href = Uri.decodeComponent(href);

        // 跳过目录（以 / 结尾）
        if (href.endsWith('/')) continue;

        final name = href.split('/').last;
        if (name.isEmpty) continue;

        final propstat = _findChild(response, ['D:propstat', 'd:propstat', 'lp1:propstat']);
        if (propstat == null) continue;

        final status = _findChildText(propstat, ['D:status', 'd:status', 'lp1:status']) ?? '';
        if (!status.contains('200')) continue;

        final prop = _findChild(propstat, ['D:prop', 'd:prop', 'lp1:prop']);
        if (prop == null) continue;

        final sizeStr = _findChildText(prop, ['D:getcontentlength', 'd:getcontentlength', 'lp1:getcontentlength']);
        final dateStr = _findChildText(prop, ['D:getlastmodified', 'd:getlastmodified', 'lp1:getlastmodified']);

        final size = int.tryParse(sizeStr ?? '0') ?? 0;
        DateTime? date;
        if (dateStr != null) {
          date = DateTime.tryParse(dateStr);
        }
        if (date == null) {
          date = _parseDateFromFileName(name);
        }

        files.add(WebDavFile(
          name: name,
          sizeBytes: size,
          modifiedDate: date,
        ));
      }
    } catch (e) {
      debugPrint('[WebDAV] XML parse error: $e');
    }

    files.sort((a, b) {
      final da = a.modifiedDate ?? DateTime(2000);
      final db = b.modifiedDate ?? DateTime(2000);
      return db.compareTo(da);
    });

    return files;
  }

  List<XmlElement> _findResponseElements(XmlNode root) {
    final result = <XmlElement>[];
    for (final node in root.descendants) {
      if (node is XmlElement) {
        final localName = node.name.toString().split(':').last;
        if (localName == 'response') {
          result.add(node);
        }
      }
    }
    return result;
  }

  XmlElement? _findChild(XmlElement parent, List<String> candidates) {
    for (final child in parent.children) {
      if (child is XmlElement && candidates.contains(child.name.toString())) {
        return child;
      }
    }
    return null;
  }

  String? _findChildText(XmlElement parent, List<String> candidates) {
    for (final child in parent.children) {
      if (child is XmlElement && candidates.contains(child.name.toString())) {
        return child.innerText;
      }
    }
    return null;
  }

  static DateTime? _parseDateFromFileName(String name) {
    final newMatch = RegExp(r'hgame_manager_(\d{14})\.zip').firstMatch(name);
    if (newMatch != null) {
      final s = newMatch.group(1)!;
      return DateTime.tryParse('${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)} ${s.substring(8, 10)}:${s.substring(10, 12)}:${s.substring(12, 14)}');
    }
    final oldMatch = RegExp(r'hgame_manager_(\d{13,})\.db').firstMatch(name);
    if (oldMatch != null) {
      final ms = int.tryParse(oldMatch.group(1)!);
      if (ms != null) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return null;
  }
}
