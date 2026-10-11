import 'package:flutter/material.dart';
import 'package:pokemon_card_scanner/models/card_side.dart';
import 'package:pokemon_card_scanner/repositories/app_preferences.dart';

class ScanGuidePage extends StatefulWidget {
  const ScanGuidePage({super.key, this.side = CardSide.front, this.errorMessage, this.showSkipOption = false});

  final CardSide side;
  final String? errorMessage;
  final bool showSkipOption;

  @override
  State<ScanGuidePage> createState() => _ScanGuidePageState();
}

class _ScanGuidePageState extends State<ScanGuidePage> {
  bool _skipGuide = false;

  CardSide get side => widget.side;

  String? get errorMessage => widget.errorMessage;

  @override
  void initState() {
    super.initState();

    if (widget.showSkipOption) {
      _loadPreference();
    }
  }

  Future<void> _loadPreference() async {
    final skip = await AppPreferences.skipScanGuide();

    if (mounted) setState(() => _skipGuide = skip);
  }

  Future<void> _setSkipGuide(bool? value) async {
    if (value == null) return;

    setState(() => _skipGuide = value);
    await AppPreferences.setSkipScanGuide(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final headerColor = errorMessage == null ? colors.primaryContainer : Colors.redAccent;
    final headerTextColor = errorMessage == null ? colors.onPrimaryContainer : Colors.white;

    return Scaffold(
      appBar: AppBar(title: Text(side == CardSide.back ? 'Scan the back' : 'Scan the front')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: headerColor, borderRadius: BorderRadius.circular(24)),
                        child: Column(
                          children: [
                            Icon(errorMessage == null ? Icons.document_scanner_outlined : Icons.error_outline, size: 64, color: headerTextColor),
                            const SizedBox(height: 16),
                            Text(
                              errorMessage ?? (side == CardSide.back ? 'Photograph the card back' : 'Photograph the card front'),
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: headerTextColor),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _GuideTip(
                        icon: Icons.screen_rotation_outlined,
                        title: 'Keep the camera level',
                        description: 'Hold your phone directly above the card. Use the level indicator to check your position.',
                      ),
                      const _GuideTip(icon: Icons.wb_sunny_outlined, title: 'Use even lighting', description: 'Light the whole card evenly, without dark areas or shadows.'),
                      const _GuideTip(icon: Icons.visibility_outlined, title: 'Avoid reflections', description: 'Move the light or card until no glare or reflections cover the card\'s details.'),
                      const _GuideTip(
                        icon: Icons.center_focus_strong,
                        title: 'Give the camera room to focus',
                        description: 'If the text or corners look blurry, move your phone farther away. Keep it steady while the camera focuses and takes the photo.',
                      ),
                      const _GuideTip(
                        icon: Icons.crop_free,
                        title: 'Line up the guide with the card',
                        description: 'Try to line up the guide with the card while keeping all four corners clearly visible.',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.showSkipOption)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Don’t show this guide again'),
                          value: _skipGuide,
                          onChanged: _setSkipGuide,
                        ),
                      FilledButton.icon(onPressed: () => Navigator.of(context).pop(true), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take picture')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideTip extends StatelessWidget {
  const _GuideTip({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
