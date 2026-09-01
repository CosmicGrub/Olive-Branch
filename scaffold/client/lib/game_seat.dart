// OLIVE BRANCH — the shared seat/roster type for ad-hoc local-play games
// that need more than two players. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion.
//
// WHY THIS IS ITS OWN FILE, used by exactly one game so far: War,
// Connect 4, Local Pictionary, and Piece It Together all stay simple
// two-seat games reusing live_games.dart's own Side{a,b} directly, with
// zero roster overhead — a device IS a seat for those. Uno is the only
// game in this expansion that can seat more than two, so this is cheap
// insurance against a second bespoke roster type if a future game ever
// needs seats too, not something forced onto the four simpler games.
//
// THE REAL ARCHITECTURE DECISION THIS ENCODES: still exactly two physical
// devices pairing over local_pairing.dart's transport — never an N-device
// mesh (local_discovery.dart/local_session.dart are both already scoped to
// exactly one peer, and nothing about this feature needs more). A device
// can locally host MORE than one seat instead — human or CPU — which is
// what lets a 4-seat Uno table (or a 2v2 team game) work over a strictly
// two-device transport: two seats live on each physical device.
library;

import 'live_games.dart' show Side;

enum SeatKind { human, cpu }

class Seat {
  const Seat({
    required this.seatId, required this.ownerDevice, required this.kind,
    this.displayName, this.cpuDifficulty, this.teamId,
  });

  /// Stable within one session — e.g. 'a1', 'a2', 'b1', 'b2' (device +
  /// ordinal), never reused for a different seat mid-game.
  final String seatId;

  /// Which PHYSICAL device hosts this seat — the real, load-bearing fact
  /// that makes team privacy a device boundary rather than a UI courtesy
  /// (see uno_session.dart's own header on why that matters for team
  /// mode): a seat's hand is only ever held in memory on its own
  /// ownerDevice, never the other one.
  final Side ownerDevice;

  final SeatKind kind;
  final String? displayName;

  /// Only meaningful for [SeatKind.cpu] — independently set per seat, so a
  /// table can mix a hard CPU partner with an easy CPU opponent.
  final String? cpuDifficulty;

  /// Null for a free-for-all table. When set, groups seats into a team —
  /// see uno_session.dart's own team turn-order convention (interleaved
  /// one-seat-per-team-per-device, never a whole team on one device).
  final String? teamId;
}

class SeatRoster {
  const SeatRoster({required this.seats});
  final List<Seat> seats;

  Seat? byId(String seatId) {
    for (final s in seats) {
      if (s.seatId == seatId) return s;
    }
    return null;
  }

  List<Seat> onDevice(Side device) => seats.where((s) => s.ownerDevice == device).toList();

  /// Real-turn-order-aware: for a team table, returns seats interleaved
  /// one-per-team-per-device (see this file's own header) rather than in
  /// raw list order, so callers never have to re-derive that convention
  /// themselves.
  List<Seat> turnOrder() {
    final teamIds = <String>[];
    for (final s in seats) {
      if (s.teamId != null && !teamIds.contains(s.teamId)) teamIds.add(s.teamId!);
    }
    if (teamIds.isEmpty) return List<Seat>.from(seats);
    final byTeam = <String, List<Seat>>{for (final t in teamIds) t: []};
    for (final s in seats) {
      if (s.teamId != null) byTeam[s.teamId]!.add(s);
    }
    final ordered = <Seat>[];
    var i = 0;
    var addedAny = true;
    while (addedAny) {
      addedAny = false;
      for (final t in teamIds) {
        final teamSeats = byTeam[t]!;
        if (i < teamSeats.length) {
          ordered.add(teamSeats[i]);
          addedAny = true;
        }
      }
      i++;
    }
    return ordered;
  }
}

/// Builds a real 2v2 roster: one seat per team per device, interleaved in
/// turn order — Team1@DeviceA, Team2@DeviceB, Team1@DeviceA, Team2@DeviceB.
/// This is the ONE concrete team-mode construction this expansion ships;
/// 3v3/uneven teams are explicitly deferred (see the Ad-Hoc Play Expansion
/// plan).
SeatRoster twoVsTwoRoster({
  required String team1DeviceASeatId, required String team2DeviceBSeatId,
  required String team1DeviceASeat2Id, required String team2DeviceBSeat2Id,
  SeatKind team1DeviceAKind = SeatKind.human, SeatKind team2DeviceBKind = SeatKind.human,
  SeatKind team1DeviceASeat2Kind = SeatKind.cpu, SeatKind team2DeviceBSeat2Kind = SeatKind.cpu,
}) => SeatRoster(seats: [
  Seat(seatId: team1DeviceASeatId, ownerDevice: Side.a, kind: team1DeviceAKind, teamId: 'team1'),
  Seat(seatId: team2DeviceBSeatId, ownerDevice: Side.b, kind: team2DeviceBKind, teamId: 'team2'),
  Seat(seatId: team1DeviceASeat2Id, ownerDevice: Side.a, kind: team1DeviceASeat2Kind, teamId: 'team1'),
  Seat(seatId: team2DeviceBSeat2Id, ownerDevice: Side.b, kind: team2DeviceBSeat2Kind, teamId: 'team2'),
]);
