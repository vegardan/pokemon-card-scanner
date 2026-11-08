import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/centering/centering_check.dart';
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/models/grading_profile.dart';
import 'package:pokemon_card_scanner/widgets/grading/centering_measurements.dart';
import 'package:pokemon_card_scanner/widgets/grading/grade_badge.dart';
import 'package:pokemon_card_scanner/widgets/image_carousel/fullscreen_image_gallery.dart';

class CenteringDetails extends StatefulWidget {
  final CenteringResult? front;
  final CenteringResult? back;
  final GradingProfile profile;

  const CenteringDetails({super.key, required this.front, required this.back, required this.profile});

  @override
  State<CenteringDetails> createState() => _CenteringDetailsState();
}

class _CenteringDetailsState extends State<CenteringDetails> {
  late CardSide _side;

  @override
  void initState() {
    super.initState();
    _side = widget.front != null
        ? CardSide.front
        : (widget.back != null ? CardSide.back : CardSide.front);
  }

  Widget _sideEstimate(BuildContext context, CardSide side) {
    final result = side == CardSide.front ? widget.front : widget.back;
    final grade = result == null ? null : widget.profile.centeringScoreForSide(side: side, leftRight: result.leftRight, topBottom: result.topBottom);
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (grade != null) GradeBadge(grade: grade, profileName: widget.profile.shortName),
        Text('${side == CardSide.front ? 'Front' : 'Back'} ${grade == null ? 'grade unavailable' : 'estimate'}', style: theme.textTheme.titleSmall),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final result = _side == CardSide.front ? widget.front : widget.back;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: colors.outlineVariant),
        const SizedBox(height: 20),
        SegmentedButton<CardSide>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: CardSide.front, label: Text('Front'), icon: Icon(Icons.flip_to_front_outlined)),
            ButtonSegment(value: CardSide.back, label: Text('Back'), icon: Icon(Icons.flip_to_back_outlined)),
          ],
          selected: {_side},
          onSelectionChanged: (selection) => setState(() => _side = selection.single),
        ),
        const SizedBox(height: 16),
        _sideEstimate(context, _side),
        const SizedBox(height: 16),
        if (result == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.crop_free, size: 32, color: colors.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('Could not be measured', style: theme.textTheme.bodyMedium),
              ],
            ),
          )
        else ...[
          CenteringMeasurements(leftMm: result.leftMm, rightMm: result.rightMm, topMm: result.topMm, bottomMm: result.bottomMm),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => FullscreenImageGallery(images: [MemoryImage(result.analysisImage)])));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Image.memory(result.analysisImage, width: 68, height: 94, fit: BoxFit.contain, semanticLabel: '${_side == CardSide.front ? 'Front' : 'Back'} centering analysis'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Border analysis', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text('Tap to zoom', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.fullscreen, color: colors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
