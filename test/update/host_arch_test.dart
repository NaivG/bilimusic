import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/update/logic/host_arch.dart';

/// 构造一个最小的 PE 头：'MZ' → e_lfanew → 'PE\0\0' → Machine
Uint8List peImage(int machine, {int peOffset = 0x80}) {
  final bytes = Uint8List(peOffset + 0x20);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 0x5A4D, Endian.little);
  data.setInt32(0x3C, peOffset, Endian.little);
  data.setUint32(peOffset, 0x00004550, Endian.little);
  data.setUint16(peOffset + 4, machine, Endian.little);
  return bytes;
}

/// 构造一个最小的 ELF 头：[ei_data] 1 = 小端、2 = 大端
Uint8List elfImage(int machine, {int eiData = 1}) {
  final bytes = Uint8List(0x40);
  bytes.setRange(0, 4, const [0x7F, 0x45, 0x4C, 0x46]);
  bytes[4] = 2; // ELFCLASS64
  bytes[5] = eiData;
  ByteData.sublistView(bytes)
      .setUint16(0x12, machine, eiData == 1 ? Endian.little : Endian.big);
  return bytes;
}

void main() {
  group('archFromHeader', () {
    test('PE 的 ARM64 / ARM64EC 都算 arm64', () {
      expect(archFromHeader(peImage(0xAA64)), HostArch.arm64);
      expect(archFromHeader(peImage(0xA641)), HostArch.arm64);
    });

    test('PE 的 x64 是 x64，x86 认不出来', () {
      expect(archFromHeader(peImage(0x8664)), HostArch.x64);
      expect(archFromHeader(peImage(0x014C)), HostArch.unknown);
    });

    test('e_lfanew 指向的 PE 头越界 / 不对都返回 unknown', () {
      final truncated = peImage(0xAA64, peOffset: 0x100);
      expect(archFromHeader(truncated.sublist(0, 0x100)), HostArch.unknown);

      final wrongMagic = peImage(0xAA64);
      wrongMagic.fillRange(0x80, 0x84, 0x00);
      expect(archFromHeader(wrongMagic), HostArch.unknown);
    });

    test('ELF 的 e_machine 按 EI_DATA 指定的字节序读（AArch64 / x86_64）', () {
      expect(archFromHeader(elfImage(0xB7)), HostArch.arm64);
      expect(archFromHeader(elfImage(0x3E)), HostArch.x64);
      expect(archFromHeader(elfImage(0xB7, eiData: 2)), HostArch.arm64);
      expect(archFromHeader(elfImage(0x28)), HostArch.unknown); // EM_ARM
    });

    test('空 / 过短 / 既不是 PE 也不是 ELF 的数据返回 unknown', () {
      expect(archFromHeader(const []), HostArch.unknown);
      expect(archFromHeader(const [0x4D, 0x5A]), HostArch.unknown);
      expect(archFromHeader(Uint8List(4096)), HostArch.unknown);
    });
  });

  group('detectHostArch', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('host_arch_test');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('读文件头判架构（arm64 PE）', () async {
      final file = File('${temp.path}/app.exe');
      await file.writeAsBytes(peImage(0xAA64));
      expect(await detectHostArch(file.path), HostArch.arm64);
    });

    test('读文件头判架构（x64 ELF）', () async {
      final file = File('${temp.path}/app');
      await file.writeAsBytes(elfImage(0x3E));
      expect(await detectHostArch(file.path), HostArch.x64);
    });

    test('路径不存在 / 是目录时返回 unknown，不抛异常', () async {
      expect(
        await detectHostArch('${temp.path}/missing.exe'),
        HostArch.unknown,
      );
      expect(await detectHostArch(temp.path), HostArch.unknown);
    });

    test('本机可执行文件在 Windows / Linux 上能读出架构', () async {
      final arch = await detectHostArch(Platform.resolvedExecutable);
      // macOS 是 Mach-O，不在识别范围内
      if (Platform.isWindows || Platform.isLinux) {
        expect(arch, isNot(HostArch.unknown));
      }
    });
  });
}
