import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

class ImagePreloader {
  final Map<String, ui.Image> _cache = {};
  final Set<String> _loadingPaths = {};
  bool _disposed = false;

  Map<String, ui.Image> get cache => _cache;

  Future<void> preload(List<String> paths, {Function()? onComplete}) async {
    if (_disposed) return;
    final toLoad = paths.where((p) => !_cache.containsKey(p) && !_loadingPaths.contains(p)).toList();
    if (toLoad.isEmpty) return;

    await Future.wait(toLoad.map((path) => _loadSingle(path)), eagerError: false);
    onComplete?.call();
  }

  Future<void> _loadSingle(String path) async {
    if (_disposed || _cache.containsKey(path)) return;
    _loadingPaths.add(path);
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (_disposed) return;
      final codec = await ui.instantiateImageCodec(bytes);
      if (_disposed) { codec.dispose(); return; }
      final frame = await codec.getNextFrame();
      if (_disposed) { frame.image.dispose(); codec.dispose(); return; }
      _cache[path] = frame.image;
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

  void dispose() {
    _disposed = true;
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _loadingPaths.clear();
  }
}
