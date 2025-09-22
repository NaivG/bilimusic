import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/components/player_manager.dart';
import 'package:bilimusic/components/play_list.dart'; // 导入播放列表组件
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/utils/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/components/playlist_manager.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/utils/recommendation_manager.dart';
import 'package:bilimusic/utils/settings_manager.dart';

class HomePage extends StatefulWidget {
  final PlayerManager playerManager;

  const HomePage({super.key, required this.playerManager});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Music> recommendedList = [];
  late PlaylistManager _playlistManager;
  List<PlaylistInfo> _userPlaylists = [];
  late RecommendationManager _recommendationManager;
  late SettingsManager _settingsManager;
  bool _isLoading = false;
  bool _isPcMode = false;

  @override
  void initState() {
    _settingsManager = SettingsManager();
    _isPcMode = _settingsManager.pcMode;

    super.initState();
    _recommendationManager = RecommendationManager();
    
    // 初始化播放列表管理器
    _playlistManager = PlaylistManager();
    _playlistManager.init().then((_) {
      _loadUserPlaylists();
    });
    
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoading = true;
    });
    
    await _recommendationManager.loadRecommendations();
    setState(() {
      recommendedList = _recommendationManager.recommendedList;
      _isLoading = false;
    });
    
    // 更新猜你喜欢列表
    _updateGuessYouLike();
  }

  Future<void> _refreshRecommendations() async {
    setState(() {
      _isLoading = true;
    });
    
    await _recommendationManager.refreshRecommendations();
    setState(() {
      recommendedList = _recommendationManager.recommendedList;
      _isLoading = false;
    });
  }

  Future<void> _updateGuessYouLike() async {
    // 在后台更新猜你喜欢列表
    await _recommendationManager.updateGuessYouLike(widget.playerManager.playHistory);
  }

  /// 加载用户自定义播放列表
  Future<void> _loadUserPlaylists() async {
    try {
      final playlists = await _playlistManager.getAllPlaylists();
      setState(() {
        _userPlaylists = playlists;
      });
    } catch (e) {
      debugPrint('Failed to load user playlists: $e');
    }
  }

  /// 创建新的播放列表
  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建新歌单'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '歌单名称',
                hintText: '请输入歌单名称',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入歌单名称';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final playlistName = controller.text.trim();
                  try {
                    await _playlistManager.createPlaylist(playlistName);
                    Navigator.of(context).pop();
                    await _loadUserPlaylists();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已创建歌单"$playlistName"')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('创建歌单失败: $e')),
                    );
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  void _playMusic(Music music) async {
    // 获取视频详情
    final detailedMusic = await music.getVideoDetails();
    
    // 播放音乐
    widget.playerManager.play(detailedMusic);
    
    // Navigator.pushNamed(context, '/detail', arguments: detailedMusic.id);
  }

  Widget _buildMusicCard(Music music, {bool isPcMode = false}) {
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
      child: _isPcMode
          ? _buildPcMusicCard(music)
          : _buildMobileMusicCard(music),
    );
  }

  Widget _buildMobileMusicCard(Music music) {
    return Container(
      width: 120,
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: music.safeCoverUrl,
              httpHeaders: NetworkConfig.biliHeaders,
              placeholder: (context, url) => Container(
                color: Colors.grey[300],
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.music_note),
              ),
              fit: BoxFit.cover,
              height: 120,
              cacheManager: imageCacheManager,
              cacheKey: music.id,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            music.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${music.artist} - ${music.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPcMusicCard(Music music) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面图片
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: CachedNetworkImage(
              imageUrl: music.safeCoverUrl,
              httpHeaders: NetworkConfig.biliHeaders,
              placeholder: (context, url) => Container(
                color: Colors.grey[300],
                height: 140,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                height: 140,
                child: const Icon(Icons.music_note),
              ),
              fit: BoxFit.cover,
              height: 140,
              width: double.infinity,
              cacheManager: imageCacheManager,
              cacheKey: music.id,
            ),
          ),

          // 音乐信息
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  music.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  music.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isPcMode) {
      return _buildPcLayout(context);
    } else {
      return _buildMobileLayout(context);
    }
  }
  // PC 模式布局
  Widget _buildPcLayout(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 搜索栏
          SliverAppBar(
            floating: true,
            snap: true,
            automaticallyImplyLeading: false,
            title: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: '搜索音乐、视频、用户...',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onTap: () {
                  Navigator.pushNamed(context, '/search', arguments: widget.playerManager);
                },
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _refreshRecommendations,
              ),
            ],
          ),

          // 推荐音乐区域
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 推荐音乐标题
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '推荐音乐',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _refreshRecommendations,
                        child: _isLoading
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('换一批'),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  // 推荐音乐网格
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                      childAspectRatio: (MediaQuery.of(context).size.width / 1290),
                    ),
                    itemCount: recommendedList.length,
                    itemBuilder: (context, index) {
                      final music = recommendedList[index];
                      return _buildMusicCard(music, isPcMode: true);
                    },
                  ),
                ],
              ),
            ),
          ),

          // 猜你喜欢区域
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 猜你喜欢标题
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '猜你喜欢',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '上次更新: ${_recommendationManager.lastGuessUpdated}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  // 猜你喜欢网格
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                      childAspectRatio: (MediaQuery.of(context).size.width / 1290),
                    ),
                    itemCount: _recommendationManager.guessYouLikeList.length,
                    itemBuilder: (context, index) {
                      final music = _recommendationManager.guessYouLikeList[index];
                      return _buildMusicCard(music, isPcMode: true);
                    },
                  ),
                ],
              ),
            ),
          ),

          // 最近播放区域
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 最近播放标题
                  Text(
                    '最近播放',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  // 最近播放列表
                  widget.playerManager.playHistory.isEmpty
                      ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        '没有找到播放历史(っ °Д °;)っ',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                      : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                      childAspectRatio: (MediaQuery.of(context).size.width / 1290),
                    ),
                    itemCount: widget.playerManager.playHistory.length > 10
                        ? 10
                        : widget.playerManager.playHistory.length,
                    itemBuilder: (context, index) {
                      final music = widget.playerManager.playHistory[index];
                      return _buildMusicCard(music, isPcMode: true);
                    },
                  ),
                  SizedBox(height: 120,),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 移动端布局
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('BiliMusic', style: TextStyle(fontFamily: 'CabinSketch', fontWeight: FontWeight.w600,)),
            floating: true,
            snap: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  Navigator.pushNamed(context, '/search', arguments: widget.playerManager);
                },
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 推荐音乐标题
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '推荐音乐',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: _isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.refresh),
                          onPressed: _isLoading ? null : _refreshRecommendations,
                        ),
                      ],
                    ),
                  ),

                  // 推荐音乐列表
                  SizedBox(
                    height: 200,
                    child: recommendedList.isEmpty
                        ? const Center(
                      child: Text(
                        '暂无推荐音乐',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    )
                        : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      scrollDirection: Axis.horizontal,
                      itemCount: recommendedList.length,
                      itemBuilder: (context, index) {
                        final music = recommendedList[index];
                        return _buildMusicCard(music, isPcMode: false);
                      },
                    ),
                  ),

                  // 猜你喜欢标题
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '猜你喜欢',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text( // 显示上次更新时间
                            _recommendationManager.lastGuessUpdated,
                            style: const TextStyle(
                              fontSize: 14,
                            )
                        )
                      ],
                    ),
                  ),

                  // 猜你喜欢列表
                  SizedBox(
                    height: 200,
                    child: _recommendationManager.guessYouLikeList.isEmpty
                        ? const Center(
                      child: Text(
                        '暂无推荐',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    )
                        : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      scrollDirection: Axis.horizontal,
                      itemCount: _recommendationManager.guessYouLikeList.length,
                      itemBuilder: (context, index) {
                        final music = _recommendationManager.guessYouLikeList[index];
                        return _buildMusicCard(music, isPcMode: false);
                      },
                    ),
                  ),

                  // 最近播放标题
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Text(
                      '最近播放',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // 最近播放列表（最多显示10个）
                  SizedBox(
                    height: 200,
                    child: widget.playerManager.playHistory.isEmpty
                        ? Center(
                      child: Text(
                        '没有找到播放历史(っ °Д °;)っ',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    )
                        : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.playerManager.playHistory.length > 10
                          ? 10
                          : widget.playerManager.playHistory.length,
                      itemBuilder: (context, index) {
                        final music = widget.playerManager.playHistory[index];
                        return _buildMusicCard(music, isPcMode: false);
                      },
                    ),
                  ),
                  SizedBox(height: 120,),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}