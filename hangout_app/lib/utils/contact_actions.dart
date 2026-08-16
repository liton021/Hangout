import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/call_data.dart';
import '../providers/call_controller.dart';
import '../providers/providers.dart';
import '../screens/call/audio_call_screen.dart';
import '../screens/call/video_call_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';

/// Shared entry points used by the Chats, Contacts and Discovery tabs so the
/// same tap always does the same thing.
class ContactActions {
  ContactActions._();

  /// Opens (creating if needed) the 1-on-1 conversation with [user].
  static Future<void> openChat(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final meUid = ref.read(authStateProvider).value?.uid;
    if (meUid == null) return;
    final chatId =
        await ref.read(chatServiceProvider).ensureChat(meUid, user.uid);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(peer: user, chatId: chatId),
    ));
  }

  /// Places an audio or video call to [peer] after checking permissions.
  static Future<void> startCall(
    BuildContext context,
    WidgetRef ref,
    AppUser peer,
    CallType type,
  ) async {
    final ok = await PermissionService.ensureForCall(
      context,
      video: type == CallType.video,
    );
    if (!ok || !context.mounted) return;
    final me = ref.read(currentAppUserProvider).value;
    if (me == null) return;
    final call = await ref.read(callControllerProvider.notifier).startCall(
          caller: me,
          callee: peer,
          type: type,
        );
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => type == CallType.video
          ? VideoCallScreen(call: call, isCaller: true)
          : AudioCallScreen(call: call, isCaller: true),
    ));
  }

  /// Long-press sheet: message / voice call / video call.
  static void showQuickActions(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  UserAvatar(user: user, radius: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (user.email.isNotEmpty)
                          Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SheetAction(
                icon: Icons.chat_bubble_rounded,
                label: 'Message',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openChat(context, ref, user);
                },
              ),
              _SheetAction(
                icon: Icons.call_rounded,
                label: 'Voice call',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  startCall(context, ref, user, CallType.audio);
                },
              ),
              _SheetAction(
                icon: Icons.videocam_rounded,
                label: 'Video call',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  startCall(context, ref, user, CallType.video);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.accentSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: AppColors.accentSoft, size: 21),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
