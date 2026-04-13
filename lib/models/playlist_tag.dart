import 'package:flutter/material.dart';

/// 标签分类枚举
enum TagCategory {
  genre,   // 音乐风格
  scenario, // 使用场景
  mood,    // 心情情绪
  custom   // 自定义标签
}

/// 标签分类的显示名称和颜色配置
class TagCategoryConfig {
  final TagCategory category;
  final String displayName;
  final Color defaultColor;

  const TagCategoryConfig({
    required this.category,
    required this.displayName,
    required this.defaultColor,
  });

  static const List<TagCategoryConfig> configs = [
    TagCategoryConfig(
      category: TagCategory.genre,
      displayName: '音乐风格',
      defaultColor: Color(0xFFFF6B6B),
    ),
    TagCategoryConfig(
      category: TagCategory.scenario,
      displayName: '使用场景',
      defaultColor: Color(0xFF74B9FF),
    ),
    TagCategoryConfig(
      category: TagCategory.mood,
      displayName: '心情情绪',
      defaultColor: Color(0xFFFDCB6E),
    ),
    TagCategoryConfig(
      category: TagCategory.custom,
      displayName: '自定义',
      defaultColor: Color(0xFF636E72),
    ),
  ];

  static TagCategoryConfig? getConfig(TagCategory category) {
    return configs.firstWhere(
      (c) => c.category == category,
      orElse: () => configs.last,
    );
  }
}

/// 歌单标签模型
class PlaylistTag {
  final String id;
  final String name;
  final String nameCn;
  final TagCategory category;
  final String iconName;
  final int colorValue;
  final int sortOrder;
  final bool isSystem; // 是否为系统预设标签

  const PlaylistTag({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.category,
    this.iconName = 'label',
    this.colorValue = 0xFF636E72,
    this.sortOrder = 0,
    this.isSystem = true,
  });

  Color get color => Color(colorValue);

  IconData get icon {
    switch (iconName) {
      case 'music_note':
        return Icons.music_note;
      case 'headphones':
        return Icons.headphones;
      case 'piano':
        return Icons.piano;
      case 'queue_music':
        return Icons.queue_music;
      case 'graphic_eq':
        return Icons.graphic_eq;
      case 'work':
        return Icons.work;
      case 'spa':
        return Icons.spa;
      case 'bedtime':
        return Icons.bedtime;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'directions_subway':
        return Icons.directions_subway;
      case 'sentiment_very_satisfied':
        return Icons.sentiment_very_satisfied;
      case 'sentiment_dissatisfied':
        return Icons.sentiment_dissatisfied;
      case 'bolt':
        return Icons.bolt;
      case 'favorite':
        return Icons.favorite;
      case 'label':
      default:
        return Icons.label;
    }
  }

  factory PlaylistTag.fromJson(Map<String, dynamic> json) {
    return PlaylistTag(
      id: json['id'],
      name: json['name'],
      nameCn: json['nameCn'] ?? json['name'],
      category: TagCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => TagCategory.custom,
      ),
      iconName: json['iconName'] ?? 'label',
      colorValue: json['colorValue'] ?? 0xFF636E72,
      sortOrder: json['sortOrder'] ?? 0,
      isSystem: json['isSystem'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'nameCn': nameCn,
      'category': category.name,
      'iconName': iconName,
      'colorValue': colorValue,
      'sortOrder': sortOrder,
      'isSystem': isSystem,
    };
  }

