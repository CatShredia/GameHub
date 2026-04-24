import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportTargetKind { post, auction, user, message }

extension ReportTargetKindX on ReportTargetKind {
  String get value {
    switch (this) {
      case ReportTargetKind.post:
        return 'post';
      case ReportTargetKind.auction:
        return 'auction';
      case ReportTargetKind.user:
        return 'user';
      case ReportTargetKind.message:
        return 'message';
    }
  }
}

/// Жалобы на контент и пользователей. Модерация — отдельно.
class ReportService {
  ReportService._();
  static final ReportService instance = ReportService._();

  static const List<String> reasons = [
    'Спам',
    'Оскорбления',
    'Мошенничество',
    'Запрещённый контент',
    'Нарушение правил',
    'Другое',
  ];

  SupabaseClient get _sb => Supabase.instance.client;

  Future<void> submit({
    required ReportTargetKind kind,
    required String targetId,
    required String reason,
    String? comment,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Не авторизован');
    }
    await _sb.from('Report').insert({
      'reporter_id': uid,
      'target_kind': kind.value,
      'target_id': targetId,
      'reason': reason,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
  }
}
