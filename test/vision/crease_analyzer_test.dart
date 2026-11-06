import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:pokemon_card_scanner/vision/crease_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('flat/gradual profiles do not become prominent creases', () {
    for (final scores in [
      List.filled(200, 12.0),
      List.generate(200, (i) => 12.0 + i * .1),
    ]) {
      final peak = measureProfile(
        scores,
        List.filled(200, 100),
        start: 30,
        end: 170,
      )!;
      expect(peak.prominence.abs(), lessThan(1e-8));
    }
  });
  test('missing frame ribbons do not create artificial prominence', () {
    final scores = List.filled(200, 12.0);
    final counts = List.filled(200, 100);
    for (var i = 80; i < 100; i++) {
      scores[i] = 0;
      counts[i] = 0;
    }
    final peak = measureProfile(scores, counts, start: 30, end: 170)!;
    expect(peak.prominence.abs(), lessThan(1e-8));
  });
  test('excluded profiles have no peak', () {
    expect(
      measureProfile(
        List.filled(200, 100.0),
        List.filled(200, 0),
        start: 30,
        end: 170,
      ),
      isNull,
    );
  });
  test('strongest numerical fixture peak ignores unsupported samples', () {
    final scores = List.filled(240, 10.0)
      ..[80] = 90
      ..[160] = 110;
    final counts = List.filled(240, 100);
    expect(measureProfile(scores, counts, start: 30, end: 210)!.position, 160);
    counts[160] = 0;
    // Entire unsupported neighbourhood, not an artificial zero-valued sample.
    for (var i = 155; i <= 165; i++) {
      counts[i] = 0;
    }
    expect(measureProfile(scores, counts, start: 30, end: 210)!.position, 80);
  });
  test(
    'missing reference and alignment are not evaluated, not clean results',
    () {
      final bytes = Uint8List(0);
      expect(
        CreaseAnalyzer.analyze((
          photo: bytes,
          reference: null,
          alignmentVerified: true,
          expectedNoise: null,
          minimumProminence: 35,
        )).evaluated,
        isFalse,
      );
      expect(
        CreaseAnalyzer.analyze((
          photo: bytes,
          reference: bytes,
          alignmentVerified: false,
          expectedNoise: null,
          minimumProminence: 35,
        )).evaluated,
        isFalse,
      );
    },
  );
  test(
    'invalid cached noise is not evaluated and cannot mutate input bytes',
    () {
      final mat = cv.Mat.zeros(832, 600, cv.MatType.CV_8UC1);
      late Uint8List reference;
      try {
        reference = cv.imencode('.png', mat).$2;
      } finally {
        mat.dispose();
      }
      final original = Uint8List.fromList(reference);
      final result = CreaseAnalyzer.analyze((
        photo: reference,
        reference: reference,
        expectedNoise: Float32List(1),
        alignmentVerified: true,
        minimumProminence: 35,
      ));
      expect(result.evaluated, isFalse);
      expect(reference, original);
    },
  );
  test('invalid profile ranges are rejected', () {
    expect(
      () => measureProfile([1.0], [40], start: 0, end: 1),
      throwsArgumentError,
    );
  });
  test(
    'native pipeline returns zero candidates for identical images and both axes for a crossing',
    () {
      Uint8List encode(Uint8List pixels) {
        final mat = cv.Mat.fromList(832, 600, cv.MatType.CV_8UC1, pixels);
        try {
          final (ok, bytes) = cv.imencode('.png', mat);
          expect(ok, isTrue);
          return bytes;
        } finally {
          mat.dispose();
        }
      }

      final reference = encode(Uint8List(832 * 600));
      final clean = CreaseAnalyzer.analyze((
        photo: reference,
        reference: reference,
        alignmentVerified: true,
        expectedNoise: null,
        minimumProminence: 35,
      ));
      expect(clean.evaluated, isTrue);
      expect(clean.candidates, isEmpty);
      final pixels = Uint8List(832 * 600);
      for (var y = 0; y < 832; y++) {
        for (var x = 0; x < 600; x++) {
          if ((y - 220).abs() <= 2 || (x - 300).abs() <= 2) {
            pixels[y * 600 + x] = 255;
          }
        }
      }
      final crossed = CreaseAnalyzer.analyze((
        photo: encode(pixels),
        reference: reference,
        alignmentVerified: true,
        expectedNoise: null,
        minimumProminence: 35,
      ));
      expect(crossed.evaluated, isTrue);
      // The transferred Python method also produces two extra oblique hypotheses
      // on this high-contrast synthetic crossing. Near-equal plateau scores
      // can select neighbouring fitted angles; allow 2 degrees here.
      expect(crossed.candidates.length, 4);
      final expectedAngles = [
        179.9696845464,
        90.7659863484,
        59.4895241484,
        121.1742679056,
      ];
      for (var i = 0; i < expectedAngles.length; i++) {
        expect(crossed.candidates[i].angle, closeTo(expectedAngles[i], 2));
      }
      expect(
        crossed.candidates.singleWhere((c) => c.angle > 179).y1,
        closeTo(220, 6),
      );
      expect(
        crossed.candidates.singleWhere((c) => (c.angle - 90).abs() < 2).x1,
        closeTo(300, 7),
      );
      // A constant column profile must not acquire a peak from the excluded
      // 5% zero-valued margin (a regression found during Python comparison).
      final stripes = Uint8List(832 * 600);
      for (var y = 0; y < 832; y++) {
        if (y % 24 >= 12) stripes.fillRange(y * 600, (y + 1) * 600, 255);
      }
      final marginCheck = CreaseAnalyzer.analyze((
        photo: encode(stripes),
        reference: reference,
        alignmentVerified: true,
        expectedNoise: null,
        minimumProminence: 35,
      ));
      expect(marginCheck.evaluated, isTrue);
      expect(marginCheck.candidates.where((c) => c.angle == 90), isEmpty);
      final invalid = CreaseAnalyzer.analyze((
        photo: Uint8List.fromList([1, 2, 3]),
        reference: reference,
        alignmentVerified: true,
        expectedNoise: null,
        minimumProminence: 35,
      ));
      expect(invalid.evaluated, isFalse);
    },
  );
  test(
    'reference frame displacement is excluded while an inner crease remains',
    () {
      Uint8List image({required bool shifted, required bool crease}) {
        final pixels = Uint8List(832 * 600);
        for (var y = 33; y < 800; y++) {
          for (var x = shifted ? 32 : 27; x < (shifted ? 565 : 570); x++) {
            pixels[y * 600 + x] = crease && (y - 220).abs() <= 2 ? 220 : 100;
          }
        }
        final mat = cv.Mat.fromList(832, 600, cv.MatType.CV_8UC1, pixels);
        try {
          return cv.imencode('.png', mat).$2;
        } finally {
          mat.dispose();
        }
      }

      final reference = image(shifted: false, crease: false);
      final clean = CreaseAnalyzer.analyze((
        photo: image(shifted: true, crease: false),
        reference: reference,
        alignmentVerified: true,
        expectedNoise: null,
        minimumProminence: 35,
      ));
      expect(clean.evaluated, isTrue);
      expect(clean.candidates, isEmpty);
      final folded = CreaseAnalyzer.analyze((
        photo: image(shifted: true, crease: true),
        reference: reference,
        alignmentVerified: true,
        expectedNoise: null,
        minimumProminence: 35,
      ));
      expect(folded.evaluated, isTrue);
      expect(folded.candidates.length, 1);
      expect(folded.candidates.single.angle, 0);
      expect(folded.candidates.single.y1, closeTo(220, 6));
    },
  );
  test('rotated profiles retain separated parallel lines and a diagonal', () {
    final pixels = Float32List(600 * 832), valid = Uint8List(600 * 832);
    for (var y = 42; y < 790; y++) {
      for (var x = 30; x < 570; x++) {
        valid[y * 600 + x] = 255;
        if ((y - 220).abs() <= 2 ||
            (y - 420).abs() <= 2 ||
            (y - (x * .7 + 100)).abs() <= 2) {
          pixels[y * 600 + x] = 200;
        }
      }
    }
    final d = cv.Mat.fromList(832, 600, cv.MatType.CV_32FC1, pixels);
    final v = cv.Mat.fromList(832, 600, cv.MatType.CV_8UC1, valid);
    try {
      final c = CreaseAnalyzer.rotatedProfiles(d, v, 600, 832, 40);
      expect(
        c.where((a) => a.angle == 0 && (a.rho - 220).abs() < 5),
        isNotEmpty,
      );
      expect(
        c.where((a) => a.angle == 0 && (a.rho - 420).abs() < 5),
        isNotEmpty,
      );
      expect(c.where((a) => (a.angle - 35).abs() < 1), isNotEmpty);
    } finally {
      d.dispose();
      v.dispose();
    }
  });
  const fixtureDirectory = String.fromEnvironment('CREASE_FIXTURES');
  test(
    'combined pipeline matches all 17 Python development images',
    () {
      final reference = File('assets/pokemon_back.png').readAsBytesSync();
      final setup = Stopwatch()..start();
      final noise = CreaseAnalyzer.referenceNoise(reference);
      final preparationMs = setup.elapsedMicroseconds / 1000;
      final expected =
          jsonDecode(File('$fixtureDirectory/expected.json').readAsStringSync())
              as List;
      final results = <Map<String, Object?>>[];
      final failures = <String>[];
      for (final row in expected) {
        final name = row['name'] as String;
        final timer = Stopwatch()..start();
        final result = CreaseAnalyzer.analyze((
          photo: File('$fixtureDirectory/$name.png').readAsBytesSync(),
          reference: reference,
          expectedNoise: noise,
          alignmentVerified: true,
          minimumProminence: 35,
        ));
        final elapsed = timer.elapsedMicroseconds / 1000;
        final target = row['candidates'] as List;
        final remaining = result.candidates.toList();
        var maxAngle = 0.0, maxPosition = 0.0, maxScore = 0.0;
        if (!result.evaluated || remaining.length != target.length) {
          failures.add(
            '$name: ${remaining.length} candidates, expected ${target.length}',
          );
        }
        for (final e in target) {
          if (remaining.isEmpty) break;
          double angleError(PossibleCrease c) {
            final d = (c.angle - (e['angle'] as num)).abs();
            return math.min(d, 180 - d);
          }

          double positionError(PossibleCrease c) {
            final mid = e['geometry']['mid'] as List;
            final t = c.angle * math.pi / 180;
            return (-math.sin(t) * (mid[0] as num) +
                    math.cos(t) * (mid[1] as num) -
                    c.rho)
                .abs();
          }

          remaining.sort(
            (a, b) => (angleError(a) + positionError(a)).compareTo(
              angleError(b) + positionError(b),
            ),
          );
          final c = remaining.removeAt(0);
          final da = angleError(c),
              dp = positionError(c),
              ds = (c.prominence - (e['score'] as num)).abs();
          maxAngle = math.max(maxAngle, da);
          maxPosition = math.max(maxPosition, dp);
          maxScore = math.max(maxScore, ds);
          if (da > .1 || dp > .25 || ds > .2) {
            failures.add('$name: delta angle=$da position=$dp score=$ds');
          }
        }
        results.add({
          'name': name,
          'milliseconds': elapsed,
          'evaluated': result.evaluated,
          'maxAngleError': maxAngle,
          'maxPositionError': maxPosition,
          'maxScoreError': maxScore,
          'candidates': [
            for (final c in result.candidates)
              {'angle': c.angle, 'rho': c.rho, 'score': c.prominence},
          ],
        });
      }
      File('$fixtureDirectory/dart_results.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'noiseMilliseconds': preparationMs,
          'cases': results,
          'failures': failures,
        }),
      );
      expect(failures, isEmpty);
    },
    skip: fixtureDirectory.isEmpty
        ? 'Set CREASE_FIXTURES to the local development fixture directory.'
        : false,
  );

  // Real-image Python profile regressions are appended below. These are numerical
  // tests, not independent evidence of general damage-detection accuracy.
  test('Python parity: Clean A horizontal', () {
    final scores = <double>[
      16.868845,
      17.8167725,
      17.7116337,
      16.6552887,
      17.0621662,
      16.4452839,
      17.3890953,
      16.3590584,
      15.7635746,
      15.5680647,
      15.1557646,
      15.1400232,
      14.3981857,
      14.0594568,
      14.0000353,
      13.7801189,
      14.9866915,
      15.5456553,
      14.0546465,
      13.9704933,
      13.5164785,
      14.2963839,
      14.1681604,
      13.4158258,
      13.8638039,
      13.3192263,
      16.4873371,
      20.9135513,
      27.9040108,
      31.6600952,
      31.3976326,
      30.7592182,
      30.0442085,
      31.566761,
      31.5560036,
      29.4752769,
      27.1923428,
      28.1238403,
      27.5390053,
      23.9002533,
      21.8684235,
      19.344286,
      18.8788147,
      17.5928326,
      16.481699,
      17.8150444,
      17.1036797,
      16.4674129,
      16.1948624,
      16.6245766,
      16.7823372,
      16.0114746,
      16.7846012,
      16.8335266,
      16.6059322,
      16.5535622,
      16.351162,
      15.7577295,
      14.6314249,
      14.6013489,
      14.3567076,
    ];
    final peak = measureProfile(
      scores,
      List.filled(scores.length, 100),
      start: 25,
      end: 36,
    )!;
    expect(peak.position, 30);
    expect(peak.prominence, closeTo(14.374567031860352, 0.0001));
  });
  test('Python parity: Crease A horizontal', () {
    final scores = <double>[
      11.4149618,
      11.874897,
      10.6656275,
      10.3998241,
      10.2969341,
      9.2773972,
      11.9108515,
      12.4477863,
      11.2240534,
      11.9130478,
      12.71276,
      10.5742531,
      12.028904,
      13.2399244,
      11.5286713,
      12.0594845,
      11.7568855,
      13.5888796,
      16.308466,
      16.7874794,
      16.0779209,
      19.2432499,
      21.5458469,
      23.8191051,
      25.311718,
      31.865551,
      39.8355026,
      46.2129555,
      49.6585197,
      59.8009262,
      69.6250916,
      59.3089104,
      61.1887093,
      58.1055069,
      43.3535385,
      41.5242043,
      43.2569351,
      33.0151024,
      25.8282452,
      19.2353172,
      14.9049129,
      14.8948298,
      16.1047306,
      14.960577,
      15.9898949,
      17.869894,
      16.5998821,
      14.382638,
      14.3748894,
      14.5992575,
      18.3200912,
      14.5887384,
      12.9166946,
      15.6629362,
      13.3021212,
      12.8810539,
      12.6301823,
      12.267065,
      12.9489975,
      13.4186687,
      16.7408085,
    ];
    final peak = measureProfile(
      scores,
      List.filled(scores.length, 100),
      start: 25,
      end: 36,
    )!;
    expect(peak.position, 30);
    expect(peak.prominence, closeTo(45.19172668457031, 0.0001));
  });
  test('Python parity: Clean B horizontal', () {
    final scores = <double>[
      14.3565893,
      14.2625904,
      13.4959774,
      13.4465847,
      13.7358217,
      12.6877804,
      12.6089134,
      13.0425758,
      13.0854864,
      13.9533215,
      13.3860092,
      12.9265528,
      13.0692139,
      13.2959547,
      13.0232143,
      12.5761423,
      12.3899469,
      12.2217913,
      13.0541143,
      13.3020601,
      16.6545029,
      20.1996708,
      19.9792976,
      20.582159,
      20.4904194,
      21.7036209,
      20.3907108,
      20.1924953,
      19.3724747,
      21.29142,
      25.0433941,
      21.3043537,
      17.9293365,
      16.1631336,
      15.136426,
      13.452673,
      12.3205948,
      13.6724491,
      13.8849821,
      13.1667624,
      12.75951,
      12.6199903,
      13.0633707,
      12.8386354,
      12.9339123,
      13.3016977,
      13.9012976,
      15.6611004,
      15.7267036,
      15.56005,
      13.6661472,
      13.0425863,
      13.0582247,
      11.4399757,
      11.289752,
      11.1377583,
      9.9741621,
      9.7457323,
      9.4631672,
      9.6900244,
      9.3902721,
    ];
    final peak = measureProfile(
      scores,
      List.filled(scores.length, 100),
      start: 25,
      end: 36,
    )!;
    expect(peak.position, 30);
    expect(peak.prominence, closeTo(8.806516647338867, 0.0001));
  });
  test('Python parity: Crease B horizontal', () {
    final scores = <double>[
      10.9970961,
      10.6772518,
      12.1957159,
      10.5026598,
      9.3907795,
      11.4769773,
      13.8741274,
      11.9477663,
      12.6482859,
      11.5233803,
      9.3293343,
      9.72686,
      10.0548115,
      9.3212986,
      9.5112581,
      8.374897,
      9.2203789,
      9.8338194,
      9.5836592,
      9.6922321,
      10.54634,
      10.589776,
      12.2868738,
      14.8700228,
      17.9288006,
      22.6074791,
      24.0567951,
      32.9121017,
      45.0822525,
      57.5581589,
      64.295929,
      56.117157,
      58.3941078,
      53.6607437,
      35.303997,
      40.6104202,
      35.504528,
      26.1507912,
      17.7848396,
      15.4924269,
      14.0830202,
      10.7977238,
      10.4629374,
      10.8544092,
      12.3595123,
      13.3257399,
      14.7379313,
      12.7569466,
      11.0421877,
      10.2950878,
      11.1985121,
      12.5464916,
      10.7246819,
      10.1748114,
      12.8384247,
      11.3569393,
      11.6540127,
      13.0645065,
      11.2529812,
      11.3916025,
      10.9258451,
    ];
    final peak = measureProfile(
      scores,
      List.filled(scores.length, 100),
      start: 25,
      end: 36,
    )!;
    expect(peak.position, 30);
    expect(peak.prominence, closeTo(46.385990142822266, 0.0001));
  });
  test('Python parity: Crossed horizontal', () {
    final scores = <double>[
      21.0487366,
      20.4684124,
      19.1917629,
      21.3355236,
      20.0010071,
      19.4153194,
      22.5393906,
      23.7070103,
      23.7814884,
      23.101757,
      27.4317818,
      24.1873379,
      22.975153,
      25.5685959,
      27.5822449,
      26.841053,
      32.3661537,
      31.2583485,
      37.3095474,
      30.6002579,
      43.2132072,
      44.6517715,
      47.1991692,
      56.17033,
      60.9817619,
      67.3285065,
      78.9420776,
      85.7223511,
      81.3776779,
      97.770462,
      94.5165405,
      92.4232941,
      86.885788,
      77.227356,
      71.2918854,
      66.1471176,
      56.5020485,
      54.8966408,
      53.434021,
      46.0352097,
      36.0109367,
      28.5316372,
      24.6031532,
      24.6252213,
      24.2320175,
      24.9774132,
      28.8678684,
      29.0389118,
      28.8741417,
      28.9054489,
      28.5340252,
      27.6147518,
      26.9888668,
      27.3967819,
      27.0554943,
      22.2789383,
      19.2085571,
      17.7822304,
      16.18437,
      14.6141558,
      15.5008888,
    ];
    final peak = measureProfile(
      scores,
      List.filled(scores.length, 100),
      start: 25,
      end: 36,
    )!;
    expect(peak.position, 30);
    expect(peak.prominence, closeTo(56.2506103515625, 0.0001));
  });
  test('Python parity: Crossed vertical', () {
    final scores = <double>[
      18.0272369,
      16.7031536,
      14.5631418,
      13.7596664,
      14.6857233,
      15.9773378,
      16.5112305,
      16.0077572,
      15.6947727,
      14.6883392,
      14.1415987,
      15.5151596,
      19.5748596,
      16.1142921,
      15.0049858,
      17.3283024,
      16.2054443,
      15.6187525,
      15.576725,
      17.0589771,
      16.4684715,
      17.6735439,
      19.496357,
      22.5899792,
      33.5508766,
      70.5241928,
      90.4739227,
      88.498085,
      127.645134,
      137.3825226,
      133.7531128,
      130.1390839,
      134.3493195,
      115.9905014,
      107.847496,
      110.2236328,
      90.7650146,
      97.5689392,
      91.6819077,
      86.6160812,
      71.2722168,
      69.3661499,
      54.9915581,
      44.1559372,
      42.7737617,
      39.0823402,
      30.0657616,
      28.8158169,
      27.7024918,
      19.4459591,
      16.1904449,
      15.646369,
      15.8650646,
      16.3380547,
      15.1831846,
      14.7599154,
      14.6353302,
      15.3033657,
      14.8063107,
      15.992219,
      16.0889015,
    ];
    final peak = measureProfile(
      scores,
      List.filled(scores.length, 100),
      start: 25,
      end: 36,
    )!;
    expect(peak.position, 30);
    expect(peak.prominence, closeTo(94.09745788574219, 0.0001));
  });
}

typedef CreasePeak = ({int position, double prominence});

CreasePeak? measureProfile(
  List<double> scores,
  List<int> counts, {
  required int start,
  required int end,
}) {
  final values = CreaseAnalyzer.profileProminence(
    scores,
    counts,
    start: start,
    end: end,
  );
  CreasePeak? best;
  for (var i = start; i < end; i++) {
    if (counts[i] >= 40 &&
        values[i].isFinite &&
        (best == null || values[i] > best.prominence)) {
      best = (position: i, prominence: values[i]);
    }
  }
  return best;
}
