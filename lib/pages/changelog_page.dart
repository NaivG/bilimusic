import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bilimusic/models/changelog_entry.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  Future<List<ChangelogEntry>> _loadChangelog() async {
    final String jsonString = await rootBundle.loadString(
      'assets/version.json',
    );
    final Map<String, dynamic> jsonData = json.decode(jsonString);
    final List<dynamic> changelogList = jsonData['changelog'];
    return changelogList.map((item) => ChangelogEntry.fromJson(item)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<ChangelogEntry>>(
        future: _loadChangelog(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          } else if (snapshot.hasData) {
            final changelogEntries = snapshot.data!;
            return ListView.builder(
              itemCount: changelogEntries.length,
              itemBuilder: (context, index) {
                return _buildChangelogItem(changelogEntries[index]);
              },
            );
          } else {
            return const Center(child: Text('暂无数据'));
          }
        },
      ),
    );
  }

  Widget _buildChangelogItem(ChangelogEntry entry) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.version,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  entry.date,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...entry.changes.map(
              (change) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(change)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
