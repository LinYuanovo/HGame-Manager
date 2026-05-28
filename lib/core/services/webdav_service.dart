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
      if (!file.existsSync()) {
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
        if (tempFile.existsSync()) {
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
        final href = _findChildText(response, ['D:href', 'd:href', 'lp1:href']);
        if (href == null || href.endsWith('/')) continue;

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
