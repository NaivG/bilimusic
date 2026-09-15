import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/features/lan_sync/models/sync_message.dart';
import 'package:bilimusic/features/lan_sync/services/pairing_service.dart';
import 'package:bilimusic/features/lan_sync/services/sync_protocol.dart';

void main() {
  group('PairingService private topology', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'propagates a private edge and prunes it after direct unpair',
      () async {
        final pairing = PairingService();
        await pairing.load();
        await pairing.configureLocalId('A');
        await pairing.rememberDirectPeer('B', 'token-B');

        final changed = await pairing.mergeRoster([
          {'a': 'B', 'aToken': 'token-B', 'b': 'C', 'bToken': 'token-C'},
        ]);

        expect(changed, isTrue);
        expect(pairing.expectedTokenFor('C'), 'token-C');
        expect(pairing.rosterEdges, hasLength(2));

        await pairing.forgetPeer('B');

        expect(pairing.expectedTokenFor('B'), isNull);
        expect(pairing.expectedTokenFor('C'), isNull);
        expect(pairing.rosterEdges, isEmpty);
      },
    );

    test('does not retain a disconnected second group', () async {
      final pairing = PairingService();
      await pairing.load();
      await pairing.configureLocalId('A');
      await pairing.rememberDirectPeer('B', 'token-B');

      await pairing.mergeRoster([
        {'a': 'C', 'aToken': 'token-C', 'b': 'D', 'bToken': 'token-D'},
      ]);

      expect(pairing.expectedTokenFor('C'), isNull);
      expect(pairing.expectedTokenFor('D'), isNull);
      expect(pairing.rosterEdges, hasLength(1));
    });
  });

  test('encodes and decodes private topology messages', () {
    final roster = RosterMessage(
      edges: const [
        {'a': 'A', 'aToken': 'token-A', 'b': 'B', 'bToken': 'token-B'},
      ],
    );
    final (decodedRoster, _) = SyncProtocol.tryDecode(
      SyncProtocol.encode(roster),
    );
    expect(decodedRoster, isA<RosterMessage>());
    expect((decodedRoster! as RosterMessage).edges.single['b'], 'B');

    final revoke = RevokeMessage(a: 'A', b: 'B');
    final (decodedRevoke, _) = SyncProtocol.tryDecode(
      SyncProtocol.encode(revoke),
    );
    expect(decodedRevoke, isA<RevokeMessage>());
    expect((decodedRevoke! as RevokeMessage).a, 'A');
  });
}
