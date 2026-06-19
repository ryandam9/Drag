import 'package:drag/fs/aws/sigv4.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AWS Signature V4 signing', () {
    test('signing key matches the AWS-documented test vector', () {
      // From the official AWS docs ("Examples of how to derive a signing key
      // for Signature Version 4"): the derived key for this input is a known,
      // published constant — proving our HMAC chain matches AWS exactly.
      final key = SigV4Signer.deriveSigningKey(
        'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
        '20150830',
        'us-east-1',
        'iam',
      );
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, 'c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9');
    });

    test('Authorization header is well-formed and deterministic', () {
      final signer = SigV4Signer(
        credentials: const AwsCredentials('AKIDEXAMPLE', 'secret'),
        region: 'us-east-1',
      );
      final headers = signer.sign(
        method: 'GET',
        host: 's3.us-east-1.amazonaws.com',
        canonicalUri: '/my-bucket',
        query: const {'list-type': '2', 'prefix': 'logs/'},
        headers: const {},
        payloadHash: emptyBodySha256,
        now: DateTime.utc(2025, 6, 19, 8, 14, 2),
      );

      final auth = headers['Authorization']!;
      expect(auth, startsWith('AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20250619/us-east-1/s3/aws4_request'));
      expect(auth, contains('SignedHeaders=host;x-amz-content-sha256;x-amz-date'));
      expect(headers['x-amz-date'], '20250619T081402Z');
      expect(headers['x-amz-content-sha256'], emptyBodySha256);
    });

    test('session token is signed when present', () {
      final signer = SigV4Signer(
        credentials: const AwsCredentials('AKID', 'secret', sessionToken: 'TOKEN123'),
        region: 'eu-west-1',
      );
      final headers = signer.sign(
        method: 'GET',
        host: 's3.eu-west-1.amazonaws.com',
        canonicalUri: '/b',
        query: const {},
        headers: const {},
        payloadHash: emptyBodySha256,
        now: DateTime.utc(2025, 1, 1),
      );
      expect(headers['x-amz-security-token'], 'TOKEN123');
      expect(headers['Authorization'], contains('x-amz-security-token'));
    });

    test('uri-encoding preserves slashes in keys but encodes spaces', () {
      expect(awsUriEncode('logs/my file.txt'), 'logs/my%20file.txt');
      expect(awsUriEncode('a/b', encodeSlash: true), 'a%2Fb');
    });
  });
}
