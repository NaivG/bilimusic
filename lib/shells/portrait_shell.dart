import 'package:flutter/material.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/components/mini_player.dart';
import 'package:bilimusic/components/desktop_window_controls.dart';

/// 竖屏模式外壳 - 包含平板模式和手机模式布局
/// 平板：NavigationRail + 主内容 + 迷你播放器
/// 手机：主内容 + 迷你播放器 + 底部导航栏
class PortraitShell extends StatelessWidget {
  final int selectedIndex;
  final List<Widget> pages;
  final PlayerManager playerManager;
  final bool isTabletMode;
  final bool isPcPlatform;
  final bool isPcMode;
  final Function(int index) onItemTapped;
  final VoidCallback onExpand;
  final VoidCallback onPlayList;

  const PortraitShell({
    super.key,
    required this.selectedIndex,
    required this.pages,
    required this.playerManager,
    required this.isTabletMode,
    required this.isPcPlatform,
    required this.isPcMode,
    required this.onItemTapped,
    required this.onExpand,
    required this.onPlayList,
  });

  @override
  Widget build(BuildContext context) {
    if (isTabletMode) {
      return _buildTabletLayout(context);
    } else {
      return _buildMobileLayout(context);
    }
  }

  /// 平板模式布局
  Widget _buildTabletLayout(BuildContext context) {
    return Scaffold(
      appBar: isPcPlatform
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: DesktopNavBar(
                selectedIndex: selectedIndex,
                onNavTap: onItemTapped,
                onClose: () => playerManager.stop(),
              ),
            )
          : null,
      body: Row(
        children: [
          // 侧边导航栏（非PC模式）
          isPcMode
              ? const SizedBox(width: 0)
              : SizedBox(
                  width: 80,
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (int index) {
                      onItemTapped(index);
                    },
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home),
                        label: Text('首页'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.search),
                        label: Text('搜索'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.person),
                        label: Text('我的'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text('设置'),
                      ),
                    ],
                  ),
                ),
          // 主内容区域
          Expanded(
            child: Stack(
              children: [
                pages[selectedIndex],
                // 平板模式下的悬浮迷你播放器
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: Center(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: MiniPlayerComponent(
                        playerManager: playerManager,
                        onExpand: onExpand,
                        onPlayList: onPlayList,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 手机模式布局
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: isPcPlatform
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: DesktopNavBar(
                selectedIndex: selectedIndex,
                onNavTap: onItemTapped,
                onClose: () => playerManager.stop(),
              ),
            )
          : null,
      body: Stack(
        children: [
          pages[selectedIndex],
          // 悬浮迷你播放器
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.95,
                child: MiniPlayerComponent(
                  playerManager: playerManager,
                  onExpand: onExpand,
                  onPlayList: onPlayList,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search),
              label: '搜索',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outlined),
              activeIcon: Icon(Icons.person),
              label: '我的',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
          currentIndex: selectedIndex,
          onTap: onItemTapped,
        ),
      ),
    );
  }
}
