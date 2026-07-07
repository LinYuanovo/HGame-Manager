bool isCloudflareChallengeResponse(int statusCode, String body) {
  if (statusCode != 403) return false;
  return RegExp(r'Just a moment|Cloudflare|cf[-_]', caseSensitive: false)
      .hasMatch(body);
}
