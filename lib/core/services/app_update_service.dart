import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../utils/changelog_parser.dart';
import '../utils/proxy_client.dart';
import '../utils/version_utils.dart';

const String appChangelogUrl =
    'https://raw.githubusercontent.com/LinYuanovo/HGame-Manager/refs/heads/master/CHANGELOG.md';
const String appQuarkUrl =
    'https://pan.quark.cn/s/3247b400db81#/list/share/08dfb3dc2604481f8e08d7ca843ab32e';

enum AppUpdateStatus {
  updateAvailable,
  upToDate,
  unavailable,
}

enum AppUpdateFrequency {
  startup('每次启动'),
  daily('每天'),
  weekly('每周'),
  monthly('每月');

  final String label;

  const AppUpdateFrequency(this.label);

  static AppUpdateFrequency fromName(String? name) {
    return AppUpdateFrequency.values.firstWhere(
      (frequency) => frequency.name == name,
      orElse: () => AppUpdateFrequency.startup,
    );
  }
}

class AppUpdateCheckResult {
  final AppUpdateStatus status;
  final String currentVersion;
  final ChangelogEntry? latestEntry;
  final List<ChangelogEntry> updateEntries;
  final String? errorMessage;

  const AppUpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.latestEntry,
    this.updateEntries = const [],
    this.errorMessage,
  });
}

/// 下载进度（totalBytes 为 null 时表示总大小未知）。
class AppUpdateDownloadProgress {
  final int receivedBytes;
  final int? totalBytes;

  const AppUpdateDownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
  });

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return receivedBytes / total;
  }
}

/// 更新包完整性校验失败（大小不符、解压失败、CRC 不匹配）。
class AppUpdateIntegrityException implements Exception {
  final String message;

  const AppUpdateIntegrityException(this.message);

  @override
  String toString() => message;
}

/// 上次未完成的安装（下载解压成功但未覆盖成功）。
class PendingAppUpdate {
  final String version;
  final String cacheDirPath;

  const PendingAppUpdate({
    required this.version,
    required this.cacheDirPath,
  });
}

class AppUpdateService {
  final http.Client? _httpClient;

  AppUpdateService({http.Client? httpClient}) : _httpClient = httpClient;

