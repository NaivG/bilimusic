import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/web_ticket.dart';

/// bili_ticket（GenWebTicket）与 WBI 口令 URL 的解析。
void main() {
  const imgKey = '7cd084941338484aae1ad9425b84077c';
  const subKey = '4932caff0ff746eab6f01bf08b70ac45';

  group('hexSign', () {
    test('HMAC-SHA256(key: XgwSnGZ1p, msg: ts<ts>) 的十六进制', () {
      expect(
        WebTicket.hexSign(1702204169),
        '4899d09c73cc357c191a77c41562ea9a7b07e858e534040cf2a24bbadbecbbbf',
      );
    });

    test('换 key 会换出不同的签名（key 是写死的，测试只为钉住形态）', () {
      expect(
        WebTicket.hexSign(1702204169, key: 'other'),
        isNot(WebTicket.hexSign(1702204169)),
      );
    });

    test('长度为 64 的小写十六进制', () {
      final sign = WebTicket.hexSign(1);
      expect(sign, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sign), isTrue);
    });
  });

  group('wbiKeyFromUrl', () {
    test('取文件名去扩展名', () {
      expect(
        WebTicket.wbiKeyFromUrl('https://i0.hdslb.com/bfs/wbi/$imgKey.png'),
        imgKey,
      );
    });

    test('裸 key 原样返回', () {
      expect(WebTicket.wbiKeyFromUrl(subKey), subKey);
    });

    test('空串返回 null', () {
      expect(WebTicket.wbiKeyFromUrl(''), isNull);
    });
  });

  group('tryParse', () {
    test('解析票据本体，并顺带取到 WBI 口令', () {
      final ticket = WebTicket.tryParse({
        'code': 0,
        'data': {
          'ticket': 'jwt-ticket',
          'created_at': 1702204169,
          'ttl': 259200,
          'nav': {
            'img': 'https://i0.hdslb.com/bfs/wbi/$imgKey.png',
            'sub': 'https://i0.hdslb.com/bfs/wbi/$subKey.png',
          },
        },
      });

      expect(ticket, isNotNull);
      expect(ticket!.ticket, 'jwt-ticket');
      expect(ticket.ttlSeconds, 259200);
      expect(ticket.imgKey, imgKey);
      expect(ticket.subKey, subKey);
    });

    test('过期判定按 created_at + ttl（秒）', () {
      final ticket = WebTicket(
        ticket: 'jwt',
        createdAt: 1702204169,
        ttlSeconds: 259200,
      );

      expect(
        ticket.isExpiredAt(
          DateTime.fromMillisecondsSinceEpoch((1702204169 + 1000) * 1000),
        ),
        isFalse,
      );
      expect(
        ticket.isExpiredAt(
          DateTime.fromMillisecondsSinceEpoch((1702204169 + 259200) * 1000),
        ),
        isTrue,
      );
    });

    test('结构不符时返回 null（票据只是降风控，不该中断启动）', () {
      expect(WebTicket.tryParse(null), isNull);
      expect(WebTicket.tryParse('not a map'), isNull);
      expect(WebTicket.tryParse({'code': -1, 'data': {}}), isNull);
      expect(WebTicket.tryParse({'code': 0, 'data': {}}), isNull);
      expect(
        WebTicket.tryParse({
          'code': 0,
          'data': {'ticket': ''},
        }),
        isNull,
      );
    });

    test('缺 created_at / ttl 时退化成默认值', () {
      final ticket = WebTicket.tryParse({
        'code': 0,
        'data': {'ticket': 'jwt'},
      });

      expect(ticket, isNotNull);
      expect(ticket!.createdAt, 0);
      expect(ticket.ttlSeconds, 259200);
      expect(ticket.imgKey, isNull);
      expect(ticket.subKey, isNull);
    });
  });
}
