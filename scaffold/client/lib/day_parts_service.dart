// OLIVE BRANCH — reading and saving her day-parts through the real routes. Verified headless
// (client/test/day_parts_service_test.dart, guardian_send_contract_test.dart). MASTERFILE section 8.31.
//
// UNVERIFIED on a real device or against a live server from the phone: covered by flutter test only.
//
// The server holds one schedule per child and PUT .../day-parts REPLACES it whole, in one transaction, behind a
// per-child writer lock (server/routes.mjs: pg_advisory_xact_lock on the child), so two saves can never merge
// into a union of both. This service keeps its side of that bargain:
//
//   * ONE SAVE AT A TIME per child from this phone. A second tap while one is running is told "busy"; it is
//     never queued behind, never sent in parallel.
//   * NEVER AN AUTOMATIC RETRY. A PUT replaces the whole schedule; repeating one after an unclear failure could
//     overwrite what another grown-up saved in between. A failed save changes nothing and says so; the grown-up
//     decides whether to save again.
//   * NO BLIND OVERWRITE. Just before saving it reads the schedule again. If it is no longer the one the editor
//     was opened on, someone else changed her day while this one was being edited: it does not save, and hands
//     back what is there now. (A small window remains between that read and the write, which the server's lock
//     serialises but cannot detect. There is no version number on this route yet; that is disclosed, not hidden.)
//   * THE SERVER'S ANSWER IS THE TRUTH. After a save the schedule shown is what the server returned, not what was
//     typed.
//   * IT CHECKS FIRST the way the server will (guardian_send_logic.dart checkDayParts), so a mistake is told in
//     words before a request is made, and a refusal that still comes back is worded too.
import 'api_client.dart';
import 'guardian_send_logic.dart';

typedef ApiOpener = Future<OliveApi> Function();

enum SaveKind {
  /// The server took it; [SaveResult.parts] is what it now holds.
  saved,

  /// Someone changed her day since the editor opened; nothing was written. [SaveResult.parts] is what is there.
  changedElsewhere,

  /// Not written: the schedule has a problem the server would refuse. [SaveResult.text] says which.
  invalid,

  /// Not written: a save is already running.
  busy,

  /// Not written: the server refused it or could not be reached. [SaveResult.text] says why.
  failed,
}

class SaveResult {
  const SaveResult(this.kind, {this.parts, this.text = ''});
  final SaveKind kind;
  final List<DayPartSpan>? parts;
  final String text;
}

class DayPartsService {
  DayPartsService({required this.childId, required this.openApi, this.closeApi = true});

  final String childId;
  final ApiOpener openApi;
  final bool closeApi;

  bool _saving = false;
  bool get saving => _saving;

  Future<T> _withApi<T>(Future<T> Function(OliveApi api) body) async {
    final OliveApi api = await openApi();
    try {
      return await body(api);
    } finally {
      if (closeApi) api.close();
    }
  }

  /// Her schedule as the server holds it. Throws [ApiException] on a refusal, [FormatException] on a reply that is
  /// not a schedule, and whatever the network throws.
  Future<List<DayPartSpan>> load() =>
      _withApi((OliveApi api) async => parseDayParts(await api.fetchDayParts(childId)));

  /// Saves [edited] as her whole schedule. [baseline] is the schedule the editor was opened on.
  Future<SaveResult> save({required List<DayPartSpan> edited, required List<DayPartSpan> baseline}) async {
    if (_saving) {
      return const SaveResult(SaveKind.busy, text: 'A save is already running. Wait for it to finish.');
    }
    final ScheduleCheck check = checkDayParts(edited);
    if (!check.canSave) {
      return SaveResult(SaveKind.invalid, text: check.problems.first.text);
    }
    _saving = true;
    try {
      return await _withApi<SaveResult>((OliveApi api) async {
        final List<DayPartSpan> now;
        try {
          now = parseDayParts(await api.fetchDayParts(childId));
        } catch (e) {
          return SaveResult(SaveKind.failed, text: dayPartSaveFailure(e));
        }
        if (!sameSchedule(now, baseline)) {
          return SaveResult(SaveKind.changedElsewhere,
              parts: now,
              text: 'Someone changed her day while you were editing it, so nothing was saved. '
                  "What is there now is shown. Make your change again if it still applies.");
        }
        try {
          final List<DayPartSpan> saved = parseDayParts(
              await api.putDayParts(childId, <Map<String, dynamic>>[for (final DayPartSpan p in edited) p.toJson()]));
          return SaveResult(SaveKind.saved,
              parts: saved,
              text: 'Saved. Anything still waiting to arrive will be timed again to match.');
        } on FormatException {
          // The write may have gone through; the answer could not be read. Say so, and show what is there.
          try {
            final List<DayPartSpan> again = parseDayParts(await api.fetchDayParts(childId));
            return SaveResult(SaveKind.saved,
                parts: again, text: 'Saved. Anything still waiting to arrive will be timed again to match.');
          } catch (_) {
            return const SaveResult(SaveKind.failed,
                text: "The server's answer could not be read, so it is not certain her day was saved. Open her day again to check.");
          }
        } catch (e) {
          return SaveResult(SaveKind.failed, text: dayPartSaveFailure(e));
        }
      });
    } catch (e) {
      // The api could not even be opened (not signed in).
      return SaveResult(SaveKind.failed, text: dayPartSaveFailure(e));
    } finally {
      _saving = false;
    }
  }
}
