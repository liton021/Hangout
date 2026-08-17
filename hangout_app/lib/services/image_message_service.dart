import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config/app_config.dart';
import 'upload_client.dart';

/// Longest edge (px) chat photos are downscaled to before upload. 1600 px is
/// plenty sharp for a phone screen and keeps JPEGs around 150–400 KB — well
/// inside the Worker's 2 MB cap and kind to the 1 GB KV free tier.
const int kChatImageMaxEdge = 1600;

/// JPEG quality for the encoded photo.
const int kChatImageQuality = 82;

/// Hard ceiling enforced by the Worker (`IMAGE_MAX_BYTES`). The processed
/// image is far smaller; this is only a safety net.
const int kChatImageMaxBytes = 2 * 1024 * 1024;

/// Largest source file we even read into memory (~25 MP JPEG).
const int kChatImageMaxSourceBytes = 25 * 1024 * 1024;

/// Decodes and downscales a picked photo, returning JPEG bytes.
///
/// Top-level so it can run through [compute] on a background isolate —
/// decoding a 12 MP camera photo on the UI isolate would freeze the chat.
Uint8List processChatImage(Uint8List original) {
  final decoded = img.decodeImage(original);
  if (decoded == null) {
    throw const FormatException('That file is not a supported image.');
  }

  // Phone cameras store rotation in EXIF — bake it in before resizing so
  // the uploaded photo is upright everywhere.
  final oriented = img.bakeOrientation(decoded);

  final longest = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final image = longest > kChatImageMaxEdge
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height
              ? kChatImageMaxEdge
              : null,
          height: oriented.width >= oriented.height
              ? null
              : kChatImageMaxEdge,
          interpolation: img.Interpolation.average,
        )
      : oriented;

  return img.encodeJpg(image, quality: kChatImageQuality);
}

/// Thrown when the photo server rejects an upload; [message] is safe to show.
class ImageMessageException implements Exception {
  const ImageMessageException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Uploads chat photos to the Cloudflare Worker (`POST /image`).
///
/// Photos get a public URL that expires after 10 days (the Worker enforces
/// the TTL) — same storage and lifetime as voice notes, while profile
/// pictures (a different endpoint) never expire.
class ImageMessageService {
  ImageMessageService({required Future<String?> Function() idTokenProvider})
      : _idToken = idTokenProvider;

  final Future<String?> Function() _idToken;

  /// Downscales [original] and uploads it, reporting 0.0 → 1.0 progress.
  /// Returns the public URL to store on the message document.
  Future<String> upload(
    Uint8List original, {
    void Function(double progress)? onProgress,
  }) async {
    if (!AppConfig.useImageServer) {
      throw const ImageMessageException(
        'Photo messages are not configured for this build.',
      );
    }

    onProgress?.call(0);

    final processed = await compute(processChatImage, original);
    if (processed.lengthInBytes > kChatImageMaxBytes) {
      throw const ImageMessageException(
        'That photo is too large even after compression. Try another one.',
      );
    }

    onProgress?.call(0.1);

    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const ImageMessageException('You need to be signed in to do that.');
    }

    try {
      final response = await postBytes(
        uri: _endpoint(),
        bytes: processed,
        contentType: 'image/jpeg',
        bearerToken: token,
        responseTimeout: const Duration(seconds: 60),
        onProgress: onProgress,
        progressStart: 0.1,
        progressEnd: 0.9,
      );
      onProgress?.call(0.95);

      if (!response.ok) {
        throw ImageMessageException(
          _errorFrom(response.body, response.statusCode),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const ImageMessageException(
          'The server did not return a photo URL.',
        );
      }
      onProgress?.call(1);
      return url;
    } on ImageMessageException {
      rethrow;
    } on SocketException {
      throw const ImageMessageException(
        'No internet connection. Check your network and try again.',
      );
    } on TimeoutException {
      throw const ImageMessageException(
        'The upload timed out. Please try again.',
      );
    } on HttpException {
      throw const ImageMessageException(
        'Could not reach the server. Please try again.',
      );
    } on FormatException {
      throw const ImageMessageException(
        'The server sent an unexpected response. Please try again.',
      );
    }
  }

  /// Builds the `/image` endpoint URL, preserving any path on the base URL.
  Uri _endpoint() {
    final base = Uri.parse(AppConfig.imageServerUrl);
    final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$prefix/image', query: '');
  }

  /// Turns a Worker error body into something worth showing a user.
  String _errorFrom(String body, int status) {
    String? message;
    String? errorCode;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] is String) message = decoded['error'] as String;
        if (decoded['errorCode'] is String) {
          errorCode = decoded['errorCode'] as String;
        }
      }
    } catch (_) {
      // Fall through to the generic message.
    }

    if (status == 501) {
      return 'Photo messages are not set up on the server yet.';
    }
    if (status == 413) return 'That photo is too large to send.';
    if (status == 429) return 'Too many photos — wait a moment.';
    if (status == 401) {
      if (errorCode == 'server_missing_firebase_project_id' ||
          (message ?? '').contains('FIREBASE_PROJECT_ID')) {
        return 'Photo messages are blocked by a missing server setting '
            '(the Hangout server has no Firebase project ID). '
            'Please try again later.';
      }
      return 'The photo server could not verify your login. Please try again.';
    }
    if (message != null && message.isNotEmpty) return message;
    return 'Upload failed (error $status).';
  }
}
