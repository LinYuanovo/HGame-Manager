import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

class RunningProcess {
  final int pid;
  final int? parentPid;
  final String name;
  final String? executablePath;

  const RunningProcess({
    required this.pid,
    required this.name,
    this.parentPid,
    this.executablePath,
  });

  factory RunningProcess.fromWindowsMap(Map<String, dynamic> map) {
    return RunningProcess(
      pid: _asInt(map['ProcessId']) ?? 0,
      parentPid: _asInt(map['ParentProcessId']),
      name: map['Name']?.toString() ?? '',
      executablePath: map['ExecutablePath']?.toString(),
    );
  }

  String get normalizedName => name.toLowerCase();

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

abstract class ProcessProbe {
  Future<List<RunningProcess>> snapshot();
}

class WindowsProcessProbe implements ProcessProbe {
  const WindowsProcessProbe();
  static const _logTag = 'WindowsProcessProbe';

  @override
  Future<List<RunningProcess>> snapshot() async {
    if (!Platform.isWindows) {
      AppLogger.instance.warning(_logTag, '当前平台不是 Windows，进程快照返回空列表');
      return const [];
    }

    late final ProcessResult result;
    try {
      result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Get-CimInstance Win32_Process | '
              'Select-Object ProcessId,ParentProcessId,Name,ExecutablePath | '
              'ConvertTo-Json -Compress',
        ],
      );
    } catch (e, stackTrace) {
      AppLogger.instance
          .error(_logTag, '进程快照查询失败：无法启动 powershell.exe', e, stackTrace);
      return const [];
    }

    if (result.exitCode != 0) {
      AppLogger.instance.warning(
        _logTag,
        '进程快照查询失败：exitCode=${result.exitCode}, stderr=${result.stderr}',
      );
      return const [];
    }

    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      AppLogger.instance.warning(_logTag, '进程快照查询结果为空');
      return const [];
    }

    try {
      final decoded = jsonDecode(output);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) =>
                RunningProcess.fromWindowsMap(Map<String, dynamic>.from(item)))
            .where((process) => process.pid > 0 && process.name.isNotEmpty)
            .toList();
      }
      if (decoded is Map) {
        final process =
            RunningProcess.fromWindowsMap(Map<String, dynamic>.from(decoded));
        return process.pid > 0 && process.name.isNotEmpty
            ? [process]
            : const [];
      }
    } catch (e, stackTrace) {
      AppLogger.instance.error(_logTag, '进程快照 JSON 解析失败', e, stackTrace);
      return const [];
    }

    AppLogger.instance.warning(_logTag, '进程快照 JSON 格式异常：既不是数组也不是对象');
    return const [];
  }
}
