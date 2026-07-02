import 'package:drag/screens/connection_manager_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateS3Endpoint', () {
    test('accepts blank (optional → AWS default)', () {
      expect(validateS3Endpoint(''), isNull);
      expect(validateS3Endpoint('   '), isNull);
    });

    test('accepts a bare host and host:port', () {
      expect(validateS3Endpoint('s3.amazonaws.com'), isNull);
      expect(validateS3Endpoint('minio.example.com:9000'), isNull);
      expect(validateS3Endpoint('localhost:4566'), isNull);
      expect(
        validateS3Endpoint('https://minio.local:9000'),
        isNull,
      ); // scheme tolerated
    });

    test('rejects a path or trailing slash', () {
      expect(validateS3Endpoint('minio.local:9000/bucket'), isNotNull);
      expect(validateS3Endpoint('s3.amazonaws.com/'), isNotNull);
    });

    test('rejects a bad port', () {
      expect(validateS3Endpoint('host:0'), isNotNull);
      expect(validateS3Endpoint('host:70000'), isNotNull);
      expect(validateS3Endpoint('host:abc'), isNotNull);
    });

    test('rejects spaces and invalid host characters', () {
      expect(validateS3Endpoint('bad host'), isNotNull);
      expect(validateS3Endpoint('ho_st!'), isNotNull);
    });
  });
}
