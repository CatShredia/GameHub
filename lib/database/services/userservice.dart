import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_flutter;
import '../models/user.dart' as app_models;

class UserService {
  final SupabaseClient _client = Supabase.instance.client;
  static const String _avatarBucket = 'avatars';

  // ? Описание
  Future<supabase_flutter.AuthResponse> signIn(
    String email,
    String password,
  ) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // ? Описание
  Future<supabase_flutter.AuthResponse> signUp(
    String email,
    String password,
  ) async {
    return await _client.auth.signUp(email: email, password: password);
  }

  // ? Описание
  Future<app_models.User> createUserProfile({
    required String id,
    required String email,
    required String password,
  }) async {
    final response = await _client.from('users').insert({
      'id': id,
      'email': email,
      'password': password,
    }).select();

    final data = response.first;
    return app_models.User.fromJson(data);
  }

  // ? Описание
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ? Описание
  supabase_flutter.User? getCurrentUser() {
    return _client.auth.currentUser;
  }

  // ? Описание
  Future<app_models.User?> getUserProfile(String userId) async {
    final response = await _client
        .from('user')
        .select()
        .eq('id', userId)
        .single();

    return app_models.User.fromJson(response);
  }

  // ? Описание
  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // ? Описание
  Future<String> uploadAvatar(
    String userId,
    Uint8List imageBytes,
    String fileName,
  ) async {
    final path = '$userId/$fileName';

    debugPrint('Загрузка файла: $path');

    final response = await _client.storage
        .from(_avatarBucket)
        .uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(upsert: true),
        );

    debugPrint('Ответ от загрузки: $response');

    if (response.isEmpty) {
      throw Exception('Файл не загрузился');
    }

    final publicUrl = _client.storage.from(_avatarBucket).getPublicUrl(path);

    debugPrint('Публичный URL: $publicUrl');

    return publicUrl;
  }

  // ? Описание
  Future<void> updateUserAvatar(String userId, String avatarUrl) async {
    await _client.from('user').update({'avatar': avatarUrl}).eq('id', userId);
  }

  // ? Описание
  Future<app_models.User?> updateUserProfile({
    required String userId,
    String? email,
    String? password,
    String? name,
  }) async {
    final Map<String, dynamic> updateData = {};
    if (email != null) updateData['email'] = email;
    if (password != null) updateData['password'] = password;
    if (name != null) updateData['full_name'] = name;

    if (updateData.isEmpty) return null;

    final response = await _client
        .from('user')
        .update(updateData)
        .eq('id', userId)
        .select()
        .single();

    return app_models.User.fromJson(response);
  }

  // ? Описание
  Future<void> updateUserEmail(String newEmail) async {
    await _client.auth.updateUser(
      supabase_flutter.UserAttributes(email: newEmail),
    );
  }
}
