// OLIVE BRANCH — what a GROWN-UP sees when the camera cannot start where they were about to scan a picture
// (guardian_pin_recovery_screens.dart, unlock_child_screen.dart). UNVERIFIED on a device; widget-tested headless
// (client/test/scanner_unavailable_test.dart).
//
// Without an errorBuilder, mobile_scanner draws the plugin's own raw English error text (for example
// "CAMERA_PERMISSION_DENIED"). This replaces it with plain adult words and one button that opens THIS app's page in
// the phone's settings, where the camera can be allowed again. Nothing here is ever shown on a child's device: the
// child-side scanners keep the calm card without words (CalmTryAgainCard).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens this app's page in the phone's settings. [MainActivity] answers on [kAppSettingsChannel] on Android.
typedef AppSettingsOpener = Future<void> Function();

const String kAppSettingsChannel = 'olive/app_settings';

/// Best effort: a missing native side (tests, other platforms) is not an error and shows nothing.
Future<void> openAppSettings([MethodChannel? channel]) async {
  try {
    await (channel ?? const MethodChannel(kAppSettingsChannel)).invokeMethod<void>('open');
  } on MissingPluginException {
    // No native side here; the card already says where to find the setting.
  } on PlatformException {
    // Could not open it; the card already says where to find the setting.
  }
}

/// The calm replacement for the plugin's error text. [openSettings] is for tests; the real one opens the app's settings.
class ScannerUnavailableCard extends StatelessWidget {
  const ScannerUnavailableCard({super.key, this.openSettings = openAppSettings});
  final AppSettingsOpener openSettings;

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Icon(Icons.no_photography_outlined, size: 32),
              const SizedBox(height: 8),
              const Text('The camera is not available right now.', key: Key('scannerUnavailableTitle'), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              const Text('Olive may not be allowed to use it. You can allow it in this phone\'s settings, under Apps, Olive, '
                  'Permissions, then come back to this screen.',
                  key: Key('scannerUnavailableBody'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                  key: const Key('scannerOpenSettings'), onPressed: () => openSettings(), child: const Text('Open settings')),
            ]),
          ),
        ),
      );
}

/// For `MobileScanner(errorBuilder: scannerErrorBuilder)` on a grown-up's screen. The plugin's error is dropped on purpose.
Widget scannerErrorBuilder(BuildContext context, MobileScannerException error) => const ScannerUnavailableCard();
