import 'package:flutter/material.dart';
import 'package:bilimusic/utils/network_config.dart';

class CookiePage extends StatelessWidget {
  const CookiePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cookies = NetworkConfig.cookies;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cookie 信息'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomSheet: Container(
        alignment: Alignment.bottomCenter,
        margin: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.1,
        child: Text(
          'Cookie 信息只在本地保存，不会上传到服务器，除非你知道你在做什么，否则请勿分享给任何人。',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      ),
      body: cookies.isEmpty
          ? const Center(
              child: Text(
                '暂无 Cookie 信息',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: cookies.length,
              itemBuilder: (context, index) {
                final entry = cookies.entries.elementAt(index);
                return ListTile(
                  title: Text(entry.key),
                  subtitle: Text(entry.value),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}