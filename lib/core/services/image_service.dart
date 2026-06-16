import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../utils/app_paths.dart';

class ImageService {
  static const _uuid = Uuid();

  /// 获取图片存储目录
  Future<String> getImageStorageDir() async {
    final rootDir = await AppPaths.rootDir;
    final imageDir = Directory('$rootDir${Platform.pathSeparator}game_images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir.path;
  }

  /// 从本地文件选择并复制图片
  Future<String?> pickAndCopyImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    if (file.path == null) return null;

    return await copyImageToStorage(file.path!);
  }

  /// 复制本地图片到应用存储目录
  Future<String> copyImageToStorage(String sourcePath) async {
    final storageDir = await getImageStorageDir();
    final extension = sourcePath.split('.').last;
    final fileName = '${_uuid.v4()}.$extension';
    final destPath = '$storageDir${Platform.pathSeparator}$fileName';

    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// 从URL下载图片
  Future<String?> downloadImageFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final storageDir = await getImageStorageDir();
      final extension = _getExtensionFromContentType(response.headers['content-type']) ?? 'jpg';
      final fileName = '${_uuid.v4()}.$extension';
      final destPath = '$storageDir${Platform.pathSeparator}$fileName';

      await File(destPath).writeAsBytes(response.bodyBytes);
      return destPath;
    } catch (e) {
      return null;
    }
  }

  /// 删除图片文件
  Future<bool> deleteImageFile(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 从Content-Type获取文件扩展名
  String? _getExtensionFromContentType(String? contentType) {
    if (contentType == null) return null;
    final map = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
      'image/bmp': 'bmp',
    };
    return map[contentType.split(';').first.trim()];
  }
}
