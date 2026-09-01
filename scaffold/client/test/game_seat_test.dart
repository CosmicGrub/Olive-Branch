// OLIVE BRANCH — game_seat.dart tests. Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic tests, no
// Flutter/widget/network involved.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_seat.dart';
import 'package:olive_client/live_games.dart' show Side;

void main() {
  group('SeatRoster basics', () {
    test('byId finds a real seat, returns null for an unknown one', () {
      const roster = SeatRoster(seats: [
        Seat(seatId: 'a1', ownerDevice: Side.a, kind: SeatKind.human),
        Seat(seatId: 'b1', ownerDevice: Side.b, kind: SeatKind.cpu, cpuDifficulty: 'medium'),
      ]);
      expect(roster.byId('a1')?.kind, SeatKind.human);
      expect(roster.byId('nope'), isNull);
    });

    test('onDevice returns only that device\'s own seats', () {
      const roster = SeatRoster(seats: [
        Seat(seatId: 'a1', ownerDevice: Side.a, kind: SeatKind.human),
        Seat(seatId: 'a2', ownerDevice: Side.a, kind: SeatKind.cpu),
        Seat(seatId: 'b1', ownerDevice: Side.b, kind: SeatKind.human),
      ]);
      expect(roster.onDevice(Side.a).map((s) => s.seatId), ['a1', 'a2']);
      expect(roster.onDevice(Side.b).map((s) => s.seatId), ['b1']);
    });
  });

  group('turnOrder', () {
    test('a free-for-all table (no teams) keeps its original order', () {
      const roster = SeatRoster(seats: [
        Seat(seatId: 'a1', ownerDevice: Side.a, kind: SeatKind.human),
        Seat(seatId: 'b1', ownerDevice: Side.b, kind: SeatKind.human),
        Seat(seatId: 'a2', ownerDevice: Side.a, kind: SeatKind.cpu),
      ]);
      expect(roster.turnOrder().map((s) => s.seatId), ['a1', 'b1', 'a2']);
    });

    test('a team table interleaves one-seat-per-team-per-device, never a whole team back to back', () {
      final roster = twoVsTwoRoster(
        team1DeviceASeatId: 'a1', team2DeviceBSeatId: 'b1',
        team1DeviceASeat2Id: 'a2', team2DeviceBSeat2Id: 'b2',
      );
      final order = roster.turnOrder().map((s) => s.seatId).toList();
      expect(order, ['a1', 'b1', 'a2', 'b2']);
      // Real, load-bearing property: no team ever plays twice in a row.
      for (var i = 0; i < order.length - 1; i++) {
        final thisTeam = roster.byId(order[i])!.teamId;
        final nextTeam = roster.byId(order[i + 1])!.teamId;
        expect(thisTeam, isNot(nextTeam));
      }
    });
  });

  group('twoVsTwoRoster — team privacy is a device boundary', () {
    test('each team has exactly one seat on each device, never both on one', () {
      final roster = twoVsTwoRoster(
        team1DeviceASeatId: 'a1', team2DeviceBSeatId: 'b1',
        team1DeviceASeat2Id: 'a2', team2DeviceBSeat2Id: 'b2',
      );
      final team1Seats = roster.seats.where((s) => s.teamId == 'team1').toList();
      final team2Seats = roster.seats.where((s) => s.teamId == 'team2').toList();
      expect(team1Seats.every((s) => s.ownerDevice == Side.a), isTrue,
        reason: 'team1 is always on device A -- its partner\'s hand is never in memory on device B');
      expect(team2Seats.every((s) => s.ownerDevice == Side.b), isTrue);
    });

    test('defaults to a human anchor seat per device plus a CPU partner', () {
      final roster = twoVsTwoRoster(
        team1DeviceASeatId: 'a1', team2DeviceBSeatId: 'b1',
        team1DeviceASeat2Id: 'a2', team2DeviceBSeat2Id: 'b2',
      );
      expect(roster.byId('a1')!.kind, SeatKind.human);
      expect(roster.byId('a2')!.kind, SeatKind.cpu);
      expect(roster.byId('b1')!.kind, SeatKind.human);
      expect(roster.byId('b2')!.kind, SeatKind.cpu);
    });
  });
}
