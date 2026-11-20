import 'package:flutter/widgets.dart';

import 'package:bilimusic/features/onboarding/ui/onboarding_visuals.dart';

/// 分页底部的配件：没有 / 主题选择。
enum OnboardingAccessory { none, themePicker }

/// 一页引导的文案与插画。
@immutable
class OnboardingPageSpec {
  const OnboardingPageSpec({
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.visual,
    required this.visualSize,
    this.accessory = OnboardingAccessory.none,
    this.hero = false,
  });

  /// 标题上方的小字分类（全大写，宽字距）。
  final String kicker;

  final String title;
  final String subtitle;
  final Widget visual;

  /// 插画的设计尺寸：页面按可用空间等比缩放它，保证插画内部永远按
  /// 这套尺寸布局，不会在超矮 / 超窄的窗口里把 RenderFlex 撑破。
  final Size visualSize;

  final OnboardingAccessory accessory;

  /// 首屏：标题更大，用于封面式开场。
  final bool hero;
}

/// 通用引导页内容。
///
/// 面向首次启动与「设置 → 使用指南」回看：按「欢迎 → 账号与收藏 →
/// 搜索与漫游 → 播放与音效 → 离线缓存 → 主题外观 → 宽屏布局 →
/// 动态歌词 → 局域网同步 → 开始听歌」的顺序介绍 BiliMusic 的核心体验。
const List<OnboardingPageSpec> onboardingPages = <OnboardingPageSpec>[
  OnboardingPageSpec(
    kicker: 'BILIMUSIC',
    title: '把 B 站当音乐库',
    subtitle: '撇开视频干扰，只专注于声音本身。\n翻唱、现场、纯音乐与播客电台，都用真正顺手的播放器来听。',
    visual: OnboardingHeroVisual(),
    visualSize: Size(440, 440),
    hero: true,
  ),
  OnboardingPageSpec(
    kicker: 'ACCOUNT',
    title: '你的收藏，直接带过来',
    subtitle: '登录 B 站账号即可导入收藏夹、追更常听的 UP 主。\n不想登录也没关系，打开就能直接搜歌播放。',
    visual: OnboardingLoginVisual(),
    visualSize: Size(340, 390),
  ),
  OnboardingPageSpec(
    kicker: 'DISCOVER',
    title: '搜得到的，和没听过的',
    subtitle: '支持关键词与 BV / AV 号直达，也能逛逛热歌榜与每日推荐。\n拿不定主意时，选一首歌开启漫游，自动续上合口味的曲目。',
    visual: OnboardingFindVisual(),
    visualSize: Size(340, 400),
  ),
  OnboardingPageSpec(
    kicker: 'PLAYBACK',
    title: '好听，也更耐听',
    subtitle: '自动剥离视频标题里的【MV】【中字】等杂讯，还原干净歌名。\n支持多档音质切换、切歌平滑过渡与八段均衡器。',
    visual: OnboardingPlayVisual(),
    visualSize: Size(340, 400),
  ),
  OnboardingPageSpec(
    kicker: 'OFFLINE',
    title: '好歌留在本地',
    subtitle: '自由创建和编排本地歌单，将喜欢的单曲或整张歌单缓存到设备里。\n出门在外、没有网络也能照常聆听。',
    visual: OnboardingOfflineVisual(),
    visualSize: Size(340, 395),
  ),
  OnboardingPageSpec(
    kicker: 'THEMES',
    title: '六套主题，随心切换',
    subtitle: '从温润的暖纸白到静谧的极夜黑，内置六套精心调校的配色，\n均支持深浅模式切换。现在就可以点选试试：',
    visual: OnboardingTheaterVisual(),
    visualSize: Size(320, 396),
    accessory: OnboardingAccessory.themePicker,
  ),
  OnboardingPageSpec(
    kicker: 'WORKSPACE',
    title: '大屏小屏，各自顺手',
    subtitle: '竖屏单手操作轻巧灵便，桌面与平板横屏则展开为宽敞的听歌空间，\n资料库与播放队列在侧边随用随开。',
    visual: OnboardingLandscapeVisual(),
    visualSize: Size(440, 286),
  ),
  OnboardingPageSpec(
    kicker: 'LYRICS',
    title: '词随声动，光影相伴',
    subtitle: 'AM样式的详情页，自动从多平台匹配歌词，\n支持逐字高亮与译文对照。',
    visual: OnboardingLyricVisual(),
    visualSize: Size(340, 395),
  ),
  OnboardingPageSpec(
    kicker: 'CONNECT',
    title: '多台设备，接力去听',
    subtitle: '同一局域网下自动发现设备，扫码配对后即可在电脑、手机间\n实时同步播放队列，也能跨设备遥控切歌。',
    visual: OnboardingSyncVisual(),
    visualSize: Size(340, 385),
  ),
  OnboardingPageSpec(
    kicker: 'PERFORMANCE',
    title: '内存性能，大幅优化',
    subtitle: '常驻内存消耗砍掉约43%，\n同时大幅优化了组件和页面的渲染开销。',
    visual: OnboardingPerformanceVisual(),
    visualSize: Size(380, 400),
  ),
  OnboardingPageSpec(
    kicker: 'READY',
    title: '去听点什么',
    subtitle: '播放记录与偏好设置均保存在本地。\n随时可以从「设置 → 使用指南」重新打开这份引导。',
    visual: OnboardingStartVisual(),
    visualSize: Size(380, 340),
  ),
];
