import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as path;

import '../utils/app_version.dart';

class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._();

  final Queue<String> _pending = Queue<String>();
  final String _session = '${DateTime.now().millisecondsSinceEpoch}-$pid';
  Future<void>? _initializing;
  Future<void>? _flushing;
  Timer? _flushTimer;
  File? _logFile;
  String? _logDir;
  String _date = '';
  String _filePrefix = 'app';
  int _pendingCharacters = 0;
  int _dropped = 0;
  int _fileBytes = 0;

  static const int _retainDays = 3;
  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxPendingCharacters = 256 * 1024;
  static final RegExp _urls = RegExp(r'''https?://[^\s<>"']+''');
  static final RegExp _headers = RegExp(
    r'''(["']?(?:authorization|proxy-authorization|cookie|set-cookie)["']?)\s*[:=][^\r\n]*''',
    caseSensitive: false,
  );
  static final RegExp _credentials = RegExp(
    r'''(["']?(?:password|passwd|token|access_token|refresh_token|api[_-]?key|secret|x-device-code|x-client-code)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;]+)''',
    caseSensitive: false,
  );
  static final RegExp _bearer =
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);
  static final RegExp _jwt =
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');

  String? get logDir => _logDir;

  static String sanitize(String message) {
    var result = message.replaceAllMapped(_urls, (match) {
      final uri = Uri.tryParse(match[0]!);
      if (uri == null || uri.host.isEmpty) return '[无效网址]';
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    });
    result = result.replaceAllMapped(_headers, (match) => '${match[1]}=[已隐藏]');
    result =
        result.replaceAllMapped(_credentials, (match) => '${match[1]}[已隐藏]');
    result = result.replaceAllMapped(_bearer, (match) => '${match[1]} [已隐藏]');
    result = result.replaceAll(_jwt, '[已隐藏]');
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      result = result.replaceAll(
          RegExp(RegExp.escape(profile), caseSensitive: false),
          '%USERPROFILE%');
    }
    return result;
  }

  Future<void> init({String? directory, String channel = 'app'}) {
    if (_initializing != null) return _initializing!;
    _filePrefix = channel.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return _initializing = _initialize(directory);
  }

  Future<void> _initialize(String? directory) async {
    final candidates = [
      directory ?? path.join(path.dirname(Platform.resolvedExecutable), 'logs'),
      if (directory == null && Platform.environment['LOCALAPPDATA'] != null)
        path.join(
            Platform.environment['LOCALAPPDATA']!, 'HGame-Manager', 'logs'),
    ];
    for (final candidate in candidates) {
      try {
        await Directory(candidate).create(recursive: true);
        _logDir = candidate;
        await _openDailyFile();
        info('AppLogger',
            '启动会话: version=$appVersion, os=${Platform.operatingSystemVersion}, locale=${Platform.localeName}, processors=${Platform.numberOfProcessors}, logs=$candidate');
        await flush();
        await _cleanOldLogs();
        return;
      } catch (error) {
        _logFile = null;
        _logDir = null;
        debugPrint('[AppLogger] 初始化失败: ${sanitize(error.toString())}');
      }
    }
  }

  Future<void> _openDailyFile() async {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    if (_date == date && _logFile != null) return;
    final file = File(path.join(_logDir!, '${_filePrefix}_$date.log'));
    final handle = await file.open(mode: FileMode.append);
    _fileBytes = await handle.length();
    await handle.close();
    _logFile = file;
    _date = date;
  }

  void _write(String tag, String level, String message) {
    final safe = sanitize(message);
    final bounded =
        safe.length > 16384 ? '${safe.substring(0, 16384)}…[已截断]' : safe;
    final line =
        '[${DateTime.now().toIso8601String()}] [$level] [$tag] [$_session] $bounded\n';
    if (kDebugMode) debugPrint(line.trimRight());
    while (_pending.isNotEmpty &&
        _pendingCharacters + line.length > _maxPendingCharacters) {
      _pendingCharacters -= _pending.removeFirst().length;
      _dropped++;
    }
    _pending.add(line);
    _pendingCharacters += line.length;
    if (_logDir != null) {
      _flushTimer ??=
          Timer(const Duration(milliseconds: 250), () => unawaited(flush()));
    }
  }

  void info(String tag, String message) => _write(tag, 'INFO', message);
  void warning(String tag, String message) => _write(tag, 'WARN', message);
  void error(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _write(tag, 'ERROR',
        '$message${error == null ? '' : '\n$error'}${stackTrace == null ? '' : '\n$stackTrace'}');
    if (_logDir != null) unawaited(flush());
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    return _flushing ??= _drain().whenComplete(() => _flushing = null);
  }

  Future<void> _drain() async {
    if (_logDir == null) return;
    while (_pending.isNotEmpty) {
      final text = StringBuffer();
      if (_dropped > 0) {
        text.writeln('[WARN] [AppLogger] 写入队列达到上限，丢弃 $_dropped 条日志');
        _dropped = 0;
      }
      while (_pending.isNotEmpty) {
        text.write(_pending.removeFirst());
      }
      _pendingCharacters = 0;
      try {
        await _openDailyFile();
        if (_fileBytes >= _maxFileBytes) {
          final oldest = File('${_logFile!.path}.2');
          if (await oldest.exists()) await oldest.delete();
          final previous = File('${_logFile!.path}.1');
          if (await previous.exists()) await previous.rename(oldest.path);
          await _logFile!.rename(previous.path);
          _fileBytes = 0;
        }
        await _logFile!
            .writeAsString(text.toString(), mode: FileMode.append, flush: true);
        _fileBytes = await _logFile!.length();
      } catch (error) {
        debugPrint('[AppLogger] 写入失败: ${sanitize(error.toString())}');
      }
    }
  }

  Future<void> _cleanOldLogs() async {
    final cutoff = DateTime.now().subtract(const Duration(days: _retainDays));
    try {
      await for (final entry in Directory(_logDir!).list(followLinks: false)) {
        if (entry is! File ||
            !RegExp(r'^(?:app|guide_[a-zA-Z0-9_-]+)_\d{8}\.log(?:\.[12])?$')
                .hasMatch(path.basename(entry.path))) {
          continue;
        }
        try {
          if ((await entry.stat()).modified.isBefore(cutoff)) {
            await entry.delete();
          }
        } catch (error) {
          warning('AppLogger', '过期日志清理失败: $error');
        }
      }
    } catch (error) {
      warning('AppLogger', '日志目录读取失败: $error');
    }
  }

  Future<void> exportDiagnostics(String destination) async {
    await init();
    await flush();
    final directory = _logDir;
    if (directory == null) throw StateError('日志目录不可用');
    final candidates = <File>[];
    await for (final entry in Directory(directory).list(followLinks: false)) {
      if (entry is File &&
          RegExp(r'^(?:app|guide_[a-zA-Z0-9_-]+)_\d{8}\.log(?:\.[12])?$')
              .hasMatch(path.basename(entry.path))) {
        candidates.add(entry);
      }
    }
    final modifiedTimes = <String, DateTime>{};
    for (final file in candidates) {
      modifiedTimes[file.path] = await file.lastModified();
    }
    candidates.sort((left, right) =>
        modifiedTimes[right.path]!.compareTo(modifiedTimes[left.path]!));
    final paths = candidates.take(9).map((file) => file.path).toList();
    final version = appVersion;
    await Isolate.run(() async {
      final archive = Archive();
      final summary = utf8.encode(
          '版本: $version\n系统: ${Platform.operatingSystemVersion}\n日志已过滤凭据及网址查询参数；本地游戏路径可能仍包含个人信息。\n');
      archive.addFile(ArchiveFile('说明.txt', summary.length, summary));
      for (final filePath in paths) {
        final handle = await File(filePath).open();
        late List<int> bytes;
        try {
          final length = await handle.length();
          if (length > _maxFileBytes) {
            await handle.setPosition(length - _maxFileBytes);
          }
          bytes = await handle.read(_maxFileBytes);
        } finally {
          await handle.close();
        }
        final content =
            utf8.encode(sanitize(utf8.decode(bytes, allowMalformed: true)));
        archive.addFile(
            ArchiveFile(path.basename(filePath), content.length, content));
      }
      await File(destination)
          .writeAsBytes(ZipEncoder().encode(archive), flush: true);
    });
    info('AppLogger', '诊断包导出完成: files=${paths.length}');
  }
}
