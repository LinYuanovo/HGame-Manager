import 'dart:convert';
import 'dart:io';

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

  @override
  Future<List<RunningProcess>> snapshot() async {
    if (!Platform.isWindows) return const [];

    final result = await Process.run(
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

    if (result.exitCode != 0) return const [];

    final output = result.stdout.toString().trim();
    if (output.isEmpty) return const [];

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
    } catch (_) {
      return const [];
    }

    return const [];
  }
}
