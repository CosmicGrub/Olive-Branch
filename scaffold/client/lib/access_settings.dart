// OLIVE BRANCH — "Accessibility for her device": the settings model, its
// repository and the controller screens read it through. No longer UNVERIFIED —
// verified by CI (client/test/access_settings_test.dart). MASTERFILE §8.4,
// §8.8.5, §8.13, §8.21.
//
// LOCAL-FIRST. Nothing here touches a network or a credential. The settings are
// a guardian's choices about HER device, kept on this device in LocalStore (area
// `access`, namespaced per child, not encrypted: five switches, nothing private).
// The shape follows her_colour_store.dart: an abstract interface, an in-memory
// implementation for tests and the preview, and the LocalStore one for the app.
//
// What is deliberately NOT here: any child-side setter. Her shell has no settings
// at any depth (§8.1); she only ever READS these through the scope in
// access_scope.dart. The guardian screen (access_screen.dart) is the one writer.
//
// Nothing stored is a score, streak, counter or tally (P2): five booleans.
import 'package:flutter/foundation.dart';

import 'a11y_speech.dart' show readAloudDefaultOn;
import 'local_services.dart';
import 'local_store.dart';

/// How big her text is: the prototype's Standard / Large / Largest (g-access).
/// Applied on top of her phone's own text size, never instead of it.
enum AccessTextSize {
  standard(1.0, 'Standard'),
  large(1.18, 'Large'),
  largest(1.41, 'Largest');

  const AccessTextSize(this.scale, this.label);

  /// Multiplies her device's own text scale (the prototype's 17, 20 and 24 px).
  final double scale;
  final String label;

  static AccessTextSize fromName(Object? n) {
    for (final AccessTextSize s in values) {
      if (s.name == n) return s;
    }
    return standard;
  }
}

/// The choices. All default off except read-aloud, which follows her age
/// until a guardian chooses (§8.8.5: default-on below 8, opt-in above), and the
/// text size, which defaults to standard.
@immutable
class AccessSettings {
  const AccessSettings({
    this.readAloud,
    this.reduceMotion = false,
    this.roomierReading = false,
    this.largerTargets = false,
    this.captions = false,
    this.visualAlerts = false,
    this.textSize = AccessTextSize.standard,
  });

  /// Null means "no guardian choice yet": [readAloudFor] then follows her age.
  final bool? readAloud;
  final bool reduceMotion;
  final bool roomierReading;
  final bool largerTargets;

  /// A wish only. Captions are not built (see [captionsBuilt]); this records
  /// that a guardian wants them, and nothing is shown because of it today.
  final bool captions;

  /// Alerts she can SEE: a picture and words that stay until she taps them, with
  /// a gentle buzz, so no cue is ever sound only. Off by default; the Compass
  /// "alerts she can see" profile turns it on, a guardian may too. Nothing ever
  /// flashes, for anyone (see compass_logic.dart's [AlertCue]).
  final bool visualAlerts;

  /// Standard, Large or Largest; multiplies her phone's own text size.
  final AccessTextSize textSize;

  static const AccessSettings defaults = AccessSettings();

  /// Whether read-aloud is on for a child of [ageYears] (null = unknown).
  bool readAloudFor(int? ageYears) => readAloud ?? readAloudDefaultOn(ageYears);

  /// What actually happens for captions: nothing, until they are built. The
  /// guardian screen says so in words; this keeps code and words in step.
  bool get captionsActive => captions && captionsBuilt;

  AccessSettings copyWith({
    bool? readAloud,
    bool clearReadAloud = false,
    bool? reduceMotion,
    bool? roomierReading,
    bool? largerTargets,
    bool? captions,
    bool? visualAlerts,
    AccessTextSize? textSize,
  }) =>
      AccessSettings(
        readAloud: clearReadAloud ? null : (readAloud ?? this.readAloud),
        reduceMotion: reduceMotion ?? this.reduceMotion,
        roomierReading: roomierReading ?? this.roomierReading,
        largerTargets: largerTargets ?? this.largerTargets,
        captions: captions ?? this.captions,
        visualAlerts: visualAlerts ?? this.visualAlerts,
        textSize: textSize ?? this.textSize,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        if (readAloud != null) 'readAloud': readAloud,
        'reduceMotion': reduceMotion,
        'roomierReading': roomierReading,
        'largerTargets': largerTargets,
        'captions': captions,
        if (visualAlerts) 'visualAlerts': true,
        if (textSize != AccessTextSize.standard) 'textSize': textSize.name,
      };

