import 'package:flutter/material.dart';

import '../bottom/mini_page/notifications_sheet.dart';
import '../database/services/notification_service.dart';
import '../database/services/profile_service.dart';

/// Иконка-колокольчик с красным бейджем непрочитанных уведомлений.
class NotificationBell extends StatelessWidget {
  final Color iconColor;
  final double iconSize;

  const NotificationBell({
    super.key,
    this.iconColor = Colors.white,
    this.iconSize = 22,
  });

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1430),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => NotificationsSheet(profileService: ProfileService()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationService.instance.unreadCount(),
      initialData: NotificationService.instance.currentUnread,
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => _open(context),
              icon: Icon(Icons.notifications_outlined,
                  color: iconColor, size: iconSize),
              tooltip: 'Уведомления',
            ),
            if (unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC4899),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF0D0D1A),
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
