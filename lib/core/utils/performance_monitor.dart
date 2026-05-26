import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class PerformanceMonitor extends StatefulWidget {
  final Widget child;

  const PerformanceMonitor({super.key, required this.child});

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  final Map<String, int> _rebuildCounts = {};
  final Set<String> _highFrequencyWidgets = {};

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('═══ Performance Monitor Initialized ═══');
    }
  }

  void recordRebuild(String widgetName) {
    if (!kDebugMode) return;

    _rebuildCounts[widgetName] = (_rebuildCounts[widgetName] ?? 0) + 1;

    if (_rebuildCounts[widgetName]! > 10 && !_highFrequencyWidgets.contains(widgetName)) {
      _highFrequencyWidgets.add(widgetName);
      debugPrint('⚠️ HIGH FREQUENCY REBUILD DETECTED: $widgetName (${_rebuildCounts[widgetName]} times)');
    }

    if (_rebuildCounts[widgetName]! % 50 == 0 && _rebuildCounts[widgetName]! > 0) {
      debugPrint('📊 Widget: $widgetName - Total Rebuilds: ${_rebuildCounts[widgetName]}');
    }
  }

  void printSummary() {
    if (!kDebugMode) return;

    debugPrint('\n═══ PERFORMANCE SUMMARY ═══');
    final sortedEntries = _rebuildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (var i = 0; i < sortedEntries.length && i < 10; i++) {
      final entry = sortedEntries[i];
      debugPrint('${i + 1}. ${entry.key}: ${entry.value} rebuilds');
    }

    if (_highFrequencyWidgets.isNotEmpty) {
      debugPrint('\n⚠️ HIGH FREQUENCY WIDGETS:');
      for (var widget in _highFrequencyWidgets) {
        debugPrint('  - $widget (${_rebuildCounts[widget]} rebuilds)');
      }
    }
    debugPrint('═══════════════════════════════\n');
  }

  @override
  void dispose() {
    if (kDebugMode) {
      printSummary();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class MonitoredWidget extends StatefulWidget {
  final String name;
  final Widget child;

  const MonitoredWidget({
    super.key,
    required this.name,
    required this.child,
  });

  @override
  State<MonitoredWidget> createState() => _MonitoredWidgetState();
}

class _MonitoredWidgetState extends State<MonitoredWidget> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('🔄 MonitoredWidget Created: ${widget.name}');
    }
  }

  @override
  void didUpdateWidget(MonitoredWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kDebugMode) {
      debugPrint('🔄 MonitoredWidget Updated: ${widget.name}');
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('🗑️ MonitoredWidget Disposed: ${widget.name}');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint('🏗️ Building: ${widget.name}');
    }
    return widget.child;
  }
}
