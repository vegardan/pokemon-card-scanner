import 'package:flutter/foundation.dart';
import 'package:pokemon_card_scanner/models/grading_profile.dart';

class GradingProfileController extends ValueNotifier<GradingProfile> {
  static final instance = GradingProfileController._();

  GradingProfileController._() : super(GradingProfile.psa);
}
