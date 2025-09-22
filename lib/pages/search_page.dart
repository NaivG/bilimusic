import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/components/player_manager.dart';
import 'dart:convert'; // 添加jsonDecode支持
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:bilimusic/utils/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/components/playlist_manager.dart';

class SearchPage extends StatefulWidget {
  final PlayerManager playerManager;

  const SearchPage({super.key, required this.playerManager});

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Music> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage; // 添加错误消息状态
  late PlaylistManager _playlistManager;

  @override
  void initState() {
    super.initState();
    _playlistManager = PlaylistManager();
  }

  // AV号转BV号实现（基于Java代码的Dart实现）
  String av2bv(int aid) {
    const xorCode = 23442827791579;
    const maskCode = 2251799813685247; // 0x1FFFFFFFFFFF
    const base = 58;
    const data = "FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf";

    // 创建初始字符数组
    List<String> bytes = ['B','V','1','0','0','0','0','0','0','0','0','0'];
    int bvIndex = bytes.length - 1;

    // 计算tmp值
    BigInt tmp = (BigInt.one << 51) | BigInt.from(aid);
    tmp = tmp ^ BigInt.from(xorCode);

    // 转换base58
    while (tmp > BigInt.zero) {
      final remainder = tmp % BigInt.from(base);
      bytes[bvIndex] = data[remainder.toInt()];
      tmp = tmp ~/ BigInt.from(base);
      bvIndex--;
    }

    // 交换位置
    _swap(bytes, 3, 9);
    _swap(bytes, 4, 7);

    return bytes.join();
  }

  // 交换列表元素
  void _swap(List<String> list, int i, int j) {
    final temp = list[i];
    list[i] = list[j];
    list[j] = temp;
  }

  Future<void> _searchMusic(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _searchResults = [];
    });

    // 检查是否为BV号或AV号
    final trimmedQuery = query.trim();
    if (trimmedQuery.startsWith("BV1")) {
      // 直接作为BV号处理
      _playByBvid(trimmedQuery);
      return;
    } else if (trimmedQuery.toUpperCase().startsWith("AV")) {
      // 处理AV号
      try {
        // 提取AV号数字部分
        final aidString = trimmedQuery.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
        if (aidString.isEmpty) {
          throw Exception('无效的AV号');
        }

        final aid = int.parse(aidString);
        final bvid = av2bv(aid);
        _playByBvid(bvid);
        return;
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'AV号转换失败: $e';
        });
        return;
      }
    }
    // 实现实际的搜索逻辑
    final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/search/all/v2?keyword=$query'),
        headers: NetworkConfig.biliHeaders,
    );
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['code'] == 0) {
        final List<Music> results = [];
        
        // 解析搜索结果
        for (var result in json['data']['result']) {
          if (result['result_type'] == 'video') {
            for (var item in result['data']) {
              // 处理富文本标题
              String finalTitle = '';
              if (item['title'].contains('<') && item['title'].contains('>')) {
                for (var titlePart in item['title'].split('<')) {
                  if (titlePart.contains('>')) {
                    finalTitle += titlePart.split('>')[1];
                  } else {
                    finalTitle += titlePart;
                  }
                }
              } else {
                finalTitle = item['title'];
              }
              
              // 替换特殊字符
              finalTitle = finalTitle.replaceFirst('&quot;', '"').replaceFirst('&amp;', '&');
              
              // 构建封面URL
              String coverUrl = item['pic'];
              if (!coverUrl.startsWith('http')) {
                coverUrl = 'https:$coverUrl';
              }
              
              results.add(
                Music(
                  id: item['bvid'],
                  title: finalTitle,
                  artist: item['author'],
                  album: item['tag'],
                  coverUrl: coverUrl + "@672w_378h",
                  duration: null, // 移除初始duration
                  audioUrl: '',
                  pages: [],
                ),
              );
            }
          }
        }
        
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '没有搜索到任何视频(っ °Д °;)っ';
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = '网络请求失败: ${response.statusCode}';
      });
    }
  }

  // 通过BV号播放音乐
  Future<void> _playByBvid(String bvid) async {
    try {
      // 创建临时音乐对象
      final tempMusic = Music(
        id: bvid,
        title: '',
        artist: '',
        album: '',
        coverUrl: '',
        duration: null,
        audioUrl: '',
        pages: [],
      );

      // 获取视频详情
      final detailedMusic = await tempMusic.getVideoDetails();

      // 播放音乐
      widget.playerManager.play(detailedMusic);

      // 更新UI显示单个结果
      setState(() {
        _searchResults = [detailedMusic];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '播放失败: $e';
      });
    }
  }

  void _playMusic(Music music) async {
    // 获取视频详情
    final detailedMusic = await music.getVideoDetails();
    
    // 播放音乐
    widget.playerManager.play(detailedMusic);
  }


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('音乐搜索'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '输入音乐名称、艺术家或BV/AV号',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: _searchMusic,
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                      child: Text(_errorMessage ?? '请输入搜索关键词'))
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final music = _searchResults[index];
                          return GestureDetector(
                            onTap: () => _playMusic(music),
                            onLongPress: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (context) => Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: LongPressMenu(
                                    music: music,
                                    playerManager: widget.playerManager,
                                    playlistManager: _playlistManager,
                                  ),
                                ),
                              );
                            },
                            onSecondaryTap: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    contentPadding: const EdgeInsets.all(16.0),
                                    content: LongPressMenu(
                                      music: music,
                                      playerManager: widget.playerManager,
                                      playlistManager: _playlistManager,
                                    ),
                                  );
                                },
                              );
                            },
                            child: ListTile(
                              leading: SizedBox(
                                width: 48,
                                height: 48,
                                child: CachedNetworkImage(
                                  imageUrl: music.safeCoverUrl,
                                  httpHeaders: Map<String, String>.from(NetworkConfig.biliHeaders),
                                  placeholder: (context, url) => Center(child: CircularProgressIndicator()),
                                  errorWidget: (context, url, error) {
                                    // 添加错误占位符并记录错误日志
                                    if (kDebugMode) {
                                      print('Image load error: $error');
                                    }
                                    return const Icon(Icons.image_not_supported_rounded);
                                  },
                                  fit: BoxFit.cover,
                                  cacheManager: imageCacheManager,
                                  cacheKey: music.id,
                                ),
                              ),
                              title: Text(music.title),
                              subtitle: Text('${music.artist} - ${music.album}'),
                            ),
                          );
                        },
                      ),
          ),
          SizedBox(height: 120,),
        ],
      ),
    );
  }
}
