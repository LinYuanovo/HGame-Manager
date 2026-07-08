bool isCloudflareChallengeResponse(int statusCode, String body) {
  if (statusCode != 403) return false;
  return looksLikeCloudflareChallenge(body) ||
      RegExp(r'Cloudflare|cf[-_]', caseSensitive: false).hasMatch(body);
}

bool looksLikeCloudflareChallenge(String body) {
  return RegExp(
    r'Just a moment|cf-chl|cf_clearance|cf-ray|Cloudflare Ray ID|cdn-cgi/challenge|Checking your browser|Verify you are human',
    caseSensitive: false,
  ).hasMatch(body);
}
