import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/avatar_service.dart';
import '../../widgets/gradient_button.dart';

/// Full-screen "position your photo" step: pinch/drag the picture inside a
/// circular window, then confirm.
///
/// Pops an [AvatarCropRequest] describing the framed region (in image
/// fractions), which [AvatarService.upload] turns into the final square JPEG.
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.bytes});

  /// The original picked file's bytes.
  final Uint8List bytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  ui.Image? _image;
  Object? _error;

  /// Zoom factor relative to "cover" (1.0 = the largest square that fits).
  double _zoom = 1;
  double _zoomStart = 1;

  /// Top-left offset of the drawn image within the viewport, in pixels.
  Offset _offset = Offset.zero;
  Offset _offsetStart = Offset.zero;
  Offset _focalStart = Offset.zero;

  /// Side of the square preview area, captured from the LayoutBuilder so the
  /// confirmed crop is computed against exactly what the user saw.
  double _viewport = 0;

  /// The initial centring needs the viewport size, which only exists at
  /// layout time — so it happens on the first build after decoding.
  bool _centred = false;

  static const double _maxZoom = 5;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _image = frame.image;
        // Start centred: a wide photo left-aligned would otherwise open on
        // its left edge rather than on the subject.
        _centred = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Display scale: image pixels → viewport pixels.
  double _scale(double viewport) {
    final image = _image!;
    final shortEdge = image.width < image.height
        ? image.width.toDouble()
        : image.height.toDouble();
    return (viewport / shortEdge) * _zoom;
  }

  /// Keeps the picture covering the whole circle — no empty corners.
  Offset _clamp(Offset value, double viewport) {
    final image = _image!;
    final scale = _scale(viewport);
    final width = image.width * scale;
    final height = image.height * scale;
    // Guard the clamp bounds: floating-point drift can make `viewport - width`
    // a hair above 0 on the short edge, and clamp() throws when min > max.
    final minX = viewport - width;
    final minY = viewport - height;
    return Offset(
      minX >= 0 ? 0.0 : value.dx.clamp(minX, 0.0).toDouble(),
      minY >= 0 ? 0.0 : value.dy.clamp(minY, 0.0).toDouble(),
    );
  }

  /// Centres the photo inside the circle (used on first layout).
  void _centre(double viewport) {
    final image = _image!;
    final scale = _scale(viewport);
    _offset = _clamp(
      Offset(
        (viewport - image.width * scale) / 2,
        (viewport - image.height * scale) / 2,
      ),
      viewport,
    );
    _centred = true;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomStart = _zoom;
    _offsetStart = _offset;
    _focalStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double viewport) {
    setState(() {
      final nextZoom = (_zoomStart * details.scale).clamp(1.0, _maxZoom).toDouble();
      // Keep the point under the user's fingers pinned while zooming.
      final ratio = nextZoom / _zoomStart;
      final pinned = _focalStart - (_focalStart - _offsetStart) * ratio;
      _zoom = nextZoom;
      _offset = _clamp(
        pinned + (details.localFocalPoint - _focalStart),
        viewport,
      );
    });
  }

  void _confirm() {
    final image = _image;
    final viewport = _viewport;
    if (image == null || viewport <= 0) return;

    final scale = _scale(viewport);
    final shortEdge = image.width < image.height
        ? image.width.toDouble()
        : image.height.toDouble();

    final clamped = _clamp(_offset, viewport);
    Navigator.of(context).pop(
      AvatarCropRequest(
        bytes: widget.bytes,
        left: (-clamped.dx / scale) / image.width,
        top: (-clamped.dy / scale) / image.height,
        size: (viewport / scale) / shortEdge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Position your photo'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _error != null
            ? const _ErrorBody()
            : _image == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final viewport = constraints.maxWidth <
                                      constraints.maxHeight
                                  ? constraints.maxWidth
                                  : constraints.maxHeight;
                              _viewport = viewport;
                              if (!_centred && viewport > 0) _centre(viewport);
                              return GestureDetector(
                                onScaleStart: _onScaleStart,
                                onScaleUpdate: (d) =>
                                    _onScaleUpdate(d, viewport),
                                child: SizedBox(
                                  width: viewport,
                                  height: viewport,
                                  child: ClipRect(
                                    child: CustomPaint(
                                      painter: _CropPainter(
                                        image: _image!,
                                        offset: _clamp(_offset, viewport),
                                        scale: _scale(viewport),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                        child: Text(
                          'Drag to reposition · pinch to zoom',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.7),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: GradientButton(
                          label: 'Use photo',
                          icon: Icons.check_rounded,
                          onPressed: _confirm,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_rounded,
                color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            const Text(
              'That image could not be opened.\nTry a different photo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the photo plus the circular mask/guide overlay.
class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.offset,
    required this.scale,
  });

  final ui.Image image;
  final Offset offset;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final destination = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      image.width * scale,
      image.height * scale,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // Dim everything outside the circle so the framing is unmistakable.
    final circle = Path()
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    final full = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, circle),
      Paint()..color = Colors.black.withOpacity(.62),
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(.9),
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.offset != offset || old.scale != scale;
}
