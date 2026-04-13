import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bilimusic/models/changelog_entry.dart';

class UpdateAvailableDialog extends StatelessWidget {
  final String newVersion;
  final List<ChangelogEntry> changelog;

  const UpdateAvailableDialog({
    super.key,
    required this.newVersion,
    required this.changelog,
  });

  static Future<void> show(
    BuildContext context, {
    required String newVersion,
    required List<ChangelogEntry> changelog,
  }) {
    return showDialog(
      context: context,
      builder: (context) => UpdateAvailableDialog(
        newVersion: newVersion,
        changelog: changelog,
      ),
    );
  }

  Future<void> _launchUpdateUrl() async {
    final url = Uri.parse('https://github.com/NaivG/bilimusic/releases');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.system_update, size: 48),
      title: Text('发现新版本 v$newVersion'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('以下是本次更新内容：'),
            const SizedBox(height: 12),
            ...changelog.map(
              (entry) => _buildChangelogItem(entry),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('暂不更新'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _launchUpdateUrl();
          },
          child: const Text('立即更新'),
        ),
      ],
    );
  }

  Widget _buildChangelogItem(ChangelogEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${entry.version}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.date,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...entry.changes.map(
            (change) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Text(
                      change,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}