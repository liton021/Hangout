import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config/app_config.dart';
import 'upload_client.dart';

/// Square size (px) every avatar is normalised to before upload.
///
/// 512² is plenty for a 112 px profile card on a 3x screen, and keeps the
/// JPEG around 40–80 KB — small enough that thousands of users still fit in
/// the Cloudflare KV free tier (1 GB) and uploads finish on slow mobile data.
const int kAvatarSize = 512;

/// JPEG quality used for the encoded avatar (visually lossless at this size).
const int kAvatarQuality = 82;

/// Hard ceiling enforced by the Worker (`AVATAR_MAX_BYTES`). The processed
/// image is far smaller; this is only a safety net.
const int kAvatarMaxBytes = 512 * 1024;

/// Input for [processAvatarImage] — must be a plain value type so it can
/// cross an isolate boundary.
@immutable
class AvatarCropRequest {
  const AvatarCropRequest({
    required this.bytes,
    required this.left,
    required this.top,
    required this.size,
  });

  /// The original, unmodified file bytes.
  final Uint8List bytes;

  /// Left/top edge of the crop square as a fraction (0..1) of the
  /// EXIF-oriented image's width/height.
  ///
  /// Fractions rather than pixels keep the crop correct regardless of how
  /// the decoder ends up rotating the photo.
  final double left;
  final double top;

  /// Side of the crop square as a fraction (0..1) of the image's *shorter*
  /// edge — i.e. 1.0 is the largest square that fits.
  final double size;
}

/// Decodes, rotates, crops, resizes and JPEG-encodes an avatar.
///
/// Top-level (not a method) so it can run through [compute] on a background
/// isolate — decoding a 12 MP camera photo would otherwise freeze the UI for
/// a second or more.
Uint8List processAvatarImage(AvatarCropRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw const FormatException('That file is not a supported image.');
  }

  // Phone cameras store the rotation in EXIF rather than rotating the
  // pixels. Flutter's own decoder applies it when previewing, so we must
  // apply it here too or the crop would land in the wrong place.
  final oriented = img.bakeOrientation(decoded);

  // `size` is a fraction of the shorter edge, so the square always fits.
  final shortEdge = oriented.width < oriented.height
      ? oriented.width.toDouble()
      : oriented.height.toDouble();
  final cropSide = (request.size * shortEdge).clamp(1.0, shortEdge).toDouble();

  final maxX = (oriented.width - cropSide).clamp(0.0, oriented.width.toDouble()).toDouble();
  final maxY =
      (oriented.height - cropSide).clamp(0.0, oriented.height.toDouble()).toDouble();
  final x = (request.left * oriented.width).clamp(0.0, maxX).toDouble();
  final y = (request.top * oriented.height).clamp(0.0, maxY).toDouble();

  final cropped = img.copyCrop(
    oriented,
    x: x.round(),
    y: y.round(),
    width: cropSide.round(),
    height: cropSide.round(),
  );

  // Only ever downscale — upscaling a small picture just wastes bytes.
  final resized = cropped.width > kAvatarSize
      ? img.copyResize(
          cropped,
          width: kAvatarSize,
          height: kAvatarSize,
          interpolation: img.Interpolation.average,
        )
      : cropped;

  // encodeJpg already returns a Uint8List.
  return img.encodeJpg(resized, quality: kAvatarQuality);
}

/// Thrown when the avatar server rejects an upload; [message] is safe to show.
class AvatarUploadException implements Exception {
  const AvatarUploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Uploads profile pictures to the Cloudflare Worker in `token_server/`.
///
/// The Worker stores the image (Workers KV by default, R2 when a bucket is
/// bound) and returns a permanent, publicly cacheable URL. Nothing here
/// depends on which backend it chose.
class AvatarService {
  AvatarService({required Future<String?> Function() idTokenProvider})
      : _idToken = idTokenProvider;

  final Future<String?> Function() _idToken;

  /// Crops/compresses [original] and uploads it.
  ///
  /// [crop] describes the region the user framed. [onProgress] reports
  /// 0.0 → 1.0 so the UI can show a determinate ring.
  ///
  /// Returns the public URL to store on the user's Firestore document.
  Future<String> upload(
    Uint8List original, {
    required AvatarCropRequest crop,
    void Function(double progress)? onProgress,
  }) async {
    if (!AppConfig.useAvatarServer) {
      throw const AvatarUploadException(
        'Profile picture uploads are not configured for this build.',
      );
    }

    onProgress?.call(0);

    // Heavy image work off the UI isolate.
    final processed = await compute(processAvatarImage, crop);
    if (processed.lengthInBytes > kAvatarMaxBytes) {
      throw const AvatarUploadException(
        'That picture is too large even after compression. Try another one.',
      );
    }

    onProgress?.call(0.15);

    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const AvatarUploadException('You need to be signed in to do that.');
    }

    final uri = _endpoint();
    try {
      final response = await postBytes(
        uri: uri,
        bytes: processed,
        contentType: 'image/jpeg',
        bearerToken: token,
        responseTimeout: const Duration(seconds: 45),
        onProgress: onProgress,
        // Upload occupies the 15%–90% band of the progress bar.
        progressStart: 0.15,
        progressEnd: 0.90,
      );
      onProgress?.call(0.95);

      if (!response.ok) {
        throw AvatarUploadException(
          _errorFrom(response.body, response.statusCode),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const AvatarUploadException(
          'The server did not return an image URL.',
        );
      }
      onProgress?.call(1);
      return url;
    } on AvatarUploadException {
      rethrow;
    } on SocketException {
      throw const AvatarUploadException(
        'No internet connection. Check your network and try again.',
      );
    } on TimeoutException {
      throw const AvatarUploadException(
        'The upload timed out. Please try again.',
      );
    } on HttpException {
      throw const AvatarUploadException(
        'Could not reach the server. Please try again.',
      );
    } on FormatException {
      throw const AvatarUploadException(
        'The server sent an unexpected response. Please try again.',
      );
    }
  }

  /// Builds the `/avatar` endpoint URL.
  ///
  /// `Uri.replace(path: …)` on its own drops any path the configured base URL
  /// carries (e.g. a Worker mounted on `example.com/api`), so join the two
  /// instead of overwriting.
  Uri _endpoint() {
    final base = Uri.parse(AppConfig.avatarServerUrl);
    final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$prefix/avatar', query: '');
  }

  /// Removes the signed-in user's picture from storage.
  Future<void> delete() async {
    if (!AppConfig.useAvatarServer) return;
    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const AvatarUploadException('You need to be signed in to do that.');
    }

    try {
      final response = await deleteWithToken(
        uri: _endpoint(),
        bearerToken: token,
      );
      if (!response.ok) {
        throw AvatarUploadException(
          _errorFrom(response.body, response.statusCode),
        );
      }
    } on AvatarUploadException {
      rethrow;
    } on SocketException {
      throw const AvatarUploadException(
        'No internet connection. Check your network and try again.',
      );
    } on TimeoutException {
      throw const AvatarUploadException(
        'The request timed out. Please try again.',
      );
    } on HttpException {
      throw const AvatarUploadException(
        'Could not reach the server. Please try again.',
      );
    }
  }

  /// Turns a Worker error body into something worth showing a user.
  String _errorFrom(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        final error = decoded['error'] as String;
        if (status == 501) {
          return 'Photo storage is not set up on the server yet.';
        }
        if (status == 429) return 'Too many uploads — please wait a minute.';
        if (status == 401) return 'Your session expired. Sign in again.';
        return error;
      }
    } catch (_) {
      // Fall through to the generic message.
    }
    return 'Upload failed (error $status). Please try again.';
  }
}
