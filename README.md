# Pokemon Card Scanner - IKT213-G 26H Group 9

Flutter app for identifying and grading Pokemon cards using OpenCV machine vision.

## Installation

Installation is provided for **Android only**. iOS is technically possible with a Mac, Xcode, and iOS SDK, but has not
been tested.

### Android

Flutter and Android Studio are not needed to install the APK on a phone.

1. Open the [latest release](https://github.com/vegardan/pokemon-card-scanner/releases/latest) on your Android phone.
2. Under **Assets**, download `app-release.apk`.
3. Open the APK. If prompted, open **Settings** and enable **Allow from this source**.
4. Tap **Install**, then **Open**.

For an Android emulator, start it in Android Studio and drag the APK onto the emulator window.

To test machine vision in the emulator, open **Extended Controls -> Camera -> Virtual scene images -> Add image**. Add a
Pokemon card front and back as custom images, and scan them in the app using the camera. See the
[Control the virtual scene guide](https://developers.google.com/ar/develop/java/emulator#control_the_virtual_scene) for
details.

## Building

Requirements:

- [Flutter SDK](https://docs.flutter.dev/install/manual#install-flutter) **3.44.0 or newer**
- Android: Android Studio with Android SDK tools and its bundled JDK. Follow
  the [Android setup guide](https://docs.flutter.dev/platform-integration/android/setup).

```sh
git clone https://github.com/vegardan/pokemon-card-scanner.git
cd pokemon-card-scanner
flutter pub get
flutter run
```

**Android:** enable Developer options and debugging, connect the phone, and accept the debugging prompt. Alternatively,
start an emulator in Android Studio Device Manager.

## Dataset

The generated catalog and ORB references are bundled with the app inside `assets/data`. See
the [dataset builder guide](tool/dataset/README.md) for generation instructions.

## Roadmap

- [x] **FR1:** Let the user take a photo of the card’s front and back.
- [x] **FR2:** Show a card outline (guide frame) overlay in the camera view.
- [x] **FR3:** Show a level indicator while taking the photo.
- [x] **FR4:** Provide a guide with tips for taking a good card photo.
- [x] **FR5:** Identify the card from the front photo by matching it to cards in the reference dataset.
- [x] **FR6:** Verify that the back photo shows an English Pokemon card back.
- [x] **FR7:** Reject a photo with a message to retake it if the card cannot be identified or does not fill enough of
  the photo.
- [x] **FR8:** Save scanned cards to a collection.
- [x] **FR9:** Let the user view saved cards and their details.
- [x] **FR10:** Let the user delete a saved card.
- [x] **FR11:** Let the user browse the card catalog.
- [ ] **FR12:** Detect the card’s physical edges and produce a straightened image for analysis.
- [ ] **FR13:** Measure centering (left and right, top and bottom) on the front and back.
- [ ] **FR14:** Detect whitening/damages on edges/corners of the back of the card.
- [ ] **FR15:** Detect whitening/damages on edges/corners of the front of the card.
- [ ] **FR16:** Show the result for each measured condition factor.
- [ ] **FR17:** Based on the condition analysis result, estimate (not guarantee) a grade from 1–10 per factor and in
  total.
