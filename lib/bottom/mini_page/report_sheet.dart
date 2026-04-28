import 'package:flutter/material.dart';

import '../../database/services/report_service.dart';

/// Модалка с выбором причины жалобы и комментарием.
class ReportSheet extends StatefulWidget {
  final ReportTargetKind kind;
  final String targetId;

  const ReportSheet({
    super.key,
    required this.kind,
    required this.targetId,
  });

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  String? _reason;
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) return;
    setState(() => _sending = true);
    try {
      await ReportService.instance.submit(
        kind: widget.kind,
        targetId: widget.targetId,
        reason: _reason!,
        comment: _commentCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Жалоба отправлена')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Пожаловаться',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...ReportService.reasons.map(
              (r) => RadioListTile<String>(
                value: r,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                title: Text(r, style: const TextStyle(color: Colors.white)),
                activeColor: const Color(0xFF7C3AED),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Комментарий (необязательно)',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _reason == null || _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Отправить',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showReportSheet(
  BuildContext context, {
  required ReportTargetKind kind,
  required String targetId,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ReportSheet(kind: kind, targetId: targetId),
  );
}
