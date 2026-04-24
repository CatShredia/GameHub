import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/message_content_codec.dart';

/// Плитка файла-вложения (чат/лента). Тап — открыть в браузере/приложении.
class AttachmentTile extends StatelessWidget {
  final AttachmentMeta meta;
  final Color accent;
  final Color background;

  const AttachmentTile({
    super.key,
    required this.meta,
    this.accent = const Color(0xFF7C3AED),
    this.background = const Color(0xFF1A1430),
  });

  IconData _iconFor(String name, String? mime) {
    final n = name.toLowerCase();
    if ((mime ?? '').startsWith('image/') ||
        n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.webp') ||
        n.endsWith('.gif')) {
      return Icons.image_outlined;
    }
    if ((mime ?? '').startsWith('audio/')) return Icons.audiotrack;
    if ((mime ?? '').startsWith('video/') ||
        n.endsWith('.mp4') ||
        n.endsWith('.mov')) {
      return Icons.videocam_outlined;
    }
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.zip') || n.endsWith('.rar') || n.endsWith('.7z')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _fmtSize(int b) {
    if (b <= 0) return '';
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    double v = b.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final uri = Uri.tryParse(meta.url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_iconFor(meta.name, meta.mime), color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    meta.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _fmtSize(meta.sizeBytes),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.download_rounded, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
