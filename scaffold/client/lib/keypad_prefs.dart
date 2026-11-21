// OLIVE BRANCH — the grown-up's one keypad choice: "Scramble the keypad". MASTERFILE §8.3, §8.5.9.
//
// The code keypad is a plain 1 2 3 / 4 5 6 / 7 8 9 / 0 pad everywhere (pin_keypad.dart). A grown-up who types their
// code with a child watching can ask for the digits to be shuffled, from the platform's secure random source, again
// after every try. That is a shoulder-surfing defence, so it is THEIR choice: off unless they turn it on, never
// required, and an unreadable or missing record means OFF (the plain keypad), never a lock-out.
//
// WHERE IT LIVES. In the sealed `adultunlock` area on the device the keypad is typed on, under its own key, next to
// the grown-up's PIN check that same keypad is for. No new data area. A device wipe removes it with the area. It holds
// one yes/no and nothing else, and it is never sent anywhere.
import 'package:flutter/foundation.dart';

import 'local_services.dart';
import 'local_store.dart';

abstract class KeypadPrefsRepository {
  Future<bool> loadScramble();
  Future<void> saveScramble(bool on);
}

class MemoryKeypadPrefsRepository implements KeypadPrefsRepository {
  bool _on = false;
  @override
  Future<bool> loadScramble() async => _on;
  @override
  Future<void> saveScramble(bool on) async => _on = on;
}

class LocalStoreKeypadPrefsRepository implements KeypadPrefsRepository {
  LocalStoreKeypadPrefsRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'keypad';

  @override
  Future<bool> loadScramble() async {
    final Object? raw = await _ns.get(_key);
    // Fail to the plain keypad: only an exact, well-formed "yes" scrambles.
    return raw is Map && raw['v'] == 1 && raw['scramble'] == true;
  }

  @override
  Future<void> saveScramble(bool on) => _ns.put(_key, <String, Object?>{'v': 1, 'scramble': on});

  static LocalStoreKeypadPrefsRepository over(LocalServices s) =>
      LocalStoreKeypadPrefsRepository(s.area('adultunlock'));
}

class KeypadPrefs extends ChangeNotifier {
  KeypadPrefs({KeypadPrefsRepository? repo, bool scramble = false})
      : _repo = repo ?? MemoryKeypadPrefsRepository(),
        _scramble = scramble; // ignore: prefer_initializing_formals

  final KeypadPrefsRepository _repo;
  bool _scramble;

  /// True only when a grown-up turned the scramble on.
  bool get scramble => _scramble;

  /// Reads the saved choice. An unreadable store leaves the plain keypad.
  static Future<KeypadPrefs> load(KeypadPrefsRepository repo) async {
    bool on = false;
    try {
      on = await repo.loadScramble();
    } catch (_) {
      on = false;
    }
    return KeypadPrefs(repo: repo, scramble: on);
  }

  /// Saves, then applies. Returns false (and changes nothing) when the choice could not be kept, so the screen never
  /// claims a setting that would be gone after a restart.
  Future<bool> setScramble(bool on) async {
    if (on == _scramble) return true;
    try {
      await _repo.saveScramble(on);
    } catch (_) {
      return false;
    }
    _scramble = on;
    notifyListeners();
    return true;
  }
}
