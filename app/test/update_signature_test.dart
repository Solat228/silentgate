import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/update/update_pubkey.dart';
import 'package:silentgate/core/update/update_signature.dart';

/// ПОДПИСЬ МАНИФЕСТА ОБНОВЛЕНИЙ: ЧТО ПРИНИМАЕТСЯ, ЧТО НЕТ, И ЧТО НЕ ПАДАЕТ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. `UpdateSignature.verify` — единственная дверь между
/// «скачали файл с GitHub» и «запускаем установщик». Сюда прилетает всё, что
/// отдал сервер: битый base64, пустая строка, подпись не той длины. Любой
/// выброс исключения на этом пути = либо падение проверки обновлений, либо
/// (хуже) `catch`, который кто-нибудь однажды напишет как «ну считаем, что
/// подпись верна». Поэтому контракт один: `verify` возвращает `false` и
/// НИКОГДА не бросает.
///
/// Сама криптография сверяется с вектором RFC 8032 (§7.1, test 1): если наш
/// обёртка или пакет считают Ed25519 неправильно, подпись, сделанная любым
/// другим инструментом, не пройдёт — и наоборот.
void main() {
  // RFC 8032 §7.1, TEST 1: пустое сообщение.
  //
  // ⚠️ Публичный ключ сверять по RFC, а не по памяти: в брифе этой задачи
  // хвост ключа был переписан по памяти неверно (`…daec2f7f…`), и тест
  // «падал» на исправной библиотеке. Подпись ниже — ровно из RFC, а Ed25519
  // хэширует публичный ключ внутрь подписи, поэтому единственный ключ, под
  // которым она проходит, и есть ключ RFC: `…daa62325af021a68f707511a`.
  const rfcSeedHex =
      '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
  const rfcPubHex =
      'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
  const rfcSigHex =
      'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb882'
      '1590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';

  List<int> hex(String s) => [
        for (var i = 0; i < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ];

  final rfcSeed = hex(rfcSeedHex);
  final rfcPubBase64 = base64.encode(hex(rfcPubHex));
  final rfcSigBase64 = base64.encode(hex(rfcSigHex));

  group('UpdateSignature: вектор RFC 8032', () {
    test('sign даёт ровно подпись из RFC на пустом сообщении', () {
      expect(UpdateSignature.sign(const [], rfcSeed), rfcSigBase64);
    });

    test('verify принимает подпись из RFC', () {
      expect(
        UpdateSignature.verify(const [], rfcSigBase64,
            publicKeyBase64: rfcPubBase64),
        isTrue,
      );
    });

    test('ключ, выведенный из seed, совпадает с RFC', () {
      final priv = ed.newKeyFromSeed(Uint8List.fromList(rfcSeed));
      expect(base64.encode(ed.public(priv).bytes), rfcPubBase64);
    });
  });

  group('UpdateSignature: отказы', () {
    final msg = utf8.encode('{"version":"1.14.1"}');
    final sig = UpdateSignature.sign(msg, rfcSeed);

    test('чужой ключ → false', () {
      final other = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);
      final otherPub =
          base64.encode(ed.public(ed.newKeyFromSeed(Uint8List.fromList(other))).bytes);
      expect(UpdateSignature.verify(msg, sig, publicKeyBase64: otherPub), isFalse);
    });

    test('изменённый байт сообщения → false', () {
      final tampered = List<int>.from(msg);
      tampered[3] ^= 0x01;
      expect(
        UpdateSignature.verify(tampered, sig, publicKeyBase64: rfcPubBase64),
        isFalse,
      );
    });

    test('изменённый байт подписи → false', () {
      final raw = base64.decode(sig);
      raw[10] ^= 0x01;
      expect(
        UpdateSignature.verify(msg, base64.encode(raw),
            publicKeyBase64: rfcPubBase64),
        isFalse,
      );
    });

    test('битый base64 подписи → false, не исключение', () {
      for (final bad in ['', '   ', '!!!not-base64!!!', 'AAAA', 'AA', '=', 'ÿÿ']) {
        expect(
          () => UpdateSignature.verify(msg, bad, publicKeyBase64: rfcPubBase64),
          returnsNormally,
          reason: 'подпись «$bad» должна давать false, а не бросать',
        );
        expect(
          UpdateSignature.verify(msg, bad, publicKeyBase64: rfcPubBase64),
          isFalse,
          reason: 'подпись «$bad»',
        );
      }
    });

    test('подпись не той длины (валидный base64) → false', () {
      final short = base64.encode(List<int>.filled(63, 1));
      final long = base64.encode(List<int>.filled(65, 1));
      expect(UpdateSignature.verify(msg, short, publicKeyBase64: rfcPubBase64),
          isFalse);
      expect(UpdateSignature.verify(msg, long, publicKeyBase64: rfcPubBase64),
          isFalse);
    });

    test('битый или не той длины публичный ключ → false, не исключение', () {
      // Пакет ed25519_edwards БРОСАЕТ ArgumentError на ключе не в 32 байта —
      // наша обёртка обязана это проглотить.
      for (final badKey in ['', '???', base64.encode(List<int>.filled(31, 1)),
          base64.encode(List<int>.filled(33, 1))]) {
        expect(
          () => UpdateSignature.verify(msg, sig, publicKeyBase64: badKey),
          returnsNormally,
          reason: 'ключ «$badKey»',
        );
        expect(UpdateSignature.verify(msg, sig, publicKeyBase64: badKey), isFalse,
            reason: 'ключ «$badKey»');
      }
    });

    test('sign с seed не в 32 байта — ArgumentError (ошибка вызывающего)', () {
      expect(() => UpdateSignature.sign(msg, List<int>.filled(31, 0)),
          throwsArgumentError);
    });
  });

  group('UpdateSignature: вшитый ключ', () {
    test('kUpdatePublicKeyBase64 декодируется ровно в 32 байта', () {
      expect(base64.decode(kUpdatePublicKeyBase64), hasLength(32));
    });

    test('вшитый ключ не совпадает с тестовым из RFC', () {
      // Тестовый seed опубликован в RFC — сборка, доверяющая ему, принимала бы
      // манифест, подписанный кем угодно.
      expect(kUpdatePublicKeyBase64, isNot(rfcPubBase64));
    });

    test('verify по умолчанию проверяет именно вшитым ключом', () {
      // Подпись тестовым ключом со вшитым по умолчанию НЕ проходит; явная
      // передача тестового — проходит. Значит умолчание — не тестовый ключ.
      final msg = utf8.encode('manifest');
      final sig = UpdateSignature.sign(msg, rfcSeed);
      expect(UpdateSignature.verify(msg, sig), isFalse);
      expect(UpdateSignature.verify(msg, sig, publicKeyBase64: rfcPubBase64),
          isTrue);
    });
  });

  group('UpdateSignature: туда-обратно', () {
    test('sign → verify на своём ключе, на большом сообщении', () {
      final seed = List<int>.generate(32, (i) => (i * 31 + 11) & 0xff);
      final pub = base64
          .encode(ed.public(ed.newKeyFromSeed(Uint8List.fromList(seed))).bytes);
      final msg = List<int>.generate(100000, (i) => (i * 13) & 0xff);
      final sig = UpdateSignature.sign(msg, seed);
      expect(base64.decode(sig), hasLength(64));
      expect(UpdateSignature.verify(msg, sig, publicKeyBase64: pub), isTrue);
    });
  });
}
