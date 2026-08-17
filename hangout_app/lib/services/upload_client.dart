import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Raw HTTP response from [postBytes] — status plus the decoded body.
class UploadResponse {
  const UploadResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;

  bool get ok => statusCode == 200;
}

/// POSTs [bytes] to [uri] as a raw request body with a Bearer token.
///
/// Shared by [AvatarService] and [VoiceNoteService] because both upload a
/// single in-memory blob to the same Cloudflare Worker.
///
/// ── Why this helper exists ────────────────────────────────────────────────
/// Both services used to stream the body themselves with:
///
///     for (each 32 KB chunk) {
///       request.add(chunk);
///       await request.flush();      // ← the bug
///       onProgress(...);
///     }
///
/// `HttpClientRequest` is an `IOSink` whose consumer stays bound to the
/// underlying socket for the whole request. Calling `flush()` before the
/// request is closed therefore races that consumer and throws
/// `Bad state: StreamSink is bound to a stream` (dart-lang/sdk#28635,
/// #25277) — or, on a real Android socket, simply never completes.
///
/// That failure is neither a [SocketException] nor an [HttpException], so it
/// fell through to the generic `catch (_)` in the callers and surfaced as
/// "Something went wrong" / "Voice message wasn't sent" — i.e. profile
/// pictures and voice notes silently never uploaded, while every other call
/// to the same Worker (push, tokens) kept working because none of them
/// flushed mid-request.
///
/// The fix is to hand the body to `addStream` and let the sink drain it, then
/// let `close()` do the single, final flush. Progress is reported as each
/// chunk is pulled by the consumer, so the UI indicator still moves.
Future<UploadResponse> postBytes({
  required Uri uri,
  required Uint8List bytes,
  required String contentType,
  required String bearerToken,
  Duration connectionTimeout = const Duration(seconds: 15),
  Duration responseTimeout = const Duration(seconds: 60),
  void Function(double progress)? onProgress,
  double progressStart = 0,
  double progressEnd = 1,
}) async {
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
    // The Worker answers with JSON; being explicit avoids any content
    // negotiation surprises behind captive portals / proxies.
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    const chunkSize = 32 * 1024;
    final total = bytes.length;
    var sent = 0;

    final body = Stream<List<int>>.fromIterable(<List<int>>[
      for (var offset = 0; offset < total; offset += chunkSize)
        bytes.sublist(offset, math.min(offset + chunkSize, total)),
    ]).map((chunk) {
      sent += chunk.length;
      if (total > 0) {
        onProgress?.call(
          progressStart + (progressEnd - progressStart) * (sent / total),
        );
      }
      return chunk;
    });

    // addStream drains through the same consumer the socket owns, so there
    // is never a competing flush in flight.
    await request.addStream(body);

    final response = await request.close().timeout(responseTimeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(responseTimeout);
    return UploadResponse(response.statusCode, text);
  } finally {
    client.close();
  }
}

/// DELETEs [uri] with a Bearer token. Small helper so the avatar service does
/// not have to hand-roll another [HttpClient] lifecycle.
Future<UploadResponse> deleteWithToken({
  required Uri uri,
  required String bearerToken,
  Duration connectionTimeout = const Duration(seconds: 15),
  Duration responseTimeout = const Duration(seconds: 30),
}) async {
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  try {
    final request = await client.deleteUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(responseTimeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(responseTimeout);
    return UploadResponse(response.statusCode, text);
  } finally {
    client.close();
  }
}
