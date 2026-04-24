import 'package:flutter/material.dart';

import '../../database/services/rating_service.dart';

/// Листок с оценкой звёздами и комментарием. Используется для оценки продавца/покупателя.
class RateUserSheet extends StatefulWidget {
  final String targetId;
  final int auctionId;
  final RatingRole role;
  final String targetLabel;

  const RateUserSheet({
    super.key,
    required this.targetId,
    required this.auctionId,
    required this.role,
    required this.targetLabel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String targetId,
    required int auctionId,
    required RatingRole role,
    required String targetLabel,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1430),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: RateUserSheet(
          targetId: targetId,
          auctionId: auctionId,
          role: role,
          targetLabel: targetLabel,
        ),
      ),
    );
  }

  @override
  State<RateUserSheet> createState() => _RateUserSheetState();
}

class _RateUserSheetState extends State<RateUserSheet> {
  int _stars = 5;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final err = await RatingService.instance.submitRating(
      targetId: widget.targetId,
      auctionId: widget.auctionId,
      role: widget.role,
      stars: _stars,
      comment: _comment.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Оценить ${widget.role.label}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.targetLabel,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final val = i + 1;
              final active = val <= _stars;
              return IconButton(
                iconSize: 36,
                onPressed: () => setState(() => _stars = val),
                icon: Icon(
                  active ? Icons.star_rounded : Icons.star_border_rounded,
                  color: active ? const Color(0xFFF59E0B) : Colors.grey,
                ),
              );
            }),
          ),
          TextField(
            controller: _comment,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
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
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
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
    );
  }
}
