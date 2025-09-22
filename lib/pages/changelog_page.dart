import 'package:flutter/material.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<ChangelogEntry> changelogEntries = [
      ChangelogEntry(
        version: '1.3.05',
        date: '2025-09-13',
        changes: [
          '新增 PC 模式',
          '重构PC端窗口样式'
        ],
      ),
      ChangelogEntry(
        version: '1.3.04',
        date: '2025-09-12',
        changes: [
          '修复媒体通知不能及时刷新信息问题',
          '修复切歌时歌曲索引错误',
        ],
      ),
      ChangelogEntry(
        version: '1.3.03',
        date: '2025-09-11',
        changes: [
          '添加数据迁移功能',
          '更新应用信息',
        ],
      ),
      ChangelogEntry(
        version: '1.3.02',
        date: '2025-09-11',
        changes: [
          '添加 Changelog 页面',
          '优化部分用户界面',
          '修复设置绑定错误',
          '修复迷你播放器不能及时刷新信息的问题',
        ],
      ),
      ChangelogEntry(
        version: '1.3.01',
        date: '2025-09-10',
        changes: [
          '恢复 APP 图标',
          '新增迷你播放器栏毛玻璃效果',
          '新增获取网易云音乐歌词',
          '正式适配 PC 端设备',
          '优化详情页流体背景效果',
          '修复 PC 设备上播放失败问题',
          '修复极端情况下界面布局错误',
          '修复详情页不能及时刷新信息的问题',
        ],
      ),
      ChangelogEntry(
        version: '1.2.27',
        date: '2025-09-01',
        changes: [
          '新增详情页流体背景效果',
          '新增猜你喜欢功能',
          '优化查看 Cookies 界面',
          '修复已知问题',
        ],
      ),
      ChangelogEntry(
        version: '1.2.26',
        date: '2025-08-30',
        changes: [
          '改进音乐播放稳定性',
          '优化缓存管理',
          '适配平板模式',
          '重构 Cookies 管理逻辑',
          '修复无法登录问题',
        ],
      ),
      ChangelogEntry(
        version: '1.2.24',
        date: '2025-08-23',
        changes: [
          '新增深色主题支持',
          '新增设置页面',
          '接入 Bilibili 登录 API',
          '优化内部信息模型',
          '修复部分设备上的播放问题',
          '修复播放列表音乐删除错误',
        ],
      ),
      ChangelogEntry(
        version: '1.2.05',
        date: '2025-08-19',
        changes: [
          '完善播放列表、歌单管理逻辑',
          '新增长按菜单',
          '新增歌单功能',
          '优化获取音乐信息的流程',
        ],
      ),
      ChangelogEntry(
        version: '1.2.01',
        date: '2025-08-18',
        changes: [
          '重构部分页面代码',
          '新增分享功能',
          '修复搜索页默认缓存全尺寸图片的问题',
        ],
      ),
      ChangelogEntry(
        version: '1.1.01',
        date: '2025-07-15',
        changes: [
          '重构主页，使用卡片视图',
          '新增列表缓存功能',
          '新增播放历史、我喜欢的音乐功能',
          '修复已知问题',
        ],
      ),
      ChangelogEntry(
        version: '1.0.02',
        date: '2025-07-01',
        changes: [
          '实现图片、音乐缓存',
          '接入安卓8+媒体推送通道',
          '修复已知问题',
        ],
      ),
      ChangelogEntry(
        version: '1.0.00',
        date: '2025-06-20',
        changes: [
          '将主程序从 Python 迁移至 Kotlin',
          '实现基本音乐播放功能',
          '实现播放列表功能',
          '实现搜索功能',
        ],
      ),
      ChangelogEntry(
        version: '0.9.0',
        date: '2025-06-18',
        changes: [
          '添加获取歌词功能',
          '增强横屏体验',
          '接入安卓8+通知推送通道',
          '修复已知问题',
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        itemCount: changelogEntries.length,
        itemBuilder: (context, index) {
          return _buildChangelogItem(changelogEntries[index]);
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
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...entry.changes.map((change) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(
                    child: Text(change),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class ChangelogEntry {
  final String version;
  final String date;
  final List<String> changes;

  ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}