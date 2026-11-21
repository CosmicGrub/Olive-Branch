// OLIVE BRANCH — the printed recovery sheet: the page, and the phone's own print dialog. Verified headless
// (client/test/recovery_paths_logic_test.dart for the page; the dialog itself is the platform's).
// MASTERFILE section 7.22.
//
// UNVERIFIED on a real device: the page is tested, the print dialog (MainActivity's "olive/print_sheet" channel, the
// platform's own print service) has never been opened on a phone.
//
// The sheet is made so a person with no technical background can keep it: a first name, the key in large type in six
// groups of four, and four short lines of plain words about keeping it and using it. It carries no server address, no
// child's name and no number a stranger could use without the account's own family waiting and being told.
//
// Nothing is saved to a file by this app. The page is handed to the platform's print service as text and is not kept.
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException, PlatformException;

/// Opens the phone's print dialog with the sheet. Tests supply a stand-in.
abstract class SheetPrinter {
  /// True when the print dialog was opened. False when this phone cannot print from here (the screen then says to
  /// write the key down by hand, which always works).
  Future<bool> printSheet({required String title, required String html});
}

class PlatformSheetPrinter implements SheetPrinter {
  const PlatformSheetPrinter();
  static const MethodChannel _channel = MethodChannel('olive/print_sheet');

  @override
  Future<bool> printSheet({required String title, required String html}) async {
    try {
      final Object? ok = await _channel.invokeMethod<Object?>('print', <String, Object?>{'title': title, 'html': html});
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// The sheet as a small, high-contrast page. [key] is the grouped key ("K7Q2-M9XD-..."), [forName] a first name.
String recoverySheetHtml({required String key, required String forName, required DateTime made}) {
  final String name = _esc(forName.trim().isEmpty ? 'My family' : forName.trim());
  final String date = '${made.year}-${made.month.toString().padLeft(2, '0')}-${made.day.toString().padLeft(2, '0')}';
  return '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<style>'
      'body{font-family:sans-serif;color:#000;background:#fff;margin:32px;line-height:1.5;font-size:18px}'
      'h1{font-size:30px;margin:0 0 4px}'
      '.key{font-family:monospace;font-size:34px;letter-spacing:2px;border:3px solid #000;padding:18px;'
      'margin:22px 0;text-align:center;word-spacing:6px}'
      'p{margin:10px 0}.small{font-size:15px}'
      '</style></head><body>'
      '<h1>Olive recovery sheet</h1>'
      '<p>For: <b>$name</b> &nbsp; Made: $date</p>'
      '<div class="key">${_esc(key)}</div>'
      '<p><b>Keep this paper safe,</b> like your passport or your will. Do not take a photo of it.</p>'
      '<p><b>Lost your phone?</b> Open Olive on a new phone, go to Settings, then Family account, then '
      '"Lost your phone?", and choose "I have my printed recovery sheet". Then type this key.</p>'
      '<p>Nothing changes right away. Olive waits 3 days and tells every phone on your account first, so you can '
      'stop it if it was not you. Nothing is lost.</p>'
      '<p class="small">Olive never asks for this key by phone call, text or email. If someone does, it is not Olive. '
      'If this paper is lost or someone else has seen it, make a new sheet in Olive, and this one stops working.</p>'
      '</body></html>';
}
