import 'dart:convert';
import 'package:bilimusic/components/auto_appbar.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'dart:io' show File;
import 'package:restart_app/restart_app.dart';
import '../managers/settings_manager.dart';
import '../utils/platform_helper.dart';

class DataMigrationPage extends StatefulWidget {
  const DataMigrationPage({super.key});

  @override
  State<DataMigrationPage> createState() => _DataMigrationPageState();
}

class _DataMigrationPageState extends State<DataMigrationPage> {
  bool _isExporting = false;
  bool _isImporting = false;
  String _statusMessage = '';
  int _exportedItemCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '数据迁移'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '数据迁移向导',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '导出或导入您的应用数据',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
              ),
              SizedBox(height: 32),

              // 数据说明
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '迁移的数据包括：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      BulletPoint(text: '用户设置（主题、通知等）'),
                      BulletPoint(text: '播放历史记录'),
                      BulletPoint(text: '用户创建的播放列表'),
                      BulletPoint(text: '登录Cookie信息'),
                      SizedBox(height: 16),
                      Text(
                        '注意：缓存数据不会被迁移',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 32),

              // 导出数据
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '导出数据',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text('将所有应用数据导出为一个文件，以便在其他设备上导入'),
                      SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportData,
                          icon: Icon(Icons.upload_file),
                          label: Text('导出数据'),
                        ),
                      ),
                      if (_isExporting) ...[
                        SizedBox(height: 16),
                        Center(child: CircularProgressIndicator()),
                      ],
                      if (_statusMessage.isNotEmpty) ...[
                        SizedBox(height: 16),
                        Center(
                          child: Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _statusMessage.contains('成功')
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              SizedBox(height: 20),

              // 导入数据
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '导入数据',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text('从之前导出的数据文件导入应用数据'),
                      SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _isImporting ? null : _importData,
                          icon: Icon(Icons.download),
                          label: Text('导入数据'),
                        ),
                      ),
                      if (_isImporting) ...[
                        SizedBox(height: 16),
                        Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
              ),

              SizedBox(height: 32),

              // 注意事项
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '注意事项',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      BulletPoint(
                        text: '导入数据将覆盖当前应用数据',
                        textColor: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer,
                      ),
                      BulletPoint(
                        text: '导入完成后建议重启应用以确保所有设置生效',
                        textColor: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer,
                      ),
                      BulletPoint(
                        text: '请妥善保管导出的数据文件',
                        textColor: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 导出数据
  Future<void> _exportData() async {
    setState(() {
      _isExporting = true;
      _statusMessage = '正在导出数据...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 获取所有需要导出的数据
      final Map<String, dynamic> exportData = {};

      // 导出所有设置
      exportData['settings'] = _exportSettings(prefs);

      // 导出播放历史
      exportData['play_history'] = prefs.getString('play_history');

      // 导出播放列表索引
      exportData['user_playlists'] = prefs.getString('user_playlists');

      // 导出各个播放列表信息和歌曲
      final playlistIdsJson = prefs.getString('user_playlists');
      if (playlistIdsJson != null) {
        try {
          final List<dynamic> playlistIds = jsonDecode(playlistIdsJson);
          for (var id in playlistIds) {
            if (id is String) {
              exportData['playlist_info_$id'] = prefs.getString(
                'playlist_info_$id',
              );
              exportData['playlist_songs_$id'] = prefs.getString(
                'playlist_songs_$id',
              );
            }
          }
        } catch (e) {
          debugPrint('Error exporting playlists: $e');
        }
      }

      // 导出Cookie信息
      exportData['cookies'] = prefs.getString('cookies');
      exportData['login_time'] = prefs.getString('login_time');

      // 计算导出项目数量
      _exportedItemCount = exportData.keys.length;

      debugPrint('Exporting data with $_exportedItemCount top-level keys');

      // 创建JSON字符串
      final jsonString = jsonEncode(exportData);

      if (kIsWeb) {
        // Web端处理
        _downloadWebFile(jsonString);
      } else {
        // 移动端/桌面端处理
        await _saveToFile(jsonString);
      }
    } catch (e) {
      setState(() {
        _statusMessage = '导出失败: $e';
        _isExporting = false;
      });
      return;
    }
  }

  // 导出设置
  Map<String, dynamic> _exportSettings(SharedPreferences prefs) {
    final settings = <String, dynamic>{};

    // 从SettingsManager中定义的所有键导出设置
    settings['notifications_enabled'] = prefs.getBool('notifications_enabled');
    settings['download_quality_high'] = prefs.getBool('download_quality_high');
    settings['theme_mode'] = prefs.getString('theme_mode');
    settings['auto_play_next'] = prefs.getBool('auto_play_next');
    settings['show_lyrics'] = prefs.getBool('show_lyrics');
    settings['tablet_mode'] = prefs.getString('tablet_mode');
    settings['fluid_background'] = prefs.getBool('fluid_background');
    settings['blur_effect'] = prefs.getBool('blur_effect');
    settings[SettingsManager.KEY_VERSION_CODE] =
        SettingsManager.DEFAULT_VERSION_CODE;

    return settings;
  }

  // Web端下载文件
  @Deprecated('由于Web端跨域限制，目前无法实现完整功能')
  void _downloadWebFile(String content) {
    // 在Web上创建下载链接
    final blob = Uint8List.fromList(utf8.encode(content));

    // 显示成功消息
    setState(() {
      _statusMessage = '导出成功！请在浏览器下载中查看文件';
      _isExporting = false;
    });

    // TODO: 实现Web端文件下载
    // 这里需要使用js包来实现浏览器下载
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Web端文件下载功能待完善')));
  }

  // 保存到文件（移动端/桌面端）
  Future<void> _saveToFile(String content) async {
    try {
      String fileName =
          'bilimusic_data_${DateTime.now().millisecondsSinceEpoch}.json';

      if (PlatformHelper.isMobile) {
        // 移动端需要传入文件内容
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '请选择保存位置:',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(content)),
        );

        if (outputFile != null) {
          setState(() {
            _statusMessage = '导出成功！文件已保存到：$outputFile';
            _isExporting = false;
          });
        } else {
          setState(() {
            _statusMessage = '导出已取消';
            _isExporting = false;
          });
        }
      } else {
        // 桌面端让用户选择保存位置
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: '请选择保存位置:',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(content);

          setState(() {
            _statusMessage = '导出成功！文件已保存到：$outputFile';
            _isExporting = false;
          });
        } else {
          setState(() {
            _statusMessage = '导出已取消';
            _isExporting = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = '保存文件失败: $e';
        _isExporting = false;
      });
    }
  }

  // 导入数据
  Future<void> _importData() async {
    setState(() {
      _isImporting = true;
    });

    try {
      // 让用户选择文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '请选择数据文件',
      );

      if (result != null) {
        String filePath = result.files.single.path!;
        final file = File(filePath);
        final content = await file.readAsString();

        // 解析JSON数据
        final Map<String, dynamic> importData = jsonDecode(content);

        // 版本验证
        final appVersionCode = SettingsManager.DEFAULT_VERSION_CODE;
        final dataVersionCode = importData['settings'] != null
            ? (importData['settings'][SettingsManager.KEY_VERSION_CODE] as int?)
            : null;

        // 如果数据文件中没有版本号或者版本号大于当前应用版本，则提示用户
        if (dataVersionCode == null) {
          // 数据文件中没有版本信息
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                icon: Icon(Icons.warning),
                title: Text('版本信息缺失'),
                content: Text(
                  '导入的数据文件中不包含版本信息，可能存在兼容性问题，请确认是否选择了正确的数据文件。'
                  '\n如果此文件是在 1.3.04 以下的版本导出的，请忽视此提示。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('继续导入'),
                  ),
                ],
              );
            },
          );

          if (shouldContinue != true) {
            setState(() {
              _isImporting = false;
            });
            return;
          }
        } else if (dataVersionCode > appVersionCode) {
          // 数据文件版本高于当前应用版本
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                icon: Icon(Icons.warning),
                title: Text('数据版本不兼容'),
                content: Text(
                  '导入的数据文件版本为 $dataVersionCode，'
                  '高于当前应用版本 $appVersionCode，可能存在兼容性问题。是否继续导入？',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('继续导入'),
                  ),
                ],
              );
            },
          );

          if (shouldContinue != true) {
            setState(() {
              _isImporting = false;
            });
            return;
          }
        }

        // 保存数据到SharedPreferences
        final prefs = await SharedPreferences.getInstance();

        // 导入设置
        if (importData['settings'] != null) {
          final settings = importData['settings'] as Map<String, dynamic>;
          for (var entry in settings.entries) {
            if (entry.value is bool) {
              await prefs.setBool(entry.key, entry.value);
            } else if (entry.value is String) {
              await prefs.setString(entry.key, entry.value);
            }
          }
        }

        // 导入播放历史
        if (importData['play_history'] != null) {
          await prefs.setString('play_history', importData['play_history']);
        }

        // 导入播放列表索引
        if (importData['user_playlists'] != null) {
          await prefs.setString('user_playlists', importData['user_playlists']);
        }

        // 导入播放列表信息和歌曲
        importData.forEach((key, value) {
          if (key.startsWith('playlist_info_') ||
              key.startsWith('playlist_songs_')) {
            if (value != null) {
              prefs.setString(key, value);
            }
          }
        });

        // 导入Cookie信息
        if (importData['cookies'] != null) {
          await prefs.setString('cookies', importData['cookies']);
        }
        if (importData['login_time'] != null) {
          await prefs.setString('login_time', importData['login_time']);
        }

        setState(() {
          _isImporting = false;
        });

        // 显示成功消息并建议重启
        if (mounted) {
          final shouldRestart = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text('导入成功'),
                content: Text('数据导入完成，建议重启应用以确保所有设置生效。是否现在重启？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('稍后重启'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('立即重启'),
                  ),
                ],
              );
            },
          );

          if (shouldRestart == true) {
            // 重启应用
            await Restart.restartApp();
          }
        }
      } else {
        // 用户取消选择
        setState(() {
          _isImporting = false;
        });
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }
}

class BulletPoint extends StatelessWidget {
  final String text;
  final Color? textColor;

  const BulletPoint({Key? key, required this.text, this.textColor})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: textColor)),
          Expanded(
            child: Text(text, style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }
}
