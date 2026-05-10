import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        forceMaterialTransparency: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 通知设置
            _buildSectionTitle('通知'),
            _buildSwitchListTile(
              icon: Icons.notifications,
              title: '推送媒体通知',
              value: sl.settingsManager.notificationsEnabled,
              onChanged: (value) {
                sl.settingsManager.setNotificationsEnabled(value);
                setState(() {}); // 刷新UI
              },
            ),

            // 播放设置
            _buildSectionTitle('播放'),
            _buildSwitchListTile(
              icon: Icons.play_arrow,
              title: '自动播放下一首',
              value: sl.settingsManager.autoPlayNext,
              onChanged: (value) {
                sl.settingsManager.setAutoPlayNext(value);
                setState(() {}); // 刷新UI
              },
            ),

            // Crossfade设置
            _buildSwitchListTile(
              icon: Icons.graphic_eq,
              title: '交叉淡入淡出',
              subtitle: '歌曲自动切换时平滑过渡(仅自动切歌生效)',
              value: sl.settingsManager.crossfadeEnabled,
              onChanged: (value) {
                sl.settingsManager.setCrossfadeEnabled(value);
                setState(() {}); // 刷新UI
              },
            ),

            // 仅在启用crossfade时显示详细设置
            if (sl.settingsManager.crossfadeEnabled) ...[
              // Crossfade时长滑块
              ListTile(
                leading: Icon(Icons.timer, color: _getPrimaryColor(context)),
                title: Text('淡入淡出时长'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前: ${sl.settingsManager.crossfadeDuration ~/ 1000}秒',
                    ),
                    Slider(
                      value: sl.settingsManager.crossfadeDuration.toDouble(),
                      min: 1000,
                      max: 10000,
                      divisions: 9,
                      label: '${sl.settingsManager.crossfadeDuration ~/ 1000}秒',
                      onChanged: (value) async {
                        await sl.settingsManager.setCrossfadeDuration(
                          value.toInt(),
                        );
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),

              // 预加载时间滑块
              ListTile(
                leading: Icon(Icons.download, color: _getPrimaryColor(context)),
                title: Text('提前加载时间'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前: 当开始过渡前${sl.settingsManager.preloadSeconds}秒开始加载下一首',
                    ),
                    Slider(
                      value: sl.settingsManager.preloadSeconds.toDouble(),
                      min: 5,
                      max: 30,
                      divisions: 25,
                      label: '${sl.settingsManager.preloadSeconds}秒',
                      onChanged: (value) async {
                        await sl.settingsManager.setPreloadSeconds(
                          value.toInt(),
                        );
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],

            // 音质设置
            _buildSectionTitle('音质'),
            _buildSwitchListTile(
              icon: Icons.high_quality,
              title: '高品质音乐',
              subtitle: '开启后将获取更高品质的音乐',
              value: sl.settingsManager.downloadQualityHigh,
              onChanged: (value) {
                sl.settingsManager.setDownloadQualityHigh(value);
                setState(() {}); // 刷新UI
              },
            ),

            // 界面设置
            _buildSectionTitle('界面'),
            _buildSwitchListTile(
              icon: Icons.auto_awesome,
              title: '流体背景效果',
              subtitle: '为页面启用模糊背景',
              value: sl.settingsManager.fluidBackground,
              onChanged: (value) {
                sl.settingsManager.setFluidBackground(value);
                setState(() {}); // 刷新UI
              },
            ),
            _buildSwitchListTile(
              icon: Icons.blur_on,
              title: '毛玻璃效果',
              subtitle: '为迷你播放器栏启用毛玻璃效果',
              value: sl.settingsManager.blurEffect,
              onChanged: (value) {
                sl.settingsManager.setBlurEffect(value);
                setState(() {}); // 刷新UI
              },
            ),
            ListTile(
              leading: Icon(Icons.tablet, color: _getPrimaryColor(context)),
              title: Text('平板模式'),
              subtitle: Text(
                sl.settingsManager.getTabletModeText(
                  sl.settingsManager.tabletMode,
                ),
              ),
              trailing: DropdownButton<String>(
                value: sl.settingsManager.tabletMode,
                items: [
                  DropdownMenuItem(value: 'auto', child: Text('自动')),
                  DropdownMenuItem(value: 'on', child: Text('强制打开')),
                  DropdownMenuItem(value: 'off', child: Text('强制关闭')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    sl.settingsManager.setTabletMode(value);
                    setState(() {});
                  }
                },
              ),
            ),

            // 音频设置（仅在安卓平台可用）
            _buildSectionTitle('音频'),
            ListTile(
              leading: Icon(Icons.volume_up, color: _getPrimaryColor(context)),
              title: Text('音频输出模式'),
              subtitle: Text(
                sl.settingsManager.getAudioOutputModeText(
                  sl.settingsManager.audioOutputMode,
                ),
              ),
              enabled: PlatformHelper.isAndroid, // 仅在安卓平台启用
              trailing: DropdownButton<String>(
                value: sl.settingsManager.audioOutputMode,
                items: [
                  DropdownMenuItem(value: 'aaudio', child: Text('AAudio (推荐)')),
                  DropdownMenuItem(
                    value: 'audiotrack',
                    child: Text('AudioTrack'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    sl.settingsManager.setAudioOutputMode(value);
                    setState(() {});
                  }
                },
              ),
            ),

            // 主题设置
            _buildSectionTitle('主题 (需要重启生效)'),
            ListTile(
              leading: Icon(
                Icons.settings_brightness,
                color: _getPrimaryColor(context),
              ),
              title: Text('主题模式'),
              subtitle: Text(
                sl.settingsManager.getThemeModeText(
                  sl.settingsManager.themeMode,
                ),
              ),
              trailing: DropdownButton<String>(
                value: sl.settingsManager.themeMode,
                items: [
                  DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                  DropdownMenuItem(value: 'light', child: Text('浅色')),
                  DropdownMenuItem(value: 'dark', child: Text('深色')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    sl.settingsManager.setThemeMode(value);
                    setState(() {}); // 刷新UI
                    // 通知整个应用重建以应用主题更改
                    defaultTargetPlatform; // 这里只是触发重建的一种方式
                  }
                },
              ),
            ),
            ListTile(
              leading: Icon(Icons.palette, color: _getPrimaryColor(context)),
              title: Text('主题配色'),
              subtitle: Text('设置全局配色方案'),
              trailing: DropdownButton<String>(
                value: sl.settingsManager.themeColor,
                items: [
                  DropdownMenuItem(value: 'lucent', child: Text('Lucent (推荐)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {});
                  }
                },
              ),
            ),

            // 数据管理
            _buildSectionTitle('数据管理'),
            ListTile(
              leading: Icon(Icons.storage, color: _getPrimaryColor(context)),
              title: Text('数据管理'),
              subtitle: Text('查看详细数据、缓存信息与数据操作'),
              trailing: Icon(Icons.arrow_forward_ios_rounded),
              onTap: () {
                ShellPageManager.instance.push(ShellPage.dataManagement);
              },
            ),

            // 关于
            _buildSectionTitle('关于'),
            ListTile(
              leading: Icon(Icons.info, color: _getPrimaryColor(context)),
              title: Text('关于应用'),
              onTap: _showAboutDialog,
            ),
            ListTile(
              leading: Icon(Icons.update, color: _getPrimaryColor(context)),
              title: Text('更新日志'),
              onTap: _showChangelog,
            ),
            ListTile(
              leading: Icon(
                Icons.privacy_tip,
                color: _getPrimaryColor(context),
              ),
              title: Text('隐私政策'),
              onTap: _showPrivacyPolicy,
            ),
            ListTile(
              leading: Icon(Icons.cookie, color: _getPrimaryColor(context)),
              title: Text('查看 Cookie'),
              subtitle: Text('查看当前保存的 Cookie 信息'),
              trailing: Icon(Icons.arrow_forward_ios_rounded),
              onTap: _showCookies,
            ),
            ListTile(
              leading: Icon(Icons.code, color: _getPrimaryColor(context)),
              title: Text('查看 Github 仓库'),
              subtitle: Text('NaivG/BiliMusic'),
              trailing: Icon(Icons.open_in_new),
              onTap: () {
                final url = Uri.parse('https://github.com/NaivG/BiliMusic');
                launchUrl(url, mode: LaunchMode.externalApplication);
              },
            ),
            SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  // 获取适合当前主题的主色调
  Color _getPrimaryColor(BuildContext context) {
    // 在深色主题中使用白色，在浅色主题中使用primaryColor
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Theme.of(context).primaryColor;
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  Widget _buildSwitchListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: _getPrimaryColor(context)),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'BiliMusic',
      applicationVersion: '1.6.1',
      applicationIcon: Image.asset(
        "assets/ic_launcher.png",
        width: 84,
        height: 84,
      ),
      applicationLegalese: '© 2025-2026 NaivG.',
      children: [
        SizedBox(height: 16),
        Text('另一个基于 Flutter 开发的 Bilibili 音乐播放器应用'),
      ],
    );
  }

  void _showChangelog() {
    ShellPageManager.instance.push(ShellPage.changelog);
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('隐私政策'),
          content: SingleChildScrollView(
            child: Text(
              '我们非常重视您的隐私保护。本应用不会收集上传您的个人隐私信息，所有数据仅存储在本地设备上。\n\n'
              '我们可能使用的信息包括：\n'
              '1. 播放历史记录\n'
              '2. 收藏列表\n'
              '3. 用户设置\n\n'
              '这些信息仅用于提供更好的用户体验，不会上传到任何服务器。\n\n'
              '如果您有任何疑问，请通过设置中的意见反馈联系我们。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showCookies() {
    ShellPageManager.instance.push(ShellPage.cookie);
  }
}
