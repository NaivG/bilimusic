/// 比较两个语义版本号（`major.minor.patch`，允许 `+build` 后缀）。
///
/// 只比较前三段数字；缺失的段按 0 处理，非数字段也按 0 处理。启动门控只
/// 需要判断「上次启动的版本」和当前版本的前后关系，不在这里做完整的
/// SemVer 校验。
int compareVersions(String a, String b) {
  final left = _parse(a);
  final right = _parse(b);
  for (var index = 0; index < 3; index++) {
    final diff = left[index] - right[index];
    if (diff != 0) return diff.sign;
  }
  return 0;
}

List<int> _parse(String version) {
  final core = version.split('+').first.trim();
  final parts = core.split('.');
  int segment(int index) {
    if (index >= parts.length) return 0;
    return int.tryParse(parts[index].trim()) ?? 0;
  }

  return <int>[segment(0), segment(1), segment(2)];
}
