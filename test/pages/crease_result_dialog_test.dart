import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/pages/scan/crease_result_dialog.dart';
import 'package:pokemon_card_scanner/vision/crease_analyzer.dart';
import 'package:pokemon_card_scanner/widgets/crease_overlay.dart';

void main() {
  testWidgets('reusable overlay keeps image and line coordinates together', (
    tester,
  ) async {
    final mat = cv.Mat.zeros(832, 600, cv.MatType.CV_8UC1);
    final bytes = cv.imencode('.png', mat).$2;
    mat.dispose();
    final analysis = CreaseAnalysis(
      width: 600,
      height: 832,
      candidates: [
        (
          angle: 0.0,
          rho: 416.0,
          x1: 30.0,
          y1: 416.0,
          x2: 570.0,
          y2: 416.0,
          prominence: 50.0,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: CreaseOverlay(analysis: analysis, image: MemoryImage(bytes)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.descendant(
      of: find.byType(CreaseOverlay),
      matching: find.byType(CustomPaint),
    );
    final paint = tester.widget<CustomPaint>(finder);
    final size = tester.getSize(finder);
    expect(size, const Size(300, 416));
    expect(tester.getSize(find.byType(Image)), size);
    final canvas = _LineCanvas();
    paint.foregroundPainter!.paint(canvas, size);
    expect(canvas.lines.first.$1, const Offset(15, 208));
    expect(canvas.lines.last.$2, const Offset(281, 208));
    expect(tester.takeException(), isNull);
  });
  Future<void> openDialog(
    WidgetTester tester,
    Future<CreaseResult> analysis,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => CreaseResultDialog(analysis: analysis),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows progress while analysis is pending', (tester) async {
    final pending = Completer<CreaseResult>();
    await openDialog(tester, pending.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const CreaseResult.notEvaluated('Reference unavailable.'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('analysis failure still allows continuing the scan', (
    tester,
  ) async {
    await openDialog(
      tester,
      Future.value(const CreaseResult.notEvaluated('Reference unavailable.')),
    );
    expect(find.textContaining('not evaluated'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(CreaseResultDialog), findsNothing);
  });

  for (final hasCandidates in [false, true]) {
    testWidgets(
      'preview with candidates=$hasCandidates omits technical scores',
      (tester) async {
        final image = cv.Mat.zeros(8, 8, cv.MatType.CV_8UC1);
        final bytes = cv.imencode('.png', image).$2;
        image.dispose();
        final result = CreaseResult(
          preview: bytes,
          width: 8,
          height: 8,
          candidates: hasCandidates
              ? [
                  (
                    angle: 0.0,
                    rho: 4.0,
                    x1: 0.0,
                    y1: 4.0,
                    x2: 8.0,
                    y2: 4.0,
                    prominence: 45.0,
                  ),
                ]
              : [],
        );
        await openDialog(tester, Future.value(result));
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
        expect(
          find.textContaining('No possible creases'),
          hasCandidates ? findsNothing : findsOneWidget,
        );
        expect(find.textContaining('not confirmed damage'), findsOneWidget);
        expect(find.textContaining('rho'), findsNothing);
        expect(find.textContaining('profile score'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _LineCanvas implements Canvas {
  final lines = <(Offset, Offset)>[];
  @override
  void drawLine(Offset a, Offset b, Paint paint) => lines.add((a, b));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
