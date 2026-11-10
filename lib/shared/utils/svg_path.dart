import 'dart:ui';

/// 把 SVG 路径数据（`<path d="…">`）解析成 [Path]。
///
/// 支持 M/L/H/V/C/S/Q/T/A/Z 与对应小写相对命令，够画内置的品牌图标；
/// 非法数据抛 [FormatException]。不做路径简化，一次解析结果由调用方缓存。
Path svgPathFromData(String data) => _SvgPathParser(data).parse();

class _SvgPathParser {
  _SvgPathParser(this.source);

  final String source;

  int _index = 0;

  // 当前点与子路径起点。
  double _x = 0;
  double _y = 0;
  double _startX = 0;
  double _startY = 0;

  // 上一条生效的命令，用于隐式重复（M/m 之后按 L/l 处理）。
  String? _command;

  // 上一段三次 / 二次贝塞尔的控制点，供 S / T 反射。
  double? _lastCubicX;
  double? _lastCubicY;
  double? _lastQuadX;
  double? _lastQuadY;

  Path parse() {
    final path = Path();
    while (true) {
      _skipSeparators();
      if (_index >= source.length) break;
      final command = _nextCommand();
      _command = command;
      switch (command) {
        case 'M':
        case 'm':
          final x = _readNumber();
          final y = _readNumber();
          if (command == 'm') {
            _x += x;
            _y += y;
          } else {
            _x = x;
            _y = y;
          }
          path.moveTo(_x, _y);
          _startX = _x;
          _startY = _y;
          _command = command == 'M' ? 'L' : 'l';
          _clearControls();
        case 'L':
        case 'l':
          final x = _readNumber();
          final y = _readNumber();
          _lineTo(path, x, y, relative: command == 'l');
        case 'H':
        case 'h':
          final x = _readNumber();
          _x = command == 'h' ? _x + x : x;
          path.lineTo(_x, _y);
          _clearControls();
        case 'V':
        case 'v':
          final y = _readNumber();
          _y = command == 'v' ? _y + y : y;
          path.lineTo(_x, _y);
          _clearControls();
        case 'C':
        case 'c':
          final x1 = _readNumber();
          final y1 = _readNumber();
          final x2 = _readNumber();
          final y2 = _readNumber();
          final x = _readNumber();
          final y = _readNumber();
          final relative = command == 'c';
          final cx1 = relative ? _x + x1 : x1;
          final cy1 = relative ? _y + y1 : y1;
          final cx2 = relative ? _x + x2 : x2;
          final cy2 = relative ? _y + y2 : y2;
          final endX = relative ? _x + x : x;
          final endY = relative ? _y + y : y;
          path.cubicTo(cx1, cy1, cx2, cy2, endX, endY);
          _lastCubicX = cx2;
          _lastCubicY = cy2;
          _lastQuadX = null;
          _lastQuadY = null;
          _x = endX;
          _y = endY;
        case 'S':
        case 's':
          final x2 = _readNumber();
          final y2 = _readNumber();
          final x = _readNumber();
          final y = _readNumber();
          final relative = command == 's';
          final cx2 = relative ? _x + x2 : x2;
          final cy2 = relative ? _y + y2 : y2;
          final endX = relative ? _x + x : x;
          final endY = relative ? _y + y : y;
          final cx1 = _lastCubicX == null ? _x : 2 * _x - _lastCubicX!;
          final cy1 = _lastCubicY == null ? _y : 2 * _y - _lastCubicY!;
          path.cubicTo(cx1, cy1, cx2, cy2, endX, endY);
          _lastCubicX = cx2;
          _lastCubicY = cy2;
          _lastQuadX = null;
          _lastQuadY = null;
          _x = endX;
          _y = endY;
        case 'Q':
        case 'q':
          final x1 = _readNumber();
          final y1 = _readNumber();
          final x = _readNumber();
          final y = _readNumber();
          final relative = command == 'q';
          final cx = relative ? _x + x1 : x1;
          final cy = relative ? _y + y1 : y1;
          final endX = relative ? _x + x : x;
          final endY = relative ? _y + y : y;
          path.quadraticBezierTo(cx, cy, endX, endY);
          _lastQuadX = cx;
          _lastQuadY = cy;
          _lastCubicX = null;
          _lastCubicY = null;
          _x = endX;
          _y = endY;
        case 'T':
        case 't':
          final x = _readNumber();
          final y = _readNumber();
          final relative = command == 't';
          final endX = relative ? _x + x : x;
          final endY = relative ? _y + y : y;
          final cx = _lastQuadX == null ? _x : 2 * _x - _lastQuadX!;
          final cy = _lastQuadY == null ? _y : 2 * _y - _lastQuadY!;
          path.quadraticBezierTo(cx, cy, endX, endY);
          _lastQuadX = cx;
          _lastQuadY = cy;
          _lastCubicX = null;
          _lastCubicY = null;
          _x = endX;
          _y = endY;
        case 'A':
        case 'a':
          final rx = _readNumber().abs();
          final ry = _readNumber().abs();
          final rotation = _readNumber();
          final largeArc = _readFlag();
          final clockwise = _readFlag();
          final x = _readNumber();
          final y = _readNumber();
          final relative = command == 'a';
          final endX = relative ? _x + x : x;
          final endY = relative ? _y + y : y;
          if (rx == 0 || ry == 0) {
            path.lineTo(endX, endY);
          } else {
            path.arcToPoint(
              Offset(endX, endY),
              radius: Radius.elliptical(rx, ry),
              rotation: rotation,
              largeArc: largeArc,
              clockwise: clockwise,
            );
          }
          _x = endX;
          _y = endY;
          _clearControls();
        case 'Z':
        case 'z':
          path.close();
          _x = _startX;
          _y = _startY;
          _clearControls();
          // Z 没有参数，后续坐标必须跟一个新命令，避免隐式重复成死循环。
          _command = null;
        default:
          throw FormatException('不支持的 SVG path 命令：$command');
      }
    }
    return path;
  }

