/// Turning messy pasted text into a clean list of downloadable links.
library;

final _urlPattern = RegExp(
  r'''(?:https?://|www\.)[^\s<>"'`(){}\[\]]+''',
  caseSensitive: false,
);

/// Finds every http(s) link in [text], in order, without duplicates.
///
/// Handles the ways people actually paste: one per line, comma separated,
/// buried in a chat message, wrapped in markdown `[label](url)` or `<url>`.
List<String> extractLinks(String text) {
  final seen = <String>{};
  final links = <String>[];
  for (final match in _urlPattern.allMatches(text)) {
    var url = match.group(0)!;
    // Trailing punctuation is almost always sentence punctuation, not URL.
    url = url.replaceFirst(RegExp(r'''[.,;:!?'"»)\]]+$'''), '');
    if (url.toLowerCase().startsWith('www.')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) continue;
    final key = canonicalKey(url);
    if (seen.add(key)) links.add(url);
  }
  return links;
}

/// A loose identity for a link, so the same video pasted twice (with
/// tracking params, a trailing slash or `youtu.be` vs `youtube.com`) is
/// recognised as a duplicate.
String canonicalKey(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return url.trim();
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  if (host.startsWith('m.')) host = host.substring(2);

  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    return 'yt:${uri.pathSegments.first}';
  }
  if (host.endsWith('youtube.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && uri.path == '/watch') return 'yt:$v';
    final segs = uri.pathSegments;
    if (segs.length >= 2 && (segs[0] == 'shorts' || segs[0] == 'live' || segs[0] == 'embed')) {
      return 'yt:${segs[1]}';
    }
    final list = uri.queryParameters['list'];
    if (list != null && uri.path == '/playlist') return 'ytpl:$list';
  }

  const noise = {
    'si', 'feature', 'utm_source', 'utm_medium', 'utm_campaign', 'utm_term',
    'utm_content', 'igsh', 'igshid', 's', 't', 'ref', 'ref_src', 'fbclid',
    'pp', 'is_from_webapp', 'sender_device',
  };
  final params = Map.of(uri.queryParameters)..removeWhere((k, _) => noise.contains(k));
  final keys = params.keys.toList()..sort();
  final query = keys.map((k) => '$k=${params[k]}').join('&');
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  return '$host$path${query.isEmpty ? '' : '?$query'}';
}

class Site {
  const Site(this.key, this.label);
  final String key;
  final String label;
}

const _sites = <(List<String>, Site)>[
  (['youtube.com', 'youtu.be', 'music.youtube.com'], Site('youtube', 'YouTube')),
  (['x.com', 'twitter.com'], Site('x', 'X')),
  (['instagram.com'], Site('instagram', 'Instagram')),
  (['threads.net', 'threads.com'], Site('threads', 'Threads')),
  (['tiktok.com'], Site('tiktok', 'TikTok')),
  (['vimeo.com'], Site('vimeo', 'Vimeo')),
  (['twitch.tv'], Site('twitch', 'Twitch')),
  (['reddit.com', 'redd.it'], Site('reddit', 'Reddit')),
  (['facebook.com', 'fb.watch'], Site('facebook', 'Facebook')),
  (['soundcloud.com'], Site('soundcloud', 'SoundCloud')),
  (['bandcamp.com'], Site('bandcamp', 'Bandcamp')),
  (['dailymotion.com', 'dai.ly'], Site('dailymotion', 'Dailymotion')),
  (['bilibili.com', 'b23.tv'], Site('bilibili', 'Bilibili')),
  (['archive.org'], Site('archive', 'Internet Archive')),
  (['bsky.app'], Site('bluesky', 'Bluesky')),
  (['linkedin.com'], Site('linkedin', 'LinkedIn')),
  (['pinterest.com', 'pin.it'], Site('pinterest', 'Pinterest')),
  (['tumblr.com'], Site('tumblr', 'Tumblr')),
  (['kick.com'], Site('kick', 'Kick')),
  (['rumble.com'], Site('rumble', 'Rumble')),
];

Site detectSite(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return const Site('unknown', 'Link');
  for (final (hosts, site) in _sites) {
    if (hosts.any((h) => host == h || host.endsWith('.$h'))) return site;
  }
  final bare = host.startsWith('www.') ? host.substring(4) : host;
  return Site('generic', bare);
}

/// Heuristic: does this URL point at many videos rather than one?
/// Used only for an optimistic label while metadata is loading.
bool looksLikeCollection(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments;
  if (host.contains('youtube.com')) {
    if (uri.path == '/playlist') return true;
    if (segs.isNotEmpty && (segs[0].startsWith('@') || segs[0] == 'channel' || segs[0] == 'c' || segs[0] == 'user')) {
      return true;
    }
  }
  return false;
}