  /// Tolerant: anything that is not a map, and any field that is not a bool,
  /// falls back to its default rather than failing a child's screen.
  factory AccessSettings.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    bool? b(String k) => raw[k] is bool ? raw[k] as bool : null;
    return AccessSettings(
      readAloud: b('readAloud'),
      reduceMotion: b('reduceMotion') ?? false,
      roomierReading: b('roomierReading') ?? false,
      largerTargets: b('largerTargets') ?? false,
      captions: b('captions') ?? false,
      visualAlerts: b('visualAlerts') ?? false,
      textSize: AccessTextSize.fromName(raw['textSize']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccessSettings &&
      other.readAloud == readAloud &&
      other.reduceMotion == reduceMotion &&
      other.roomierReading == roomierReading &&
      other.largerTargets == largerTargets &&
      other.captions == captions &&
      other.visualAlerts == visualAlerts &&
      other.textSize == textSize;

  @override
  int get hashCode => Object.hash(readAloud, reduceMotion, roomierReading, largerTargets, captions, visualAlerts, textSize);
}

/// Captions on live calls and async artifacts are a §8.4 promise that is not
/// built in this client. Held as a constant so the guardian screen, the
/// effective-value getter and the tests cannot disagree about it.
const bool captionsBuilt = false;

/// The touch-target floors (dp). §8.4 names 64 for pre-readers; the guardian
/// side keeps the platform-standard 48. "Larger targets" raises the child floor.
const double kChildTarget = 64;
const double kChildTargetLarger = 80;
const double kGuardianTarget = 48;
const double kGuardianTargetLarger = 64;

/// The floor for a child control under [s].
double childTargetFor(AccessSettings s) => s.largerTargets ? kChildTargetLarger : kChildTarget;

/// The floor for a guardian control under [s].
double guardianTargetFor(AccessSettings s) => s.largerTargets ? kGuardianTargetLarger : kGuardianTarget;

// ============================================================== repository ==
abstract class AccessRepository {
  Future<AccessSettings> load();

  /// Throws if the settings cannot be kept; callers say so and carry on.
  Future<void> save(AccessSettings s);
}

/// In memory: tests, and the preview before the on-device store is installed.
class MemoryAccessRepository implements AccessRepository {
  MemoryAccessRepository([AccessSettings initial = AccessSettings.defaults]) : _s = initial;
  AccessSettings _s;
  int saves = 0;
  bool failSaves = false;

  @override
  Future<AccessSettings> load() async => _s;

  @override
  Future<void> save(AccessSettings s) async {
    if (failSaves) throw const LocalStoreFull('child.test.access', 0);
    _s = s;
    saves++;
  }
}

/// Durable, on this device, per child (LocalStore area `access`).
class LocalStoreAccessRepository implements AccessRepository {
  LocalStoreAccessRepository(LocalNamespace ns) : _fixed = ns;

  /// Bound lazily to [LocalServices.current] (so the child the device is
  /// showing, and a store installed after this object was built, are honoured).
  LocalStoreAccessRepository.shared([this._childId]) : _fixed = null;

  final LocalNamespace? _fixed;
  String? _childId;

  LocalNamespace get _ns => _fixed ?? LocalServices.current.area('access', ownerId: _childId);

  static const String _key = 'settings';

  @override
  Future<AccessSettings> load() async {
    try {
      return AccessSettings.fromJson(await _ns.get(_key));
    } catch (_) {
      // An unreadable file was quarantined by the store: start from defaults.
      return AccessSettings.defaults;
    }
  }

  @override
  Future<void> save(AccessSettings s) => _ns.put(_key, s.toJson());
}

// ============================================================== controller ==
/// Holds the current settings for the running app and tells listeners when they
/// change. One per app ([sharedAccess]); tests build their own.
class AccessController extends ChangeNotifier {
  AccessController({AccessRepository? repository, this.ageYears})
      : _repo = repository ?? LocalStoreAccessRepository.shared();

  final AccessRepository _repo;

  /// Her age in whole years when known; only used for the read-aloud default.
  int? ageYears;

  AccessSettings _value = AccessSettings.defaults;
  bool _loaded = false;

  AccessSettings get value => _value;
  bool get loaded => _loaded;

  /// Tells the controller her age once a screen knows it (it only moves the
  /// read-aloud default), and lets listeners react if it changed.
  void setAge(int? years) {
    if (years == ageYears) return;
    ageYears = years;
    notifyListeners();
  }

  /// Reads what was kept. Safe to call more than once.
  Future<void> load() async {
    final AccessSettings s = await _repo.load();
    _value = s;
    _loaded = true;
    notifyListeners();
  }

  /// Applies [change], tells listeners at once, then tries to keep it. Returns
  /// whether it was kept; a failed save still takes effect for this run.
  Future<bool> update(AccessSettings Function(AccessSettings current) change) async {
    final AccessSettings next = change(_value);
    if (next == _value) return true;
    _value = next;
    notifyListeners();
    try {
      await _repo.save(next);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// The one controller for the process, like sharedColourStore: the child's shell
/// reads it, the guardian's screen writes it, and they agree by construction.
final AccessController sharedAccess = AccessController();
