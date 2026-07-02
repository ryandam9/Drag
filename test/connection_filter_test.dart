import 'package:drag/models/connection.dart';
import 'package:drag/state/connection_filter.dart';
import 'package:flutter_test/flutter_test.dart';

Connection _c(
  String name, {
  String tag = '',
  String host = '',
  String bucket = '',
  String region = '',
  String user = '',
}) => Connection(
  name: name,
  tag: tag,
  host: host,
  bucket: bucket,
  region: region,
  username: user,
  protocol: bucket.isNotEmpty || region.isNotEmpty
      ? Protocol.s3
      : Protocol.sftp,
);

void main() {
  group('connectionMatches', () {
    test('blank query matches everything', () {
      expect(connectionMatches(_c('anything'), ''), isTrue);
      expect(connectionMatches(_c('anything'), '   '), isTrue);
    });

    test('matches name, tag, host and username (case-insensitive)', () {
      final c = _c(
        'Prod SFTP',
        tag: 'Production',
        host: 'box.example.com',
        user: 'deploy',
      );
      expect(connectionMatches(c, 'prod'), isTrue); // name + tag
      expect(connectionMatches(c, 'EXAMPLE'), isTrue); // host
      expect(connectionMatches(c, 'deploy'), isTrue); // username
      expect(connectionMatches(c, 'zzz'), isFalse);
    });

    test('matches S3 bucket and region', () {
      final s3 = _c('data', bucket: 'acme-assets', region: 'eu-west-1');
      expect(connectionMatches(s3, 'acme'), isTrue);
      expect(connectionMatches(s3, 'eu-west'), isTrue);
      expect(connectionMatches(s3, 'us-east'), isFalse);
    });
  });

  group('filterConnections', () {
    test('keeps matching connections in order', () {
      final list = [_c('alpha'), _c('beta', tag: 'prod'), _c('gamma')];
      expect(filterConnections(list, 'a').map((c) => c.name), [
        'alpha',
        'beta',
        'gamma',
      ]);
      expect(filterConnections(list, 'prod').map((c) => c.name), ['beta']);
      expect(filterConnections(list, ''), hasLength(3));
    });
  });

  group('groupConnections', () {
    test(
      'tagged groups sort alphabetically, untagged last, order preserved',
      () {
        final a = _c('a', tag: 'Staging');
        final b = _c('b'); // untagged
        final c = _c('c', tag: 'Production');
        final d = _c('d', tag: 'Production');
        final groups = groupConnections([a, b, c, d]);
        expect(groups.map((g) => g.label), [
          'Production',
          'Staging',
          kUngroupedLabel,
        ]);
        expect(groups[0].items, [c, d]); // insertion order within a group
        expect(groups[1].items, [a]);
        expect(groups.last.items, [b]);
      },
    );

    test('whitespace-only tags count as untagged', () {
      final groups = groupConnections([
        _c('a', tag: '  '),
        _c('b', tag: 'Prod'),
      ]);
      expect(groups.map((g) => g.label), ['Prod', kUngroupedLabel]);
    });

    test('empty input yields no groups', () {
      expect(groupConnections(const []), isEmpty);
    });

    test('all-untagged yields a single Ungrouped group', () {
      final groups = groupConnections([_c('a'), _c('b')]);
      expect(groups, hasLength(1));
      expect(groups.single.label, kUngroupedLabel);
      expect(groups.single.items.map((c) => c.name), ['a', 'b']);
    });
  });
}
