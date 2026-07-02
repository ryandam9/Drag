import 'dart:typed_data';

import 'package:drag/fs/sftp_backend.dart';
import 'package:drag/models/connection.dart';
import 'package:flutter_test/flutter_test.dart';

Connection _conn() => Connection(
  name: 'h',
  protocol: Protocol.sftp,
  host: 'example.com',
  port: 22,
  username: 'deploy',
  auth: AuthMethod.password,
);

void main() {
  group('SftpBackend.dispose', () {
    test(
      'a disposed backend fails fast instead of reusing a dead session',
      () async {
        final b = SftpBackend(_conn());
        b.dispose();

        // Every session-backed operation must trip the guard with a clear error
        // — not hang on (or silently re-open) a torn-down SSH connection.
        await expectLater(
          b.list('/'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
        await expectLater(b.openRead('/f'), throwsStateError);
        await expectLater(
          b.write('/f', const Stream<Uint8List>.empty(), 0),
          throwsStateError,
        );
        await expectLater(b.makeDir('/d'), throwsStateError);
        await expectLater(b.delete('/f', isDir: false), throwsStateError);
      },
    );

    test(
      'sizeOf on a disposed backend reports "unknown" rather than throwing',
      () async {
        // sizeOf's contract is null-on-failure (post-transfer verification treats
        // it as "couldn't confirm"), so the dispose guard is swallowed there.
        final b = SftpBackend(_conn());
        b.dispose();
        expect(await b.sizeOf('/f'), isNull);
      },
    );

    test('dispose is idempotent', () {
      final b = SftpBackend(_conn());
      b.dispose();
      b.dispose(); // second call must not throw on the nulled-out session
    });
  });
}
