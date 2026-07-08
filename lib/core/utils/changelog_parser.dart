class ChangelogEntry {
  final String version;
  final String? date;
  final String body;

  const ChangelogEntry({
    required this.version,
    required this.body,
    this.date,
  });
}

List<ChangelogEntry> parseChangelogEntries(String markdown) {
  final lines = markdown.split(RegExp(r'\r?\n'));
  final entries = <ChangelogEntry>[];
  String? version;
  String? date;
  final body = <String>[];

  void flush() {
    if (version == null) return;
    entries.add(
      ChangelogEntry(
        version: version,
        date: date,
        body: body.join('\n').trim(),
      ),
    );
    body.clear();
  }

  for (final line in lines) {
    final match =
        RegExp(r'^##\s+v?([^\s(]+)(?:\s+\(([^)]+)\))?').firstMatch(line.trim());
    if (match != null) {
      flush();
      version = match.group(1);
      date = match.group(2);
    } else if (version != null) {
      body.add(line);
    }
  }
  flush();
  return entries;
}
