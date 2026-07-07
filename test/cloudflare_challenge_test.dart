import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/cloudflare_challenge.dart';

void main() {
  group('isCloudflareChallengeResponse', () {
    test('matches Cloudflare 403 challenge body', () {
      expect(
        isCloudflareChallengeResponse(
          403,
          '<html><title>Just a moment...</title><body>Cloudflare cf-ray</body>',
        ),
        isTrue,
      );
    });

    test('does not match ordinary 403 body', () {
      expect(
        isCloudflareChallengeResponse(403, 'Forbidden'),
        isFalse,
      );
    });

    test('does not match successful response', () {
      expect(
        isCloudflareChallengeResponse(
          200,
          '<html><title>Cloudflare protected content</title></html>',
        ),
        isFalse,
      );
    });
  });
}
