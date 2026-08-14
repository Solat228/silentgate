import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silentgate/core/subscription/subscription_logo.dart';

/// Поиск логотипа подписки целиком на MockClient — сети не требует.
///
/// Разобранный живой случай (адрес и токен владельца сюда НЕ переносятся, хосты
/// выдуманные): панель на Express отдаёт страницу подписки по `/s/<токен>`,
/// cookie `session` не ставит, `/assets/*` у неё нет, а в HTML нет ни одного
/// `<img>` с логотипом — фирменный знак нарисован инлайновым `<svg>`, favicon
/// объявлен как `data:image/svg+xml` с эмодзи. Отрисовать нечего. Единственная
/// растровая картинка бренда, на которую панель указывает сама, — аватарка её
/// Telegram-страницы из заголовков `profile-web-page-url` / `support-url`.
void main() {
  const sub = 'https://panel.example.org/s/TOKEN123';

  /// Страница панели без логотипа: как у разобранной — инлайновый `<svg>`,
  /// favicon в `data:`-ссылке, картинки только у инструкций по приложениям.
  const brandlessPage = '''
<!DOCTYPE html><html><head>
<title>Example VPN | 100500</title>
<link rel="icon" type="image/svg+xml"
      href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg'></svg>">
</head><body>
<svg width="185" height="124" viewBox="0 0 185 124"><path d="M3 62V15.4z"/></svg>
<img width="30" height="30" src="data:image/png;base64,iVBORw0KGgo=">
<img class="rounded-2xl w-full" src="https://cdn.example.net/steps/1.jpg"
     alt="v2rayNG Step 1">
</body></html>
''';

  /// Разметка страницы t.me (аватарка — отдельным хостом-CDN).
  const tgPage = '''
<html><head>
<meta property="og:title" content="Example VPN">
</head><body>
<div class="tgme_page_photo">
<img class="tgme_page_photo_image"
     src="https://cdn4.telesco.pe/file/AVATAR_BLOB.jpg">
</div></body></html>
''';

  const avatar = 'https://cdn4.telesco.pe/file/AVATAR_BLOB.jpg';

  /// Ответ страницы подписки: заголовки бренда, как их шлёт разобранная панель.
  /// Имена заголовков в нижнем регистре — package:http их так нормализует.
  http.Response panelPage(
    String body, {
    String? webPage,
    String? support,
    String? cookie,
  }) =>
      http.Response(body, 200, headers: {
        'content-type': 'text/html; charset=utf-8',
        if (webPage != null) 'profile-web-page-url': webPage,
        if (support != null) 'support-url': support,
        if (cookie != null) 'set-cookie': cookie,
      });

  group('Панель без логотипа: аватарка Telegram из заголовков', () {
    test('profile-web-page-url → аватарка со страницы t.me', () async {
      final seen = <Uri>[];
      final client = MockClient((req) async {
        seen.add(req.url);
        if (req.url.host == 'panel.example.org') {
          return panelPage(brandlessPage,
              webPage: 'https://t.me/example_vpn_bot?start=profile_v2_777');
        }
        if (req.url.host == 't.me') return http.Response(tgPage, 200);
        return http.Response('', 404);
      });

      expect(await SubscriptionLogo(client: client).findUrl(sub), avatar);

      final tg = seen.firstWhere((u) => u.host == 't.me');
      expect(tg.path, '/example_vpn_bot');
      // Идентификатор владельца из ?start=… в Telegram не уезжает.
      expect(tg.query, isEmpty);
      // На хост панели за иконками не ходим: перебор путей запрещён.
      expect(seen.where((u) => u.host == 'panel.example.org').length, 1);
    });

    test('support-url берётся, когда profile-web-page-url нет', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'panel.example.org') {
          return panelPage(brandlessPage,
              support: 'https://t.me/example_vpn_bot?start=help_v2_777');
        }
        if (req.url.host == 't.me') return http.Response(tgPage, 200);
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), avatar);
    });

    test('profile-web-page-url важнее support-url', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'panel.example.org') {
          return panelPage(brandlessPage,
              webPage: 'https://t.me/primary_bot',
              support: 'https://t.me/second_bot');
        }
        if (req.url.path == '/primary_bot') {
          return http.Response(tgPage, 200);
        }
        if (req.url.path == '/second_bot') {
          return http.Response(
              tgPage.replaceAll('AVATAR_BLOB', 'WRONG_BLOB'), 200);
        }
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), avatar);
    });

    test('t.me недоступен → null, а не исключение', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'panel.example.org') {
          return panelPage(brandlessPage, webPage: 'https://t.me/example_bot');
        }
        throw http.ClientException('handshake failed');
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), isNull);
    });

    test('заголовков бренда нет → на t.me не ходим вовсе', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'panel.example.org') {
          return panelPage(brandlessPage);
        }
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), isNull);
      expect(hosts, ['panel.example.org']);
    });

    test('нетелеграмная ссылка поддержки не тянется', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'panel.example.org') {
          return panelPage(brandlessPage,
              support: 'https://help.example.com/tickets');
        }
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), isNull);
      expect(hosts, ['panel.example.org']);
    });
  });

  group('SubscriptionLogo.telegramProfileUrl', () {
    test('обычная ссылка нормализуется, запрос отбрасывается', () {
      expect(
        SubscriptionLogo.telegramProfileUrl(
                'https://t.me/example_vpn_bot?start=profile_v2_777')
            ?.toString(),
        'https://t.me/example_vpn_bot',
      );
      expect(
        SubscriptionLogo.telegramProfileUrl('https://www.telegram.me/some_chan')
            ?.toString(),
        'https://t.me/some_chan',
      );
      expect(
        SubscriptionLogo.telegramProfileUrl('  https://t.me/name_here#frag  ')
            ?.toString(),
        'https://t.me/name_here',
      );
    });

    test('приглашения и служебные пути отвергаются', () {
      for (final raw in const [
        'https://t.me/+AbCdEfGh',
        'https://t.me/joinchat/AAAAAE',
        'https://t.me/c/1234567/89',
        'https://t.me/i/userpic/320/name.jpg',
        'https://t.me/proxy',
        'https://t.me/',
        'https://t.me/ab',
        'https://example.com/team',
        'tg://resolve?domain=example_bot',
        'мусор',
        null,
        '',
      ]) {
        expect(SubscriptionLogo.telegramProfileUrl(raw), isNull, reason: '$raw');
      }
    });
  });

  group('SubscriptionLogo.extractTelegramAvatar', () {
    test('берётся tgme_page_photo_image', () {
      expect(SubscriptionLogo.extractTelegramAvatar(tgPage), avatar);
    });

    test('фолбэк на og:image', () {
      const html = '<meta property="og:image" content="https://cdn.example/a.jpg">';
      expect(SubscriptionLogo.extractTelegramAvatar(html),
          'https://cdn.example/a.jpg');
    });

    test('страницы без картинки и относительные пути → null', () {
      expect(SubscriptionLogo.extractTelegramAvatar('<html></html>'), isNull);
      expect(
          SubscriptionLogo.extractTelegramAvatar(
              '<img class="tgme_page_photo_image" src="/local.jpg">'),
          isNull);
    });
  });

  group('extractLogoUrl: что отрисуется, а что нет', () {
    final base = Uri.parse('https://panel.example.org/s/TOKEN123');

    test('<img> с логотипом в class/id, когда alt не проставлен', () {
      expect(
        SubscriptionLogo.extractLogoUrl(
            '<img class="header site-logo" src="/img/brand.png">',
            base: base),
        'https://panel.example.org/img/brand.png',
      );
      expect(
        SubscriptionLogo.extractLogoUrl('<img id="logo" src="/l.jpg">',
            base: base),
        'https://panel.example.org/l.jpg',
      );
      // alt="logo" по-прежнему важнее.
      expect(
        SubscriptionLogo.extractLogoUrl(
            '<img class="logo" src="/wrong.png">'
            '<img alt="logo" src="/right.png">',
            base: base),
        'https://panel.example.org/right.png',
      );
    });

    test('favicon с ?v= больше не теряется', () {
      expect(
        SubscriptionLogo.extractLogoUrl(
            '<link rel="icon" href="/favicon.png?v=3">',
            base: base),
        'https://panel.example.org/favicon.png?v=3',
      );
    });

    test('SVG и ICO пропускаются — Image.file их не отрисует', () {
      expect(
          SubscriptionLogo.extractLogoUrl(
              '<link rel="icon" href="/favicon.svg">'
              '<link rel="shortcut icon" href="/favicon.ico">',
              base: base),
          isNull);
      expect(
          SubscriptionLogo.extractLogoUrl(
              '<link rel="apple-touch-icon" href="/touch.svg">',
              base: base),
          isNull);
      expect(
          SubscriptionLogo.extractLogoUrl('<img alt="logo" src="/brand.svg">',
              base: base),
          isNull);
      // Тип объявлен, расширения нет — тоже мимо.
      expect(
          SubscriptionLogo.extractLogoUrl(
              '<link rel="icon" type="image/x-icon" href="/favicon">',
              base: base),
          isNull);
    });

    test('data:-ссылки не берутся: качать нечего', () {
      expect(SubscriptionLogo.extractLogoUrl(brandlessPage, base: base), isNull);
    });
  });

  group('прежние стратегии не сдвинулись', () {
    test('брендинг Remnawave по cookie важнее Telegram-заголовка', () async {
      const logo = 'https://cdn.example.net/brand.png';
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'panel.example.org') {
          if (req.url.path == '/s/TOKEN123') {
            return panelPage(brandlessPage,
                webPage: 'https://t.me/example_vpn_bot',
                cookie: 'session=JWT.VAL; Path=/; Max-Age=1800; HttpOnly');
          }
          if (req.url.path == '/assets/.app-config-v2.json') {
            return http.Response(
                jsonEncode({
                  'brandingSettings': {'logoUrl': logo}
                }),
                200);
          }
        }
        return http.Response('', 404);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub), logo);
      expect(hosts.contains('t.me'), isFalse);
    });

    test('логотип в разметке панели важнее Telegram-заголовка', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'panel.example.org') {
          return panelPage('<img alt="logo" src="/own.png">',
              webPage: 'https://t.me/example_vpn_bot');
        }
        return http.Response(tgPage, 200);
      });
      expect(await SubscriptionLogo(client: client).findUrl(sub),
          'https://panel.example.org/own.png');
      expect(hosts.contains('t.me'), isFalse);
    });
  });
}
