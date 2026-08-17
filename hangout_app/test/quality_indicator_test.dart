import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hangout/widgets/quality_indicator.dart';

/// The video call screen asks for `compact: true`, which must render icons
/// only — no "Excellent" / "720p" / "High" text over the picture.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('CallQualityIndicator', () {
    testWidgets('compact mode shows icons but no text labels',
        (tester) async {
      await tester.pumpWidget(wrap(const CallQualityIndicator(
        compact: true,
        networkQuality: 1,
        videoQuality: '720p',
        audioQuality: 'High',
      )));

      // No textual readout at all.
      expect(find.byType(Text), findsNothing);
      expect(find.text('Excellent'), findsNothing);
      expect(find.text('720p'), findsNothing);
      expect(find.text('High'), findsNothing);

      // Signal + camera + mic glyphs instead.
      expect(find.byType(Icon), findsNWidgets(3));
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('compact mode drops the camera glyph on audio-only calls',
        (tester) async {
      await tester.pumpWidget(wrap(const CallQualityIndicator(
        compact: true,
        networkQuality: 2,
        videoQuality: null,
        audioQuality: 'Normal',
      )));

      expect(find.byType(Icon), findsNWidgets(2));
      expect(find.byIcon(Icons.videocam_rounded), findsNothing);
    });

    testWidgets('non-compact mode still shows the full labelled readout',
        (tester) async {
      await tester.pumpWidget(wrap(const CallQualityIndicator(
        networkQuality: 1,
        videoQuality: '720p',
        audioQuality: 'High',
      )));

      expect(find.text('Excellent'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
    });

    testWidgets('renders nothing before the first quality reading',
        (tester) async {
      await tester.pumpWidget(wrap(const CallQualityIndicator(
        compact: true,
        networkQuality: 0,
        videoQuality: '720p',
        audioQuality: 'High',
      )));

      expect(find.byType(Icon), findsNothing);
    });
  });
}
