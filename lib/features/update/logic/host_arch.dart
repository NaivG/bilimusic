import 'dart:io';
import 'dart:typed_data';

/// 探测当前进程所跑二进制的 CPU 架构。
///
/// Windows 取 PE 的 Machine 字段，Linux 取 ELF 的 e_machine。
enum HostArch {
  x64,

  /// 含 Windows 的 ARM64EC
  arm64,

  /// 文件头认不出来（不是 PE/ELF、被截断、读取失败）
  unknown;

  bool get isArm64 => this == HostArch.arm64;
}

/// 读取 [executablePath] 的文件头判断架构，认不出一律返回 [HostArch.unknown]
/// （调用方按 x64 兜底，与按架构分包之前的行为一致）。
Future<HostArch> detectHostArch(String executablePath) async {
  try {
    final raf = await File(executablePath).open();
    try {
      // PE 的 e_lfanew / ELF 头都在前 4 KB 内
      return archFromHeader(await raf.read(4096));
    } finally {
      await raf.close();
    }
  } catch (_) {
    return HostArch.unknown;
  }
}

/// 从可执行文件头字节解析架构（Windows PE / Linux ELF）
HostArch archFromHeader(List<int> header) {
  final bytes = ByteData.sublistView(Uint8List.fromList(header));
  return _peArch(bytes) ?? _elfArch(bytes) ?? HostArch.unknown;
}

const int _machineArm64 = 0xAA64;
const int _machineArm64Ec = 0xA641;
const int _machineX64 = 0x8664;

/// PE：'MZ' → 0x3C 处的 e_lfanew → 'PE\0\0' → Machine 字段
HostArch? _peArch(ByteData bytes) {
  if (bytes.lengthInBytes < 0x40) return null;
  if (bytes.getUint16(0, Endian.little) != 0x5A4D) return null;
  final peOffset = bytes.getInt32(0x3C, Endian.little);
  if (peOffset < 0 || peOffset + 6 > bytes.lengthInBytes) return null;
  if (bytes.getUint32(peOffset, Endian.little) != 0x00004550) return null;
  return switch (bytes.getUint16(peOffset + 4, Endian.little)) {
    _machineArm64 || _machineArm64Ec => HostArch.arm64,
    _machineX64 => HostArch.x64,
    _ => HostArch.unknown,
  };
}

/// ELF：0x7F 'E' 'L' 'F' → EI_DATA 定字节序 → 0x12 处的 e_machine
HostArch? _elfArch(ByteData bytes) {
  const magic = [0x7F, 0x45, 0x4C, 0x46];
  if (bytes.lengthInBytes < 0x14) return null;
  for (var i = 0; i < magic.length; i++) {
    if (bytes.getUint8(i) != magic[i]) return null;
  }
  final endian = switch (bytes.getUint8(5)) {
    1 => Endian.little,
    2 => Endian.big,
    _ => null,
  };
  if (endian == null) return null;
  return switch (bytes.getUint16(0x12, endian)) {
    0xB7 => HostArch.arm64, // EM_AARCH64
    0x3E => HostArch.x64, // EM_X86_64
    _ => HostArch.unknown,
  };
}
