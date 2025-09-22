import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/components/play_list.dart';
import 'package:bilimusic/components/player_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:bilimusic/utils/settings_manager.dart';
import 'package:bilimusic/utils/netease_music_api.dart';
import 'package:bilimusic/utils/lyric_parser.dart';
import 'dart:ui';

// 歌词信息类
class LyricInfo {
  final String id;
  final String name;
  final String artist;

  LyricInfo({
    required this.id,
    required this.name,
    required this.artist,
  });

  @override
  String toString() {
    return '$name - $artist';
  }
}

class DetailPage extends StatefulWidget {
  final PlayerManager playerManager;

  const DetailPage({
    super.key,
    required this.playerManager,
  });

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with TickerProviderStateMixin {
  late model.Music _music;
  int _currentPageIndex = 0;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isPlaying = true;
  late SettingsManager _settingsManager;
  final bool _isPcPlatform = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // 歌词相关变量
  List<LyricInfo> _lyricOptions = [];
  String? _selectedLyricId;
  LyricParser? _lyricParser;
  bool _isLoadingLyrics = false;
  late ScrollController _lyricScrollController;
  LyricLine? _lastCurrentLine;

  // 背景颜色相关变量
  Color? _backgroundColor;
  Color? _targetBackgroundColor;
  late AnimationController _colorAnimationController;
  late Animation<Color?> _colorAnimation;

  // 播放控制相关变量
  late Function(AudioState) _stateListener;
  late Function(Duration) _positionListener;
  late Function(PlayMode) _playModeListener;
  late IconData _playModeIcon;

  @override
  void initState() {
    // 初始化设置管理器
    _settingsManager = SettingsManager();

    super.initState();

    // 初始化动画控制器
    _colorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // 初始化播放模式图标
    _playModeIcon = Icons.repeat;

    // 初始化滚动控制器
    _lyricScrollController = ScrollController();

    // 初始化音乐信息
    final currentMusic = widget.playerManager.currentMusic ?? model.Music(
      id: '',
      title: '未知标题',
      artist: '未知艺术家',
      album: '未知专辑',
      coverUrl: '',
      duration: Duration.zero,
      audioUrl: '',
      pages: [],
    );
    _music = currentMusic;
    _duration = currentMusic.duration;

    // 提取初始背景颜色
    _extractBackgroundColor(_music.coverUrl);

    // 创建绑定监听器的函数
    _stateListener = (state) {
      if (mounted) {
        final updatedMusic = widget.playerManager.currentMusic ?? _music;
        if (updatedMusic.id != _music.id) {
          // 音乐切换时更新背景颜色
          _updateBackgroundColor(updatedMusic.coverUrl);
        }
        setState(() {
          _isPlaying = state == AudioState.playing;
          _music = updatedMusic;
          _duration = updatedMusic.duration;
        });
      }
    };

    _positionListener = (position) {
      if (mounted) {
        final updatedMusic = widget.playerManager.currentMusic ?? _music;
        setState(() {
          _position = position;
          _music = updatedMusic;
          _duration = updatedMusic.duration;
        });

        // 自动滚动歌词
        _scrollToCurrentLyric();
      }
    };

    _playModeListener = (playMode) {
      if (mounted) {
        final updatedMusic = widget.playerManager.currentMusic ?? _music;
        setState(() {
          // 更新播放模式图标
          switch (playMode) {
            case PlayMode.sequential:
              _playModeIcon = Icons.repeat;
            case PlayMode.loop:
              _playModeIcon = Icons.repeat_one;
            case PlayMode.shuffle:
              _playModeIcon = Icons.shuffle;
          }
          _music = updatedMusic;
        });
      }
    };

    // 添加播放状态监听器
    widget.playerManager.addStateListener(_stateListener);
    // 添加播放位置监听器
    widget.playerManager.addPositionListener(_positionListener);
    // 添加播放模式监听器
    widget.playerManager.addPlayModeListener(_playModeListener);

    // 初始化歌词选项
    _initLyricOptions();
  }

  /// 初始化歌词选项
  void _initLyricOptions() async {
    setState(() {
      _isLoadingLyrics = true;
    });

    try {
      // 添加本地缓存选项
      final localOption = LyricInfo(
        id: 'local',
        name: _music.title,
        artist: _music.artist,
      );

      // 搜索网易云音乐选项
      final neteaseOptions = await NeteaseMusicApi.searchMusic(_music.title);

      setState(() {
        _lyricOptions = [localOption, ...neteaseOptions.map((info) =>
            LyricInfo(id: info.id, name: info.name, artist: info.artist))];
        _isLoadingLyrics = false;
      });
    } catch (e) {
      print('获取歌词选项失败: $e');
      // 至少添加本地选项
      setState(() {
        _lyricOptions = [
          LyricInfo(
            id: 'local',
            name: _music.title,
            artist: _music.artist,
          )
        ];
        _isLoadingLyrics = false;
      });
    }
  }

  /// 加载歌词内容
  void _loadLyric(String id) async {
    setState(() {
      _selectedLyricId = id;
      _lyricParser = null;
      _lastCurrentLine = null;

      // 重置滚动位置
      if (_lyricScrollController.hasClients) {
        _lyricScrollController.jumpTo(0);
      }
    });

    try {
      String? lyric;
      if (id == 'local') {
        // 本地歌词，这里可以实现本地歌词加载逻辑
        lyric = '[00:00.00]暂无本地歌词\n[00:03.00]请从网易云音乐选择歌词';
      } else {
        // 从网易云获取歌词
        lyric = await NeteaseMusicApi.getLyric(id);
      }

      if (mounted && lyric != null) {
        final parser = LyricParser.parse(lyric);
        if (mounted) {
          setState(() {
            _lyricParser = parser;
          });
        }
      }
    } catch (e) {
      print('加载歌词失败: $e');
      if (mounted) {
        setState(() {
          _lyricParser = LyricParser.parse('[00:00.00]加载歌词失败');
        });
      }
    }
  }

  /// 提取背景颜色
  void _extractBackgroundColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;

    final color = await compute(_extractColorFromUrl, imageUrl);
    if (mounted) {
      setState(() {
        _backgroundColor = color?.withOpacity(0.3);
      });
    }
  }

