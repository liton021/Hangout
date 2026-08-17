import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/providers.dart';
import '../../services/avatar_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import 'avatar_crop_screen.dart';

/// Everything behind "tap your picture to change it": the source sheet,
/// the cropper, the upload, and saving the URL to Firestore.
class AvatarPicker {
  AvatarPicker._();

  /// Largest file we'll even read into memory before cropping (~20 MP JPEG).
  static const int _maxSourceBytes = 20 * 1024 * 1024;

  /// Shows the bottom sheet and runs the whole change-photo flow.
  ///
  /// [hasPhoto] controls whether the "Remove photo" option is offered.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required bool hasPhoto,
  }) async {
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => _SourceSheet(hasPhoto: hasPhoto),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _AvatarAction.camera:
        await _pickAndUpload(context, ref, ImageSource.camera);
      case _AvatarAction.gallery:
        await _pickAndUpload(context, ref, ImageSource.gallery);
      case _AvatarAction.remove:
        await _remove(context, ref);
    }
  }

  static Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    // The manifest declares CAMERA, so image_picker needs it granted before
    // it will open the capture UI. Gallery picking needs no permission.
    if (source == ImageSource.camera) {
      if (!await PermissionService.ensureCamera(context)) return;
      if (!context.mounted) return;
    }

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        // Cheap pre-downscale in the platform picker keeps huge camera
        // shots from blowing up memory before we crop them.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (e) {
      if (context.mounted) {
        _snack(
          context,
          source == ImageSource.camera
              ? 'Could not open the camera. Check the app permissions.'
              : 'Could not open your photos. Check the app permissions.',
        );
      }
      return;
    }
    if (picked == null || !context.mounted) return;

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      if (context.mounted) _snack(context, 'That file could not be read.');
      return;
    }
    if (bytes.lengthInBytes > _maxSourceBytes) {
      if (context.mounted) _snack(context, 'That image is too large.');
      return;
    }
    if (!context.mounted) return;

    final crop = await Navigator.of(context).push<AvatarCropRequest>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AvatarCropScreen(bytes: bytes),
      ),
    );
    if (crop == null || !context.mounted) return;

    await _upload(context, ref, crop);
  }

  static Future<void> _upload(
    BuildContext context,
    WidgetRef ref,
    AvatarCropRequest crop,
  ) async {
    final progress = ValueNotifier<double>(0);
    final messenger = ScaffoldMessenger.of(context);
    // showDialog puts the dialog on the ROOT navigator, so that is the one
    // that has to dismiss it again.
    final navigator = Navigator.of(context, rootNavigator: true);

    // Non-dismissible: cancelling mid-upload would leave a partial object.
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadDialog(progress: progress),
    ).then((_) => dialogOpen = false);

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      navigator.pop();
    }
    try {
      final url = await ref.read(avatarServiceProvider).upload(
            crop.bytes,
            crop: crop,
            onProgress: (value) => progress.value = value,
          );
      await ref.read(userServiceProvider).setAvatarUrl(url);

      closeDialog();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Profile picture updated')),
        );
    } on AvatarUploadException catch (e) {
      closeDialog();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      closeDialog();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
    } finally {
      // The dialog keeps listening until its exit animation finishes, so
      // disposing the notifier right after pop() would pull it out from
      // under a live ValueListenableBuilder.
      Future<void>.delayed(const Duration(milliseconds: 500), progress.dispose);
    }
  }

  static Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text(
          'Your profile picture will go back to your initials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(avatarServiceProvider).delete();
      await ref.read(userServiceProvider).setAvatarUrl(null);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Profile picture removed')));
    } on AvatarUploadException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not remove the photo.')),
        );
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _AvatarAction { camera, gallery, remove }

/// "Take photo / Choose from gallery / Remove" chooser.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.hasPhoto});

  final bool hasPhoto;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: palette.divider,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Profile picture',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          _SourceTile(
            icon: Icons.photo_camera_rounded,
            label: 'Take photo',
            onTap: () => Navigator.of(context).pop(_AvatarAction.camera),
          ),
          _SourceTile(
            icon: Icons.photo_library_rounded,
            label: 'Choose from gallery',
            onTap: () => Navigator.of(context).pop(_AvatarAction.gallery),
          ),
          if (hasPhoto)
            _SourceTile(
              icon: Icons.delete_outline_rounded,
              label: 'Remove photo',
              danger: true,
              onTap: () => Navigator.of(context).pop(_AvatarAction.remove),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final tint = danger ? AppColors.danger : AppColors.accent;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(icon, color: tint, size: 26),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: danger ? AppColors.danger : palette.textPrimary,
        ),
      ),
    );
  }
}

/// Determinate progress ring shown while the picture uploads.
class _UploadDialog extends StatelessWidget {
  const _UploadDialog({required this.progress});

  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (context, value, _) => SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    // Indeterminate until the first byte moves.
                    value: value <= 0 ? null : value,
                    strokeWidth: 4,
                    color: AppColors.accent,
                    backgroundColor: palette.surfaceMuted,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Uploading photo…',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