  PlaylistTag copyWith({
    String? id,
    String? name,
    String? nameCn,
    TagCategory? category,
    String? iconName,
    int? colorValue,
    int? sortOrder,
    bool? isSystem,
  }) {
    return PlaylistTag(
      id: id ?? this.id,
      name: name ?? this.name,
      nameCn: nameCn ?? this.nameCn,
      category: category ?? this.category,
      iconName: iconName ?? this.iconName,
      colorValue: colorValue ?? this.colorValue,
      sortOrder: sortOrder ?? this.sortOrder,
      isSystem: isSystem ?? this.isSystem,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaylistTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PlaylistTag(id: $id, nameCn: $nameCn, category: $category)';
}

/// 预设标签集合
class DefaultPlaylistTags {
  // 音乐风格
  static const List<PlaylistTag> genreTags = [
    PlaylistTag(
      id: 'pop',
      name: 'pop',
      nameCn: '流行',
      category: TagCategory.genre,
      iconName: 'music_note',
      colorValue: 0xFFFF6B6B,
      sortOrder: 1,
    ),
    PlaylistTag(
      id: 'rock',
      name: 'rock',
      nameCn: '摇滚',
      category: TagCategory.genre,
      iconName: 'headphones',
      colorValue: 0xFF4ECDC4,
      sortOrder: 2,
    ),
    PlaylistTag(
      id: 'jazz',
      name: 'jazz',
      nameCn: '爵士',
      category: TagCategory.genre,
      iconName: 'piano',
      colorValue: 0xFFFFE66D,
      sortOrder: 3,
    ),
    PlaylistTag(
      id: 'classical',
      name: 'classical',
      nameCn: '古典',
      category: TagCategory.genre,
      iconName: 'queue_music',
      colorValue: 0xFF95E1D3,
      sortOrder: 4,
    ),
    PlaylistTag(
      id: 'electronic',
      name: 'electronic',
      nameCn: '电子',
      category: TagCategory.genre,
      iconName: 'graphic_eq',
      colorValue: 0xFFA8E6CF,
      sortOrder: 5,
    ),
    PlaylistTag(
      id: 'hiphop',
      name: 'hiphop',
      nameCn: '嘻哈',
      category: TagCategory.genre,
      iconName: 'music_note',
      colorValue: 0xFF9B59B6,
      sortOrder: 6,
    ),
    PlaylistTag(
      id: 'folk',
      name: 'folk',
      nameCn: '民谣',
      category: TagCategory.genre,
      iconName: 'music_note',
      colorValue: 0xFF00B894,
      sortOrder: 7,
    ),
  ];

  // 使用场景
  static const List<PlaylistTag> scenarioTags = [
    PlaylistTag(
      id: 'work',
      name: 'work',
      nameCn: '工作',
      category: TagCategory.scenario,
      iconName: 'work',
      colorValue: 0xFF74B9FF,
      sortOrder: 10,
    ),
    PlaylistTag(
      id: 'relax',
      name: 'relax',
      nameCn: '放松',
      category: TagCategory.scenario,
      iconName: 'spa',
      colorValue: 0xFFDDA0DD,
      sortOrder: 11,
    ),
    PlaylistTag(
      id: 'sleep',
      name: 'sleep',
      nameCn: '助眠',
      category: TagCategory.scenario,
      iconName: 'bedtime',
      colorValue: 0xFF9B59B6,
      sortOrder: 12,
    ),
    PlaylistTag(
      id: 'workout',
      name: 'workout',
      nameCn: '运动',
      category: TagCategory.scenario,
      iconName: 'fitness_center',
      colorValue: 0xFFFF7675,
      sortOrder: 13,
    ),
    PlaylistTag(
      id: 'commute',
      name: 'commute',
      nameCn: '通勤',
      category: TagCategory.scenario,
      iconName: 'directions_subway',
      colorValue: 0xFF636E72,
      sortOrder: 14,
    ),
    PlaylistTag(
      id: 'study',
      name: 'study',
      nameCn: '学习',
      category: TagCategory.scenario,
      iconName: 'menu_book',
      colorValue: 0xFF00CEC9,
      sortOrder: 15,
    ),
  ];

  // 心情情绪
  static const List<PlaylistTag> moodTags = [
    PlaylistTag(
      id: 'happy',
      name: 'happy',
      nameCn: '欢快',
      category: TagCategory.mood,
      iconName: 'sentiment_very_satisfied',
      colorValue: 0xFFFDCB6E,
      sortOrder: 20,
    ),
    PlaylistTag(
      id: 'sad',
      name: 'sad',
      nameCn: '忧伤',
      category: TagCategory.mood,
      iconName: 'sentiment_dissatisfied',
      colorValue: 0xFF0984E3,
      sortOrder: 21,
    ),
    PlaylistTag(
      id: 'energetic',
      name: 'energetic',
      nameCn: '活力',
      category: TagCategory.mood,
      iconName: 'bolt',
      colorValue: 0xFFE17055,
      sortOrder: 22,
    ),
    PlaylistTag(
      id: 'romantic',
      name: 'romantic',
      nameCn: '浪漫',
      category: TagCategory.mood,
      iconName: 'favorite',
      colorValue: 0xFFE84393,
      sortOrder: 23,
    ),
    PlaylistTag(
      id: 'calm',
      name: 'calm',
      nameCn: '平静',
      category: TagCategory.mood,
      iconName: 'spa',
      colorValue: 0xFF81ECEC,
      sortOrder: 24,
    ),
    PlaylistTag(
      id: 'nostalgic',
      name: 'nostalgic',
      nameCn: '怀旧',
      category: TagCategory.mood,
      iconName: 'history',
      colorValue: 0xFFB2BEC3,
      sortOrder: 25,
    ),
  ];

  /// 获取所有预设标签
  static List<PlaylistTag> get allTags => [...genreTags, ...scenarioTags, ...moodTags];

  /// 根据分类获取标签
  static List<PlaylistTag> getByCategory(TagCategory category) {
    switch (category) {
      case TagCategory.genre:
        return genreTags;
      case TagCategory.scenario:
        return scenarioTags;
      case TagCategory.mood:
        return moodTags;
      case TagCategory.custom:
        return [];
    }
  }

  /// 根据ID获取标签
  static PlaylistTag? getById(String id) {
    try {
      return allTags.firstWhere((tag) => tag.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 根据ID列表获取标签
  static List<PlaylistTag> getByIds(List<String> ids) {
    return allTags.where((tag) => ids.contains(tag.id)).toList();
  }
}