  /// 更新背景颜色（当音乐切换时）
  void _updateBackgroundColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;

    final color = await compute(_extractColorFromUrl, imageUrl);
    if (mounted) {
      setState(() {
        _targetBackgroundColor = color?.withOpacity(0.3);

        // 创建颜色动画
        _colorAnimation = ColorTween(
          begin: _backgroundColor,
          end: _targetBackgroundColor,
        ).animate(CurvedAnimation(
          parent: _colorAnimationController,
          curve: Curves.easeInOut,
        ));

        // 启动动画
        _colorAnimationController.forward(from: 0.0);
      });
    }
  }

  /// 在独立的函数中提取颜色，以便使用compute进行隔离计算
  static Future<Color?> _extractColorFromUrl(String imageUrl) async {
    return await ColorExtractor.extractColorFromUrl(imageUrl);
  }

  @override
  void dispose() {
    _lyricScrollController.dispose();
    _colorAnimationController.dispose();
    // 移除播放状态监听器
    widget.playerManager.removeStateListener(_stateListener);
    // 移除播放位置监听器
    widget.playerManager.removePositionListener(_positionListener);
    // 移除播放模式监听器
    widget.playerManager.removePlayModeListener(_playModeListener);
    super.dispose();
  }

  void _playTrack(int index) {
    // 实现播放指定音轨的逻辑
    if (index >= 0 && index < _music.pages.length) {
      final selectedTrack = _music.pages[index];

      // 创建一个新的Music对象包含当前选中的页面
      final trackMusic = model.Music(
          id: _music.id,
          title: '${_music.title} - ${selectedTrack.part}',
          artist: _music.artist,
          album: _music.album,
          coverUrl: _music.coverUrl,
          duration: Duration(seconds: int.parse(selectedTrack.duration)),
          audioUrl: '',
          pages: [_music.pages[index]]
      );

      widget.playerManager.play(trackMusic);
    }
  }

  void _openPlayList() {
    showModalBottomSheet(
      context: context,
      builder: (context) => PlayListSheet(
        playerManager: widget.playerManager,
        onTrackSelect: (index) {
          widget.playerManager.playAtIndex(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  // 检查是否应该启用平板模式
  bool _isTabletMode(BuildContext context) {
    switch (_settingsManager.tabletMode) {
      case 'on':
        return true;
      case 'off':
        return false;
      case 'auto':
      default:
      // 自动模式：检查屏幕宽度是否大于600dp（平板阈值）
        return MediaQuery.of(context).size.shortestSide >= 600;
    }
  }

  /// 自动滚动到当前歌词行
  void _scrollToCurrentLyric() {
    if (_lyricParser == null || _lyricParser!.lines.isEmpty) return;

    final currentLine = _lyricParser!.getCurrentLine(_position.inMilliseconds / 1000);

    // 只有当当前行发生变化时才滚动
    if (currentLine != null && currentLine != _lastCurrentLine) {
      _lastCurrentLine = currentLine;

      // 找到当前行在列表中的索引
      final index = _lyricParser!.lines.indexOf(currentLine);
      if (index != -1) {
        // 计算滚动位置，使当前行居中显示
        final lineHeight = 35.0;
        final viewportHeight = MediaQuery.of(context).size.height * 0.4; // 歌词显示区域高度
        final targetPosition = index * lineHeight - (viewportHeight / 2) + (lineHeight / 2);

        // 滚动到目标位置
        _lyricScrollController.animateTo(
          targetPosition.clamp(0.0, _lyricScrollController.position.maxScrollExtent),
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTabletMode(context);

    // 确定当前使用的背景颜色
    Color? currentBackgroundColor = _colorAnimationController.isAnimating
        ? _colorAnimation.value
        : (_targetBackgroundColor ?? _backgroundColor);

    var appBar = AppBar(
      title: Text('音乐详情'),
      leading: IconButton(
        icon: Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Icon(
            widget.playerManager.isFavorite(_music)
                ? Icons.favorite
                : Icons.favorite_border,
            color: widget.playerManager.isFavorite(_music)
                ? Colors.red
                : null,
          ),
          onPressed: () async {
            if (widget.playerManager.isFavorite(_music)) {
              await widget.playerManager.removeFromFavorites(_music);
            } else {
              await widget.playerManager.addToFavorites(_music);
            }
            setState(() {
              _music = _music.copyWith(isFavorite: !widget.playerManager.isFavorite(_music));
            });
          },
        ),
        IconButton(
          icon: Icon(Icons.share),
          onPressed: () {
            final String shareText =
                '由 BiliMusic 分享：${_music.title}\n'
                'https://b23.tv/${_music.id}';
            SharePlus.instance.share(
                ShareParams(
                  text: shareText,
                  sharePositionOrigin: Rect.fromCenter(
                    center: Offset.zero,
                    width: 100,
                    height: 100,
                  ),
                )
            );
          },
        ),
      ],
      backgroundColor: _settingsManager.fluidBackground
          ? currentBackgroundColor?.withOpacity(0.7)
          : Theme.of(context).canvasColor,
    );

    return Scaffold(
      appBar: _isPcPlatform
              ?  PreferredSize(
                  preferredSize: const Size.fromHeight(50.0),
                  child: MoveWindow(
                    child: appBar,
                  )
              )
              : PreferredSize(
                  preferredSize: const Size.fromHeight(50.0),
                  child: appBar
              ),
      body: Stack(
        children: [
          // 模糊背景 (根据设置决定是否显示)
          if (_settingsManager.fluidBackground && currentBackgroundColor != null) ...[
            Positioned.fill(
              child: Container(
                color: currentBackgroundColor,
              ),
            ),
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 200, sigmaY: 200),
                child: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: CachedNetworkImageProvider(_music.coverUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (isTablet)
            _buildTabletLayout()
          else
            _buildMobileLayout(),
        ],
      ),
    );
  }

  // 构建手机布局
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 封面图片区域
          Container(
            width: MediaQuery.of(context).size.width * 0.6,
            height: MediaQuery.of(context).size.width * 0.6,
            margin: EdgeInsets.only(top: 20, bottom: 20),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
              borderRadius: BorderRadius.circular(20),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: _music.coverUrl,
                placeholder: (context, url) => Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) => Icon(Icons.error_outline),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 音乐标题和艺术家信息
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(
                  _music.title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  '${_music.artist} - ${_music.album}',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width > 600 ? 20 : 18,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),

                // 分P选择下拉框
                if (_music.pages.isNotEmpty) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    width: double.infinity,
                    child: Text(
                      '分P选择',
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width > 600 ? 20 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    margin: EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _currentPageIndex,
                        items: _music.pages.map((page) {
                          final index = _music.pages.indexOf(page);
                          return DropdownMenuItem(
                            value: index,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(
                                'P${index + 1}: ${page.part}',
                                style: TextStyle(
                                  fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: _onPageChange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                //
                // // 歌词选择和显示区域
                // _buildLyricSection(),

                // 播放控制区域
                _buildControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建平板布局
  Widget _buildTabletLayout() {
    return Row(
      children: [
        // 左侧：封面、音乐信息和播放控制区域
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // 封面图片区域（平板模式下更大）
                Container(
                  width: MediaQuery.of(context).size.width * 0.22,
                  height: MediaQuery.of(context).size.width * 0.22,
                  margin: EdgeInsets.only(top: 20, bottom: 20),
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: _music.coverUrl,
                      placeholder: (context, url) => Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => Icon(Icons.error_outline),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                // 音乐标题和艺术家信息
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Text(
                        _music.title,
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width > 1000 ? 28 : 24,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        '${_music.artist} - ${_music.album}',
                        style: TextStyle(
                          fontSize: MediaQuery.of(context).size.width > 1000 ? 22 : 18,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 20),

                      // 分P选择下拉框
                      if (_music.pages.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          width: double.infinity,
                          child: Text(
                            '分P选择',
                            style: TextStyle(
                              fontSize: MediaQuery.of(context).size.width > 1000 ? 24 : 20,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                        SizedBox(height: 10),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          margin: EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _currentPageIndex,
                              items: _music.pages.map((page) {
                                final index = _music.pages.indexOf(page);
                                return DropdownMenuItem(
                                  value: index,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Text(
                                      'P${index + 1}: ${page.part}',
                                      style: TextStyle(
                                        fontSize: MediaQuery.of(context).size.width > 1000 ? 20 : 16,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: _onPageChange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 播放控制区域（平板）
                _buildTabletControlTop(),
              ],
            ),
          ),
        ),
        // 右侧：歌词显示区域
        Expanded(
          flex: 1,
          child: Column(
            children: [
              Expanded(
                child: _buildLyricSection(),
              ),
              _buildTabletControlBottom(),
            ],
          ),
        ),
      ],
    );
  }

  // 构建歌词选择和显示区域
  Widget _buildLyricSection() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '歌词(Beta)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),

          // 歌词选项下拉框
          if (_isLoadingLyrics)
            Center(child: CircularProgressIndicator())
          else
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedLyricId,
                  hint: Text('选择歌词'),
                  items: _lyricOptions.map((option) {
                    return DropdownMenuItem<String>(
                      value: option.id,
                      child: Text(
                        option.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    if (id != null) {
                      _loadLyric(id);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

          SizedBox(height: 20),

          // 歌词显示区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _buildLyricContent(),
            ),
          ),
          SizedBox(height: 20),

          // 新增：歌词同步开关
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.equalizer,
                color: Theme.of(context).primaryColor,
              ),
              Switch(
                value: _isLyricSyncEnabled,
                onChanged: (value) {
                  setState(() {
                    _isLyricSyncEnabled = value;
                  });
                },
                activeColor: Theme.of(context).primaryColor,
              ),
              Text(
                '歌词同步',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 新增状态变量：歌词同步开关
  bool _isLyricSyncEnabled = true;

  // 构建歌词内容显示
  Widget _buildLyricContent() {
    if (_lyricParser == null) {
      return Center(
        child: Text(
          '请选择歌词来源',
          style: TextStyle(
            fontSize: MediaQuery.of(context).size.width > 1000 ? 20 :
            MediaQuery.of(context).size.width > 600 ? 18 : 16,
            color: Colors.grey,
          ),
        ),
      );
    }

    if (_lyricParser!.lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            fontSize: MediaQuery.of(context).size.width > 1000 ? 20 :
            MediaQuery.of(context).size.width > 600 ? 18 : 16,
            color: Colors.grey,
          ),
        ),
      );
    }

    // 获取当前歌词行
    final currentLine = _lyricParser!.getCurrentLine(_position.inMilliseconds / 1000);

    return ListView.builder(
      controller: _lyricScrollController,
      padding: EdgeInsets.all(15),
      itemCount: _lyricParser!.lines.length,
      itemBuilder: (context, index) {
        final line = _lyricParser!.lines[index];
        final isCurrentLine = line == currentLine;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Text(
            line.content,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCurrentLine? 24 : 18,
              color: isCurrentLine ? Theme.of(context).primaryColor : Colors.black87,
              fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      },
    );
  }

  // 构建播放控制区域（手机）
  Widget _buildControls() {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;

    return Container(
      padding: EdgeInsets.all(isLargeScreen ? 30.0 : 20.0),
      child: Column(
        children: [
          // 进度条
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_position)),
              Text(_formatDuration(_duration ?? Duration.zero)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).primaryColor,
              inactiveTrackColor: Colors.grey[300],
              thumbColor: Theme.of(context).primaryColor,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Theme.of(context).primaryColor,
                inactiveTrackColor: Colors.grey[300],
                thumbColor: Theme.of(context).primaryColor,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: isLargeScreen ? 10 : 8),
                overlayShape: RoundSliderOverlayShape(overlayRadius: isLargeScreen ? 20 : 16),
              ),
              child: Slider(
                min: 0,
                max: (_duration?.inSeconds ?? 0).toDouble(),
                value: _position.inSeconds.toDouble(),
                onChanged: _onSliderChanged,
              ),
            ),
          ),
          SizedBox(height: 20),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous),
                iconSize: isLargeScreen ? 48 : 36,
                onPressed: _playPrevious,
              ),
              Container(
                width: isLargeScreen ? 80 : 60,
                height: isLargeScreen ? 80 : 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  iconSize: isLargeScreen ? 48 : 36,
                  onPressed: _togglePlay,
                ),
              ),
              IconButton(
                icon: Icon(Icons.skip_next),
                iconSize: isLargeScreen ? 48 : 36,
                onPressed: _playNext,
              ),
            ],
          ),

          // 其他功能按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.playlist_play),
                iconSize: isLargeScreen ? 36 : 30,
                onPressed: _openPlayList,
              ),
              IconButton(
                icon: Icon(_playModeIcon),
                iconSize: isLargeScreen ? 36 : 30,
                onPressed: _togglePlayMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 构建播放控制区域（平板）
  Widget _buildTabletControlTop() {
    final isExtraLargeScreen = MediaQuery.of(context).size.width > 1000;
    final isLargeScreen = MediaQuery.of(context).size.width > 600;

    return Container(
      padding: EdgeInsets.all(isExtraLargeScreen ? 30.0 : 20.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  fontSize: isExtraLargeScreen ? 20 : (isLargeScreen ? 18 : 16),
                ),
              ),
              Text(
                _formatDuration(_duration ?? Duration.zero),
                style: TextStyle(
                  fontSize: isExtraLargeScreen ? 20 : (isLargeScreen ? 18 : 16),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).primaryColor,
              inactiveTrackColor: Colors.grey[300],
              thumbColor: Theme.of(context).primaryColor,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Theme.of(context).primaryColor,
                inactiveTrackColor: Colors.grey[300],
                thumbColor: Theme.of(context).primaryColor,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: isLargeScreen ? 10 : 8),
                overlayShape: RoundSliderOverlayShape(overlayRadius: isLargeScreen ? 20 : 16),
              ),
              child: Slider(
                min: 0,
                max: (_duration?.inSeconds ?? 0).toDouble(),
                value: _position.inSeconds.toDouble(),
                onChanged: _onSliderChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建播放控制区域（平板）
  Widget _buildTabletControlBottom() {
    final isExtraLargeScreen = MediaQuery.of(context).size.width > 1000;

    return Container(
      padding: EdgeInsets.all(isExtraLargeScreen ? 30.0 : 20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.playlist_play),
                iconSize: isExtraLargeScreen ? 40 : 36,
                onPressed: _openPlayList,
              ),
              IconButton(
                icon: Icon(Icons.skip_previous),
                iconSize: isExtraLargeScreen ? 48 : 40,
                onPressed: _playPrevious,
              ),
              Container(
                width: isExtraLargeScreen ? 72 : 60,
                height: isExtraLargeScreen ? 72 : 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  iconSize: isExtraLargeScreen ? 40 : 36,
                  onPressed: _togglePlay,
                ),
              ),
              IconButton(
                icon: Icon(Icons.skip_next),
                iconSize: isExtraLargeScreen ? 48 : 40,
                onPressed: _playNext,
              ),
              IconButton(
                icon: Icon(_playModeIcon),
                iconSize: isExtraLargeScreen ? 40 : 36,
                onPressed: _togglePlayMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 格式化时间
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // 切换分P
  void _onPageChange(int? index) {
    if (index != null) {
      setState(() {
        _currentPageIndex = index;
      });
      widget.playerManager.play(model.Music(
        id: _music.id,
        title: _music.title,
        artist: _music.artist,
        album: _music.album,
        coverUrl: _music.coverUrl,
        duration: Duration(seconds: int.parse(_music.pages[index].duration)),
        audioUrl: '',
        pages: [_music.pages[index]],
      ));
    }
  }

  // 播放下一首
  void _playNext() {
    widget.playerManager.playNext();
  }

  // 播放上一首
  void _playPrevious() {
    widget.playerManager.playPrevious();
  }

  // 切换播放状态
  void _togglePlay() {
    if (_isPlaying) {
      widget.playerManager.pause();
    } else {
      widget.playerManager.resume();
    }
  }

  // 切换播放模式
  void _togglePlayMode() {
    widget.playerManager.togglePlayMode();
    setState(() {
      // 更新播放模式图标
      switch (widget.playerManager.playMode) {
        case PlayMode.sequential:
          _playModeIcon = Icons.repeat;
        case PlayMode.loop:
          _playModeIcon = Icons.repeat_one;
        case PlayMode.shuffle:
          _playModeIcon = Icons.shuffle;
      }
    });
  }

  // 滑动进度条
  void _onSliderChanged(double value) {
    widget.playerManager.seek(Duration(seconds: value.toInt()));
  }
}