  void _lineTo(Path path, double x, double y, {required bool relative}) {
    _x = relative ? _x + x : x;
    _y = relative ? _y + y : y;
    path.lineTo(_x, _y);
    _clearControls();
  }

  void _clearControls() {
    _lastCubicX = null;
    _lastCubicY = null;
    _lastQuadX = null;
    _lastQuadY = null;
  }

  String _nextCommand() {
    _skipSeparators();
    if (_index >= source.length) {
      throw const FormatException('SVG path 意外结束');
    }
    final char = source[_index];
    if (_isCommand(char)) {
      _index++;
      return char;
    }
    final last = _command;
    if (last == null) {
      throw FormatException('SVG path 缺少命令：$char');
    }
    return last;
  }

  double _readNumber() {
    _skipSeparators();
    final start = _index;
    if (_index < source.length &&
        (source[_index] == '+' || source[_index] == '-')) {
      _index++;
    }
    var hasDigits = false;
    while (_index < source.length && _isDigit(source[_index])) {
      _index++;
      hasDigits = true;
    }
    if (_index < source.length && source[_index] == '.') {
      _index++;
      while (_index < source.length && _isDigit(source[_index])) {
        _index++;
        hasDigits = true;
      }
    }
    if (!hasDigits) {
      throw FormatException('SVG path 在偏移 $_index 处缺少数字');
    }
    if (_index < source.length &&
        (source[_index] == 'e' || source[_index] == 'E')) {
      _index++;
      if (_index < source.length &&
          (source[_index] == '+' || source[_index] == '-')) {
        _index++;
      }
      while (_index < source.length && _isDigit(source[_index])) {
        _index++;
      }
    }
    return double.parse(source.substring(start, _index));
  }

  bool _readFlag() {
    _skipSeparators();
    if (_index >= source.length) {
      throw const FormatException('SVG path 圆弧标志缺失');
    }
    final char = source[_index];
    if (char != '0' && char != '1') {
      throw FormatException('SVG path 圆弧标志非法：$char');
    }
    _index++;
    return char == '1';
  }

  void _skipSeparators() {
    while (_index < source.length) {
      final char = source.codeUnitAt(_index);
      if (char == 0x20 ||
          char == 0x09 ||
          char == 0x0A ||
          char == 0x0D ||
          char == 0x0C ||
          char == 0x2C) {
        _index++;
      } else {
        break;
      }
    }
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isCommand(String char) {
    switch (char) {
      case 'M':
      case 'm':
      case 'L':
      case 'l':
      case 'H':
      case 'h':
      case 'V':
      case 'v':
      case 'C':
      case 'c':
      case 'S':
      case 's':
      case 'Q':
      case 'q':
      case 'T':
      case 't':
      case 'A':
      case 'a':
      case 'Z':
      case 'z':
        return true;
    }
    return false;
  }
}
