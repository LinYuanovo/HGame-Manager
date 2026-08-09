import 'dart:io';
import 'dart:typed_data';

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

class AppUpdateCheckResult {
  final AppUpdateStatus status;
  final String currentVersion;
  final ChangelogEntry? latestEntry;
  final String? errorMessage;

  const AppUpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.latestEntry,
    this.errorMessage,
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

      return AppUpdateCheckResult(
        status: compareVersions(latestEntry.version, currentVersion) > 0
            ? AppUpdateStatus.updateAvailable
            : AppUpdateStatus.upToDate,
        currentVersion: currentVersion,
        latestEntry: latestEntry,
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

  Future<void> downloadAndInstall({
    required String version,
    required String executablePath,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('应用更新仅支持 Windows');
    }

    final client =
        _httpClient ?? await createProxyClientFromPrefs(domain: 'github.com');
    final tempRoot = await Directory.systemTemp.createTemp('hgame_update_');
    try {
      final response = await client
          .get(buildReleaseDownloadUri(version))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        throw HttpException('下载更新失败: HTTP ${response.statusCode}');
      }

      final extractedDir = Directory(path.join(tempRoot.path, 'extracted'));
      await extractedDir.create(recursive: true);
      await _extractZip(response.bodyBytes, extractedDir);

      final sourceDir = await _findReleaseRoot(extractedDir);
      final executableFile = File(
        path.join(sourceDir.path, path.basename(executablePath)),
      );
      if (!await executableFile.exists()) {
        throw const FormatException('更新压缩包中未找到应用程序文件');
      }

      final scriptFile = File(path.join(tempRoot.path, 'update.cmd'));
      await scriptFile.writeAsString(
        _buildUpdaterScript(
          processId: pid,
          sourceDir: sourceDir.path,
          targetDir: File(executablePath).parent.path,
          executablePath: executablePath,
          tempDir: tempRoot.path,
        ),
      );
      final cmdPath = path.join(
        Platform.environment['WINDIR'] ?? r'C:\Windows',
        'System32',
        'cmd.exe',
      );
      await Process.start(
        cmdPath,
        ['/d', '/c', scriptFile.path],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
      rethrow;
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  static Future<void> _extractZip(
    Uint8List bytes,
    Directory destination,
  ) async {
    final archive = ZipDecoder().decodeBytes(bytes);
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

      final target = File(targetPath);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.content as List<int>, flush: true);
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

  static String _buildUpdaterScript({
    required int processId,
    required String sourceDir,
    required String targetDir,
    required String executablePath,
    required String tempDir,
  }) {
    return [
      '@echo off',
      'setlocal EnableExtensions DisableDelayedExpansion',
      'set "PROCESS_ID=$processId"',
      'set "SOURCE_DIR=${_escapeCmdValue(sourceDir)}"',
      'set "TARGET_DIR=${_escapeCmdValue(targetDir)}"',
      'set "EXECUTABLE_PATH=${_escapeCmdValue(executablePath)}"',
      'set "TEMP_DIR=${_escapeCmdValue(tempDir)}"',
      'set "LOG_FILE=%TEMP_DIR%\\update.log"',
      'set "PROCESS_FILE=%TEMP_DIR%\\process.txt"',
      'call :log Updater started',
      'set /a WAIT_COUNT=0',
      ':wait_for_process',
      'tasklist /FI "PID eq %PROCESS_ID%" /FO CSV /NH > "%PROCESS_FILE%"',
      'set "PROCESS_FOUND="',
      'for /f "usebackq tokens=2 delims=," %%P in ("%PROCESS_FILE%") do if "%%~P"=="%PROCESS_ID%" set "PROCESS_FOUND=1"',
      'if not defined PROCESS_FOUND goto process_exited',
      'set /a WAIT_COUNT+=1',
      'if %WAIT_COUNT% GEQ 120 goto wait_timeout',
      'timeout /t 1 /nobreak >nul',
      'goto wait_for_process',
      ':process_exited',
      'del /q "%PROCESS_FILE%" >nul 2>&1',
      'call :log Old process exited',
      'robocopy "%SOURCE_DIR%" "%TARGET_DIR%" /E /COPY:DAT /DCOPY:DAT /R:3 /W:1 /XD "%SOURCE_DIR%\\hgame_manager_data" >> "%LOG_FILE%" 2>&1',
      'if errorlevel 8 goto copy_failed',
      'if not exist "%EXECUTABLE_PATH%" goto executable_missing',
      'call :log Files copied',
      'start "" /D "%TARGET_DIR%" "%EXECUTABLE_PATH%"',
      'if errorlevel 1 goto start_failed',
      'call :log New process started',
      'exit /b 0',
      ':wait_timeout',
      'call :log Waiting for old process timed out',
      'exit /b 1',
      ':copy_failed',
      'call :log File copy failed',
      'exit /b 1',
      ':executable_missing',
      'call :log New executable is missing',
      'exit /b 1',
      ':start_failed',
      'call :log New process failed to start',
      'exit /b 1',
      ':log',
      '>> "%LOG_FILE%" echo [%date% %time%] %*',
      'exit /b 0',
    ].join('\r\n');
  }

  static String _escapeCmdValue(String value) {
    return value.replaceAll('%', '%%').replaceAll('"', '""');
  }
}
