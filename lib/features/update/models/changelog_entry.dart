class ChangelogEntry {
  final String version;
  final String date;
  final List<String> changes;

  ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) {
    return ChangelogEntry(
      version: json['version'] as String? ?? '',
      date: json['date'] as String? ?? '',
      changes: json['changes'] != null
          ? List<String>.from(json['changes'] as List)
          : [],
    );
  }
}