  Future<AppUpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async {
    final client = _httpClient ??
        await createProxyClientFromPrefs(domain: 'raw.githubusercontent.com');
    try {
      final response = await client
          .get(Uri.parse(appChangelogUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return AppUpdateCheckResult(
          status: AppUpdateStatus.unavailable,
          currentVersion: currentVersion,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }

      final entries = parseChangelogEntries(response.body);
      if (entries.isEmpty) {
        return AppUpdateCheckResult(
          status: AppUpdateStatus.unavailable,
          currentVersion: currentVersion,
          errorMessage: 'CHANGELOG 中未找到版本信息',
        );
      }

      var latestEntry = entries.first;
      for (final entry in entries.skip(1)) {
        if (compareVersions(entry.version, latestEntry.version) > 0) {
          latestEntry = entry;
        }
      }
      final updateEntries = entries
          .where((entry) => compareVersions(entry.version, currentVersion) > 0)
          .toList()
        ..sort(
          (left, right) => compareVersions(right.version, left.version),
        );

      return AppUpdateCheckResult(
        status: compareVersions(latestEntry.version, currentVersion) > 0
            ? AppUpdateStatus.updateAvailable
            : AppUpdateStatus.upToDate,
        currentVersion: currentVersion,
        latestEntry: latestEntry,
        updateEntries: updateEntries,
      );
    } catch (e) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        currentVersion: currentVersion,
        errorMessage: e.toString(),
      );
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  static Uri buildReleaseDownloadUri(String version) {
    return Uri.parse(
      'https://github.com/LinYuanovo/HGame-Manager/releases/download/'
      'v$version/HGame-Manager-v$version-windows.zip',
    );
  }

  static bool shouldCheck({
    required bool enabled,
    required AppUpdateFrequency frequency,
    required DateTime? lastChecked,
    DateTime? now,
  }) {
    if (!enabled) return false;
    if (frequency == AppUpdateFrequency.startup || lastChecked == null) {
      return true;
    }

    final elapsed = (now ?? DateTime.now()).difference(lastChecked);
    final threshold = switch (frequency) {
      AppUpdateFrequency.startup => Duration.zero,
      AppUpdateFrequency.daily => const Duration(days: 1),
      AppUpdateFrequency.weekly => const Duration(days: 7),
      AppUpdateFrequency.monthly => const Duration(days: 30),
    };
    return elapsed >= threshold;
  }

  Future<void> downloadAndInstall({
    required String version,
    required String executablePath,
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('应用更新仅支持 Windows');
    }

    final client =
        _httpClient ?? await createProxyClientFromPrefs(domain: 'github.com');
    try {
      final cacheDir = await _prepareCacheDir(version);
      var sourceDir = await _findReusableSource(cacheDir, executablePath);
      sourceDir ??= await _downloadAndExtractWithRetry(
        client: client,
        version: version,
        cacheDir: cacheDir,
        executablePath: executablePath,
        onProgress: onProgress,
      );

      await _writeInstallerScripts(
        cacheDir: cacheDir,
        sourceDir: sourceDir,
        executablePath: executablePath,
      );
      final cmdPath = path.join(
        Platform.environment['WINDIR'] ?? r'C:\Windows',
        'System32',
        'cmd.exe',
      );
      await Process.start(
        cmdPath,
        ['/d', '/c', path.join(cacheDir.path, 'update_bootstrap.cmd')],
        mode: ProcessStartMode.detached,
      );
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  static Future<Directory> _findReleaseRoot(Directory extractedDir) async {
    final rootExecutable = File(
      path.join(extractedDir.path, 'hgame_manager.exe'),
    );
    if (await rootExecutable.exists()) return extractedDir;

    await for (final entity in extractedDir.list(recursive: true)) {
      if (entity is File &&
          path.basename(entity.path).toLowerCase() == 'hgame_manager.exe') {
        return entity.parent;
      }
    }
    throw const FormatException('更新压缩包目录结构无效');
  }

  /// 检测上次未完成的安装，并顺带清理缓存目录：
  /// - install.result 为 success：安装已成功，删除缓存
  /// - 版本不高于当前版本：已无价值，删除
  /// - 多个待安装版本：只保留最新一个
  static Future<PendingAppUpdate?> findPendingInstall({
    required String currentVersion,
  }) async {
    if (!Platform.isWindows) return null;
    final root = Directory(
      path.join(Directory.systemTemp.path, 'hgame_update'),
    );
    if (!await root.exists()) return null;

    PendingAppUpdate? best;
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final name = path.basename(entity.path);
      if (!name.startsWith('v')) continue;
      final version = name.substring(1);
      try {
        final resultFile = File(path.join(entity.path, 'install.result'));
        if (await resultFile.exists()) {
          final result = (await resultFile.readAsString()).trim();
          if (result.startsWith('success')) {
            await entity.delete(recursive: true);
            continue;
          }
        }
        if (compareVersions(version, currentVersion) <= 0) {
          await entity.delete(recursive: true);
          continue;
        }
        final marker = File(path.join(entity.path, '.extracted_ok'));
        if (!await marker.exists()) {
          // 只有部分下载，保留供断点续传
          continue;
        }
        if (best == null || compareVersions(version, best.version) > 0) {
          final previous = best;
          best = PendingAppUpdate(
            version: version,
            cacheDirPath: entity.path,
          );
          if (previous != null) {
            await Directory(previous.cacheDirPath).delete(recursive: true);
          }
        } else {
          await entity.delete(recursive: true);
        }
      } catch (_) {
        // 单个缓存目录读取/清理失败不影响整体检测
      }
    }
    return best;
  }

  static Future<void> discardPendingInstall(PendingAppUpdate pending) async {
    try {
      await Directory(pending.cacheDirPath).delete(recursive: true);
    } catch (_) {}
  }

  static Future<Directory> _prepareCacheDir(String version) async {
    final dir = Directory(
      path.join(Directory.systemTemp.path, 'hgame_update', 'v$version'),
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// 缓存命中条件：.extracted_ok 标记存在且解压目录中能找到目标 exe。
  static Future<Directory?> _findReusableSource(
    Directory cacheDir,
    String executablePath,
  ) async {
    final marker = File(path.join(cacheDir.path, '.extracted_ok'));
    if (!await marker.exists()) return null;
    try {
      final root = await _findReleaseRoot(
        Directory(path.join(cacheDir.path, 'extracted')),
      );
      final executable = File(
        path.join(root.path, path.basename(executablePath)),
      );
      if (await executable.exists()) return root;
    } catch (_) {}
    return null;
  }

  /// 下载并解压，完整性失败（大小不符/解压失败/CRC 不匹配）时
  /// 清空缓存自动重试一次；网络错误不重试，保留部分文件供断点续传。
  Future<Directory> _downloadAndExtractWithRetry({
    required http.Client client,
    required String version,
    required Directory cacheDir,
    required String executablePath,
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        try {
          await cacheDir.delete(recursive: true);
        } catch (_) {}
        await cacheDir.create(recursive: true);
      }
      try {
        await _downloadZip(
          client,
          version,
          File(path.join(cacheDir.path, 'update.zip')),
          onProgress,
        );
        final extractedDir = Directory(path.join(cacheDir.path, 'extracted'));
        if (await extractedDir.exists()) {
          await extractedDir.delete(recursive: true);
        }
        await extractedDir.create(recursive: true);
        final sourceDir = await _extractAndVerify(
          cacheDir,
          extractedDir,
          executablePath,
        );
        await File(path.join(cacheDir.path, '.extracted_ok')).create();
        return sourceDir;
      } on AppUpdateIntegrityException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const AppUpdateIntegrityException('更新包校验失败');
  }

  static Future<Directory> _extractAndVerify(
    Directory cacheDir,
    Directory extractedDir,
    String executablePath,
  ) async {
    try {
      await extractAndVerifyZip(
        File(path.join(cacheDir.path, 'update.zip')),
        extractedDir,
      );
      final sourceDir = await _findReleaseRoot(extractedDir);
      final executable = File(
        path.join(sourceDir.path, path.basename(executablePath)),
      );
      if (!await executable.exists()) {
        throw const FormatException('更新压缩包中未找到应用程序文件');
      }
      return sourceDir;
    } on AppUpdateIntegrityException {
      rethrow;
    } catch (e) {
      throw AppUpdateIntegrityException('更新包校验失败: $e');
    }
  }

  /// 分段并行下载的分片数（GitHub 资产后端支持 Range，多连接可显著提速）
  static const int _parallelDownloadParts = 8;

  static Future<http.StreamedResponse> _sendDownloadRequest(
    http.Client client,
    Uri uri, {
    int? rangeStart,
    int? rangeEnd,
  }) {
    final request = http.Request('GET', uri);
    if (rangeStart != null) {
      request.headers['Range'] =
          'bytes=$rangeStart-${rangeEnd != null ? '$rangeEnd' : ''}';
    }
    return client.send(request).timeout(const Duration(minutes: 5));
  }

  /// 下载更新包。旧版单流部分文件继续单流续传（不浪费已下载内容）；
  /// 否则先探测 Range 支持：支持则分段并行下载（分片各自断点续传，
  /// 完成后合并校验），探测失败或服务器不支持时回退单流。
  Future<void> _downloadZip(
    http.Client client,
    String version,
    File zipFile,
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  ) async {
    final uri = buildReleaseDownloadUri(version);
    final existingLength = await zipFile.exists() ? await zipFile.length() : 0;
    if (existingLength > 0) {
      return _downloadZipSingle(client, uri, zipFile, existingLength,
          onProgress);
    }

    int? total;
    try {
      final probe =
          await _sendDownloadRequest(client, uri, rangeStart: 0, rangeEnd: 0);
      await probe.stream.drain<void>();
      if (probe.statusCode == 206) {
        total = int.tryParse(
            probe.headers['content-range']?.split('/').last ?? '');
      }
    } catch (_) {
      total = null;
    }

    if (total == null || total <= 0) {
      return _downloadZipSingle(client, uri, zipFile, 0, onProgress);
    }
    return _downloadZipParallel(client, uri, zipFile, total, onProgress);
  }

  /// 单流下载/断点续传：已有部分文件时发送 Range 头，206 追加写入，200 从头下载。
  Future<void> _downloadZipSingle(
    http.Client client,
    Uri uri,
    File zipFile,
    int existingLength,
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  ) async {
    final response = await _sendDownloadRequest(
      client,
      uri,
      rangeStart: existingLength > 0 ? existingLength : null,
    );

    var received = existingLength;
    int? total;
    IOSink sink;
    if (response.statusCode == 206) {
      sink = zipFile.openWrite(mode: FileMode.append);
      final contentLength = response.contentLength;
      final remaining =
          contentLength == null || contentLength < 0 ? null : contentLength;
      total = remaining == null ? null : existingLength + remaining;
    } else if (response.statusCode == 200) {
      sink = zipFile.openWrite();
      received = 0;
      final contentLength = response.contentLength;
      total = contentLength == null || contentLength < 0 ? null : contentLength;
    } else {
      throw HttpException('下载更新失败: HTTP ${response.statusCode}');
    }

    try {
      await for (final chunk
          in response.stream.timeout(const Duration(minutes: 2))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          AppUpdateDownloadProgress(receivedBytes: received, totalBytes: total),
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (total != null && received != total) {
      throw const AppUpdateIntegrityException('下载文件大小不符');
    }
  }

  /// 分段并行下载：各分片独立 Range 请求并支持按分片断点续传，
  /// 全部完成后按序合并并校验总大小，最后清理分片。
  Future<void> _downloadZipParallel(
    http.Client client,
    Uri uri,
    File zipFile,
    int total,
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  ) async {
    const parts = _parallelDownloadParts;
    final base = total ~/ parts;
    final partFiles =
        List.generate(parts, (i) => File('${zipFile.path}.part$i'));
    final received = List<int>.filled(parts, 0);

    Future<void> downloadPart(int i) async {
      final start = i * base;
      final end = i == parts - 1 ? total - 1 : (i + 1) * base - 1;
      final expected = end - start + 1;
      final partFile = partFiles[i];
      var done = await partFile.exists() ? await partFile.length() : 0;
      if (done > expected) {
        await partFile.delete();
        done = 0;
      }
      received[i] = done;
      if (done == expected) return;

      final response = await _sendDownloadRequest(
        client,
        uri,
        rangeStart: start + done,
        rangeEnd: end,
      );
      if (response.statusCode != 206) {
        throw HttpException('分段下载更新失败: HTTP ${response.statusCode}');
      }
      final sink = partFile.openWrite(mode: FileMode.append);
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(minutes: 2))) {
          sink.add(chunk);
          received[i] += chunk.length;
          onProgress?.call(
            AppUpdateDownloadProgress(
              receivedBytes: received.fold<int>(0, (a, b) => a + b),
              totalBytes: total,
            ),
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received[i] != expected) {
        throw const AppUpdateIntegrityException('分段下载大小不符');
      }
    }

    // 网络错误保留分片供下次续传；完整性错误由上层清空缓存重试
    await Future.wait(List.generate(parts, downloadPart));

    final sink = zipFile.openWrite();
    try {
      for (final partFile in partFiles) {
        await sink.addStream(partFile.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await zipFile.length() != total) {
      throw const AppUpdateIntegrityException('下载文件大小不符');
    }
    for (final partFile in partFiles) {
      try {
        await partFile.delete();
      } catch (_) {}
    }
  }

  /// 解压 zip 并逐文件做 CRC32 校验（archive 4.x 内置 verify 已失效，
  /// 这里手动比对解压内容与中央目录记录的 CRC）。
  static Future<void> extractAndVerifyZip(
    File zipFile,
    Directory destination,
  ) async {
    final input = InputFileStream(zipFile.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final destinationPath = path.normalize(destination.path);

      for (final file in archive.files) {
        final relativePath = path.normalize(file.name.replaceAll('\\', '/'));
        if (path.isAbsolute(relativePath) ||
            relativePath == '..' ||
            relativePath.startsWith('..${path.separator}')) {
          throw const FormatException('更新压缩包包含非法路径');
        }
        final targetPath = path.normalize(
          path.join(destinationPath, relativePath),
        );
        if (targetPath != destinationPath &&
            !targetPath.startsWith('$destinationPath${path.separator}')) {
          throw const FormatException('更新压缩包包含非法路径');
        }
        if (!file.isFile) continue;

        final content = file.content as List<int>;
        final expectedCrc = file.crc32;
        if (expectedCrc != null &&
            (getCrc32(content) & 0xFFFFFFFF) != (expectedCrc & 0xFFFFFFFF)) {
          throw AppUpdateIntegrityException('更新包校验失败: ${file.name}');
        }

        final target = File(targetPath);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(content, flush: true);
      }
    } finally {
      await input.close();
    }
  }

  static Future<void> _writeInstallerScripts({
    required Directory cacheDir,
    required Directory sourceDir,
    required String executablePath,
  }) async {
    final targetDir = File(executablePath).parent.path;

    // PowerShell 5.1 按 BOM 识别 UTF-8，必须带 BOM 写入，否则中文路径乱码
    final ps1File = File(path.join(cacheDir.path, 'update.ps1'));
    await ps1File.writeAsBytes([
      0xEF, 0xBB, 0xBF,
      ...utf8.encode(
        _buildPowerShellScript(
          processId: pid,
          sourceDir: sourceDir.path,
          targetDir: targetDir,
          executablePath: executablePath,
          tempDir: cacheDir.path,
        ),
      ),
    ]);

    final fallbackFile = File(path.join(cacheDir.path, 'update_fallback.cmd'));
    await fallbackFile.writeAsString(
      _buildFallbackCmdScript(
        processId: pid,
        sourceDir: sourceDir.path,
        targetDir: targetDir,
        executablePath: executablePath,
        tempDir: cacheDir.path,
      ),
    );

    final bootstrapFile =
        File(path.join(cacheDir.path, 'update_bootstrap.cmd'));
    await bootstrapFile.writeAsString(
      _buildBootstrapCmdScript(tempDir: cacheDir.path),
    );
  }

  static String _buildPowerShellScript({
    required int processId,
    required String sourceDir,
    required String targetDir,
    required String executablePath,
    required String tempDir,
  }) {
    const script = r'''
$ErrorActionPreference = 'Stop'
$ProcessId = __PROCESS_ID__
$SourceDir = '__SOURCE_DIR__'
$TargetDir = '__TARGET_DIR__'
$ExecutablePath = '__EXECUTABLE_PATH__'
$TempDir = '__TEMP_DIR__'
$LogFile = Join-Path $TempDir 'update.log'
$ResultFile = Join-Path $TempDir 'install.result'

function Write-Log([string]$msg) {
  $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $msg
  Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

try {
  Write-Log 'Updater started (PowerShell)'
  $old = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if ($old) {
    $oldPath = $null
    try { $oldPath = $old.Path } catch {}
    if ($oldPath -and ($oldPath -ine $ExecutablePath)) {
      Write-Log "PID $ProcessId path mismatch: $oldPath, treated as exited"
    } else {
      Write-Log "Found old process PID=$ProcessId Name=$($old.ProcessName)"
      try { $old.CloseMainWindow() | Out-Null } catch {}
      if (-not $old.WaitForExit(10000)) {
        Write-Log "Graceful close timed out, killing PID=$ProcessId"
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
      }
      $deadline = (Get-Date).AddSeconds(60)
      while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        if ((Get-Date) -gt $deadline) {
          throw "PID $ProcessId still alive after kill"
        }
        Start-Sleep -Milliseconds 500
      }
      Write-Log 'Old process exited'
    }
  } else {
    Write-Log 'Old process not found'
  }

  $excludeDir = Join-Path $SourceDir 'hgame_manager_data'
  robocopy $SourceDir $TargetDir /E /COPY:DAT /DCOPY:DAT /R:3 /W:1 /XD $excludeDir *>&1 | Out-File -LiteralPath $LogFile -Append -Encoding UTF8
  if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed, exit code $LASTEXITCODE"
  }
  if (-not (Test-Path -LiteralPath $ExecutablePath)) {
    throw "New executable missing: $ExecutablePath"
  }
  Write-Log 'Files copied'

  Set-Content -LiteralPath $ResultFile -Value 'success' -Encoding ASCII
  Start-Process -FilePath $ExecutablePath -WorkingDirectory $TargetDir
  Write-Log 'New process started'
  exit 0
} catch {
  Write-Log "Update failed: $($_.Exception.Message)"
  Set-Content -LiteralPath $ResultFile -Value "failed: $($_.Exception.Message)" -Encoding UTF8
  exit 1
}
''';
    return script
        .trim()
        .replaceAll('__PROCESS_ID__', '$processId')
        .replaceAll('__SOURCE_DIR__', _escapePsValue(sourceDir))
        .replaceAll('__TARGET_DIR__', _escapePsValue(targetDir))
        .replaceAll('__EXECUTABLE_PATH__', _escapePsValue(executablePath))
        .replaceAll('__TEMP_DIR__', _escapePsValue(tempDir))
        .replaceAll('\n', '\r\n');
  }

  /// CMD 兜底脚本：tasklist 管道直接判断进程，去掉 PROCESS_FILE 临时文件，
  /// 消除重定向失败导致误判"进程已退出"的根因。
  static String _buildFallbackCmdScript({
    required int processId,
    required String sourceDir,
    required String targetDir,
    required String executablePath,
    required String tempDir,
  }) {
    const script = r'''
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PROCESS_ID=__PROCESS_ID__"
set "SOURCE_DIR=__SOURCE_DIR__"
set "TARGET_DIR=__TARGET_DIR__"
set "EXECUTABLE_PATH=__EXECUTABLE_PATH__"
set "TEMP_DIR=__TEMP_DIR__"
set "LOG_FILE=%TEMP_DIR%\update.log"
set "RESULT_FILE=%TEMP_DIR%\install.result"
call :log Updater started (CMD fallback)
set /a WAIT_COUNT=0
:wait_for_process
tasklist /FI "PID eq %PROCESS_ID%" /FO CSV /NH 2>nul | find "%PROCESS_ID%" >nul
if errorlevel 1 goto process_exited
set /a WAIT_COUNT+=1
if %WAIT_COUNT% GEQ 120 goto wait_timeout
timeout /t 1 /nobreak >nul
goto wait_for_process
:process_exited
call :log Old process exited
robocopy "%SOURCE_DIR%" "%TARGET_DIR%" /E /COPY:DAT /DCOPY:DAT /R:3 /W:1 /XD "%SOURCE_DIR%\hgame_manager_data" >> "%LOG_FILE%" 2>&1
if errorlevel 8 goto copy_failed
if not exist "%EXECUTABLE_PATH%" goto executable_missing
call :log Files copied
echo success> "%RESULT_FILE%"
start "" /D "%TARGET_DIR%" "%EXECUTABLE_PATH%"
call :log New process started
exit /b 0
:wait_timeout
call :log Waiting for old process timed out
echo failed: waiting for old process timed out> "%RESULT_FILE%"
exit /b 1
:copy_failed
call :log File copy failed
echo failed: file copy failed> "%RESULT_FILE%"
exit /b 1
:executable_missing
call :log New executable is missing
echo failed: new executable is missing> "%RESULT_FILE%"
exit /b 1
:log
>> "%LOG_FILE%" echo [%date% %time%] %*
exit /b 0
''';
    return script
        .trim()
        .replaceAll('__PROCESS_ID__', '$processId')
        .replaceAll('__SOURCE_DIR__', _escapeCmdValue(sourceDir))
        .replaceAll('__TARGET_DIR__', _escapeCmdValue(targetDir))
        .replaceAll('__EXECUTABLE_PATH__', _escapeCmdValue(executablePath))
        .replaceAll('__TEMP_DIR__', _escapeCmdValue(tempDir))
        .replaceAll('\n', '\r\n');
  }

  /// 启动器：优先 PowerShell，不可用或执行失败（退出码非 0）时回退 CMD。
  static String _buildBootstrapCmdScript({required String tempDir}) {
    const script = r'''
@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "TEMP_DIR=__TEMP_DIR__"
set "LOG_FILE=%TEMP_DIR%\update.log"
where powershell >nul 2>&1
if errorlevel 1 goto cmd_fallback
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP_DIR%\update.ps1"
if not errorlevel 1 exit /b 0
>> "%LOG_FILE%" echo [%date% %time%] PowerShell updater failed, falling back to CMD
:cmd_fallback
call "%TEMP_DIR%\update_fallback.cmd"
exit /b %errorlevel%
''';
    return script
        .trim()
        .replaceAll('__TEMP_DIR__', _escapeCmdValue(tempDir))
        .replaceAll('\n', '\r\n');
  }

  static String _escapeCmdValue(String value) {
    return value.replaceAll('%', '%%').replaceAll('"', '""');
  }

  static String _escapePsValue(String value) {
    return value.replaceAll("'", "''");
  }
}
