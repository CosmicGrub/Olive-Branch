// No longer UNVERIFIED — verified by CI (client/test/play_save_test.dart).
// OLIVE BRANCH — the dealer's save of a game in progress, so a game survives the OS killing the app.
//
// WHAT IS SAVED: only the dealing device (the authority) saves, and only the state needed to carry on (the board, the
// piles, whose turn it is). It lives in the sealed 'playsave' area of the on-device store (local_services.dart's
// catalogue, so the "Data on this device" screen lists it and its wipe covers it). It is deleted when the game ends,
// when a grown-up chooses "Finish for now", and by that wipe.
//
// WHAT IS NEVER SAVED (P2): an outcome, a winner, a result, a score, a tally, a history. A snapshot that carries one
// of those words as a key is refused outright; a finished game is cleared, not saved. The other device saves nothing:
// it is rebuilt from the dealer's hello and state when they find each other again.
import 'dart:async';
import 'dart:convert';

import 'live_games.dart' show auditLiveView, liveForbidden;
import 'local_store.dart';

/// Keys a snapshot may never carry, on top of live_games.dart's liveForbidden.
const List<String> playSaveBannedKeys = <String>['winner', 'outcome', 'result', 'won', 'lost', 'tally', 'history'];

/// The most one saved game may take, in bytes of JSON.
const int maxPlaySaveBytes = 16 * 1024;

/// True when [snapshot] is safe to keep: plain JSON, small, and with no outcome or score key at any depth.
bool playSaveAcceptable(Map<String, dynamic> snapshot) {
  if (!auditLiveView(snapshot).ok) return false;
  try {
    if (utf8.encode(jsonEncode(snapshot)).length > maxPlaySaveBytes) return false;
  } on Object {
    return false; // not plain JSON
  }
  final Set<String> banned = <String>{...playSaveBannedKeys, ...liveForbidden.map((String s) => s.toLowerCase())};
  bool clean = true;
  void walk(Object? x, int depth) {
    if (depth > 12) {
      clean = false;
    } else if (x is List) {
      for (final Object? e in x) {
        walk(e, depth + 1);
      }
    } else if (x is Map) {
      for (final MapEntry<dynamic, dynamic> e in x.entries) {
        if (banned.contains(e.key.toString().toLowerCase())) clean = false;
        walk(e.value, depth + 1);
      }
    }
  }

  walk(snapshot, 0);
  return clean;
}

abstract class PlaySaveStore {
  Future<Map<String, dynamic>?> load(String gameId);

  /// Returns false (and keeps what was there) when the snapshot is not acceptable.
  Future<bool> save(String gameId, Map<String, dynamic> snapshot);
  Future<void> clear(String gameId);
}

class MemoryPlaySaveStore implements PlaySaveStore {
  final Map<String, Map<String, dynamic>> saved = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> load(String gameId) async => saved[gameId];
  @override
  Future<bool> save(String gameId, Map<String, dynamic> snapshot) async {
    if (!playSaveAcceptable(snapshot)) return false;
    saved[gameId] = snapshot;
    return true;
  }

  @override
  Future<void> clear(String gameId) async => saved.remove(gameId);
}

/// The real one: the sealed 'playsave' area, one key per game.
class LocalPlaySaveStore implements PlaySaveStore {
  LocalPlaySaveStore(this._ns);
  final LocalNamespace _ns;

  @override
  Future<Map<String, dynamic>?> load(String gameId) async {
    try {
      final Object? raw = await _ns.get(gameId);
      if (raw is! Map || raw['v'] != 1 || raw['game'] != gameId) return null;
      final Object? state = raw['state'];
      return state is Map ? Map<String, dynamic>.from(state) : null;
    } on Object {
      return null; // a damaged save reads as no save, never as a crash
    }
  }

  @override
  Future<bool> save(String gameId, Map<String, dynamic> snapshot) async {
    if (!playSaveAcceptable(snapshot)) return false;
    try {
      await _ns.put(gameId, <String, Object?>{'v': 1, 'game': gameId, 'state': snapshot});
      return true;
    } on LocalStoreException {
      return false;
    }
  }

  @override
  Future<void> clear(String gameId) async {
    try {
      await _ns.delete(gameId);
    } on LocalStoreException {
      // nothing to clear
    }
  }
}
