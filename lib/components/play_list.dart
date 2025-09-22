import 'package:flutter/material.dart';
import 'package:bilimusic/components/player_manager.dart';

class PlayListSheet extends StatefulWidget {
  final PlayerManager playerManager;
  final Function(int) onTrackSelect;

  const PlayListSheet({
    super.key,
    required this.playerManager,
    required this.onTrackSelect,
  });

  @override
  State<PlayListSheet> createState() => _PlayListSheetState();
}

class _PlayListSheetState extends State<PlayListSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Text(
            '播放列表',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Divider(),
          if (widget.playerManager.playList.isEmpty)
            Text('播放列表为空'),
          Expanded(
            child: ListView.builder(
              itemCount: widget.playerManager.playList.length,
              itemBuilder: (context, index) {
                final music = widget.playerManager.playList[index];
                return ListTile(
                  title: Text(music.title),
                  subtitle: Text('${music.artist} - ${music.album}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          widget.playerManager.isFavorite(music) 
                            ? Icons.favorite 
                            : Icons.favorite_border,
                          color: widget.playerManager.isFavorite(music) 
                            ? Colors.red 
                            : null,
                        ),
                        onPressed: () async {
                          if (widget.playerManager.isFavorite(music)) {
                            await widget.playerManager.removeFromFavorites(music);
                          } else {
                            await widget.playerManager.addToFavorites(music);
                          }
                          setState(() {}); // 更新UI
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () {
                          // 实现从播放列表中移除音乐的功能
                          final playlist = widget.playerManager.playList;
                          if (index >= 0 && index < playlist.length) {
                            final musicToRemove = playlist[index];
                            widget.playerManager.removeFromPlayList(musicToRemove).then((_) {
                              setState(() {}); // 更新UI
                              
                              // 显示提示信息
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已从播放列表中移除"${musicToRemove.title}"')),
                              );
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () => widget.onTrackSelect(index),
                );
              },
            ),
          ),
        ],

      ),
    );
  }
}