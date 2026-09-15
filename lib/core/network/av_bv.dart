/// AV 号转 BV 号工具。
///
/// 公开算法常量与映射表来自 B 站前端常见的 `av2bv` 实现；
/// 见 https://www.bilibili.com/blackboard/topic-list.html 及社区 wiki。
String av2bv(int aid) {
  const xorCode = 23442827791579;
  const base = 58;
  const data = 'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf';

  final bytes = <String>[
    'B',
    'V',
    '1',
    '0',
    '0',
    '0',
    '0',
    '0',
    '0',
    '0',
    '0',
    '0',
  ];
  var bvIndex = bytes.length - 1;

  BigInt tmp = (BigInt.one << 51) | BigInt.from(aid);
  tmp = tmp ^ BigInt.from(xorCode);

  while (tmp > BigInt.zero) {
    final remainder = tmp % BigInt.from(base);
    bytes[bvIndex] = data[remainder.toInt()];
    tmp = tmp ~/ BigInt.from(base);
    bvIndex--;
  }

  _swap(bytes, 3, 9);
  _swap(bytes, 4, 7);

  return bytes.join();
}

void _swap(List<String> list, int i, int j) {
  final temp = list[i];
  list[i] = list[j];
  list[j] = temp;
}
