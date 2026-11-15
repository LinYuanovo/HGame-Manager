import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同路径图片替换同时清理原图和省内存封面缓存', () async {
    const imagePath = r'C:\Tests\cover.png';
    final original = FileImage(File(imagePath));
    final resized = ResizeImage(original, width: 768);
    final originalKey = await original.obtainKey(ImageConfiguration.empty);
    final resizedKey = await resized.obtainKey(ImageConfiguration.empty);
    for (final key in [originalKey, resizedKey]) {
      imageCache.putIfAbsent(key,
          () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future));
    }
    addTearDown(imageCache.clear);
    expect(imageCache.containsKey(originalKey), isTrue);
    expect(imageCache.containsKey(resizedKey), isTrue);
    await ImageService.invalidateFileCache(imagePath);
    expect(imageCache.containsKey(originalKey), isFalse);
    expect(imageCache.containsKey(resizedKey), isFalse);
  });
}
