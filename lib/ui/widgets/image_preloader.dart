import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

class ImagePreloader {
  final Map<String, ui.Image> _cache = {};
  final Map<String, DateTime> _modifiedTimes = {};
  final Set<String> _loadingPaths = {};
  bool _disposed = false;

  Map<String, ui.Image> get cache => _cache;

  Future<void> preload(List<String> paths, {Function()? onComplete}) async {
    if (_disposed) return;
    final toLoad = <String>[];
    for (final p in paths) {
      if (_loadingPaths.contains(p)) continue;
      final file = File(p);
      if (!await file.exists()) continue;
      final modified = await file.lastModified();
      final cached = _modifiedTimes[p];
      if (_cache.containsKey(p) && cached != null && !modified.isAfter(cached)) continue;
      toLoad.add(p);
    }
    if (toLoad.isEmpty) return;

    await Future.wait(toLoad.map((path) => _loadSingle(path)), eagerError: false);
    onComplete?.call();
  }

  Future<void> _loadSingle(String path) async {
    if (_disposed) return;
    _loadingPaths.add(path);
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final modified = await file.lastModified();
      final bytes = await file.readAsBytes();
      if (_disposed) return;
      final codec = await ui.instantiateImageCodec(bytes);
      if (_disposed) { codec.dispose(); return; }
      final frame = await codec.getNextFrame();
      if (_disposed) { frame.image.dispose(); codec.dispose(); return; }
      _cache[path]?.dispose();
      _cache[path] = frame.image;
      _modifiedTimes[path] = modified;
      codec.dispose();
    } catch (_) {
    } finally {
      _loadingPaths.remove(path);
    }
  }

  void evictOutside(Set<String> activePaths) {
    final toRemove = <String>[];
    for (final path in _cache.keys) {
      if (!activePaths.contains(path)) {
        toRemove.add(path);
      }
    }
    for (final path in toRemove) {
      _cache[path]?.dispose();
      _cache.remove(path);
    }
  }

  void invalidate(List<String> paths) {
    for (final path in paths) {
      _cache[path]?.dispose();
      _cache.remove(path);
      _loadingPaths.remove(path);
    }
  }

  void dispose() {
    _disposed = true;
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _loadingPaths.clear();
  }
}
