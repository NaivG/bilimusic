import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';

class MusicList extends StatelessWidget {
  final List<Map<String, String>> musics;

  const MusicList({super.key, required this.musics});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: musics.length,
      itemBuilder: (context, index) {
        Map<String, String> music = musics[index];
        return ListTile(
          leading: SizedBox(
            width: 48,  // 建议值：40-60之间
            height: 48,
            child: CachedNetworkImage(
              imageUrl: music['coverUrl'] ?? '',
              // httpHeaders: {
              //   'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
              //   'Referer': 'https://www.bilibili.com'
              // },
              placeholder: (context, url) => CircularProgressIndicator(),
              errorWidget: (context, url, error, stackTrace) {
                // 添加错误占位符并记录错误日志
                if (kDebugMode) {
                  print('Image load error: $error');
                }
                return const Icon(Icons.image_not_supported);
              } as LoadingErrorWidgetBuilder?,
              fit: BoxFit.cover,
            ),
          ),
          title: Text(music['title'] ?? '未知标题'),
          subtitle: Text('${music['artist']} - ${music['album']}'),
          trailing: const Icon(Icons.more_vert),
          onTap: () {
            // Navigator.push(
            //   context,
            //   MaterialPageRoute(
            //     builder: (context) => DetailPage(musicId: music['id'] ?? ''),
            //   ),
            // );
          },
        );
      },
    );
  }
}