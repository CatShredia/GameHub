import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final SupabaseClient _sb = Supabase.instance.client;

class UploadedMedia {
  final String url;
  final String storagePath;
  final String bucket;
  final String name;
  final int sizeBytes;
  final String? mime;

  const UploadedMedia({
    required this.url,
    required this.storagePath,
    required this.bucket,
    required this.name,
    required this.sizeBytes,
    this.mime,
  });
}

/// Загрузка файлов в бакеты [chat-media] и [post-media].
/// Путь: [uid]/[uuid][ext]. Первый сегмент — uid (под RLS).
class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();

  static const String chatBucket = 'chat-media';
  static const String postBucket = 'post-media';
  static const String fallbackBucket = 'avatars';

  final _uuid = const Uuid();

  Future<UploadedMedia?> uploadChatMedia({
    required dynamic chatId,
    required File file,
    String? contentType,
  }) =>
      _upload(bucket: chatBucket, file: file, contentType: contentType);

  Future<UploadedMedia?> uploadPostMedia({
    required File file,
    String? contentType,
  }) =>
      _upload(bucket: postBucket, file: file, contentType: contentType);

  Future<UploadedMedia?> _upload({
    required String bucket,
    required File file,
    String? contentType,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;

    try {
      final ext = p.extension(file.path).isEmpty ? '' : p.extension(file.path);
      final fileName = '${_uuid.v4()}$ext';
      final objectPath = '${user.id}/$fileName';
      final bytes = await file.readAsBytes();

      final targetBucket =
          await _resolveBucket(bucket: bucket, objectPath: objectPath);
      if (targetBucket == null) {
        throw Exception(
          'Не найден ни один доступный бакет для медиа. Накатите SQL миграции 013 и 016.',
        );
      }

      await _sb.storage.from(targetBucket).uploadBinary(
        objectPath,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: false,
        ),
      );

      final publicUrl = _sb.storage.from(targetBucket).getPublicUrl(objectPath);
      return UploadedMedia(
        url: publicUrl,
        storagePath: objectPath,
        bucket: targetBucket,
        name: p.basename(file.path),
        sizeBytes: bytes.length,
        mime: contentType,
      );
    } catch (e, st) {
      debugPrint('MediaService.upload ошибка: $e\n$st');
      return null;
    }
  }

  Future<String?> _resolveBucket({
    required String bucket,
    required String objectPath,
  }) async {
    if (await _bucketAvailable(bucket, objectPath)) return bucket;
    if (await _bucketAvailable(fallbackBucket, objectPath)) {
      debugPrint(
        'MediaService: бакет "$bucket" не найден, fallback -> "$fallbackBucket"',
      );
      return fallbackBucket;
    }
    return null;
  }

  Future<bool> _bucketAvailable(String bucket, String objectPath) async {
    try {
      await _sb.storage.from(bucket).list(path: p.dirname(objectPath));
      return true;
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('bucket not found') || text.contains('statuscode: 404')) {
        return false;
      }
      // Если бакет существует, но list запретили RLS-ом — считаем доступным
      // и пробуем upload, чтобы не отбрасывать валидный путь.
      return true;
    }
  }
}
