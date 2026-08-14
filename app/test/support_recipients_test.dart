import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/ui/settings_screen.dart';
import 'package:silentgate/ui/widgets/subscription_avatar.dart';

/// «Кому отправить» в отчёте поддержки.
///
/// ⚠️ ЗАМЕЧАНИЕ ВЛАДЕЛЬЦА (1.4.3): у пункта с именем подписки стояла общая
/// иконка поддержки — «заменить на аватарку самой подписки». Две кнопки рядом
/// отличались только словом в скобках, а отправить лог не тому адресату проще
/// всего именно здесь.
///
/// ⚠️ И ВТОРАЯ ЕГО ПОЛОВИНА: у кнопки «разработчику клиента» аватарки подписки
/// быть НЕ ДОЛЖНО — это другой адресат, чужой логотип рядом с ним прямо врал бы.
void main() {
  final l = AppLocalizationsRu();

  Future<void> pump(WidgetTester tester,
      {String serviceName = 'Silentgate VPN',
      String supportUrl = 'https://t.me/silentgate_support',
      String? logoPath}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SupportRecipients(
          serviceName: serviceName,
          supportUrl: supportUrl,
          logoPath: logoPath,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('у кнопки сервиса — аватарка подписки, а не общий значок',
      (tester) async {
    await pump(tester);

    final named = find.widgetWithText(
        FilledButton, l.supportContactNamed('Silentgate VPN'));
    expect(named, findsOneWidget, reason: 'кнопка сервиса обязана быть');
    expect(
        find.descendant(of: named, matching: find.byType(SubscriptionAvatar)),
        findsOneWidget,
        reason: 'ЗДЕСЬ БЫЛ ОБЩИЙ ЗНАЧОК: две кнопки различались только словом '
            'в скобках');
    expect(find.byIcon(Icons.support_agent), findsNothing,
        reason: 'прежний безликий значок поддержки заменён, а не добавлен');
  });

  testWidgets('⚠️ у кнопки разработчика аватарки подписки НЕТ', (tester) async {
    await pump(tester);

    final dev = find.widgetWithText(
        OutlinedButton, l.supportContactNamed(l.supportDevServiceName));
    expect(dev, findsOneWidget);
    expect(find.descendant(of: dev, matching: find.byType(SubscriptionAvatar)),
        findsNothing,
        reason: 'это другой адресат — чужой логотип рядом с ним врал бы');
    expect(find.descendant(of: dev, matching: find.byIcon(Icons.developer_mode)),
        findsOneWidget);
    // Аватарка на экране ровно одна — у той единственной кнопки, которой она
    // принадлежит.
    expect(find.byType(SubscriptionAvatar), findsOneWidget);
  });

  testWidgets('логотипа нет — аватарка всё равно своя (буква на градиенте)',
      (tester) async {
    // Логотип панель отдаёт не всегда, а кнопка обязана остаться узнаваемой:
    // `SubscriptionAvatar` в этом случае рисует первую букву названия.
    await pump(tester, logoPath: null);
    expect(find.byType(SubscriptionAvatar), findsOneWidget);
    expect(find.text('S'), findsOneWidget,
        reason: 'запасная аватарка — буква названия подписки');
  });

  testWidgets('ссылки на поддержку сервиса нет — нет и кнопки с аватаркой',
      (tester) async {
    // Отправлять некуда: показывать адресата, который никуда не ведёт, хуже,
    // чем не показывать его вовсе.
    await pump(tester, supportUrl: '');
    expect(find.byType(SubscriptionAvatar), findsNothing);
    expect(
        find.widgetWithText(
            OutlinedButton, l.supportContactNamed(l.supportDevServiceName)),
        findsOneWidget,
        reason: 'разработчик остаётся адресатом в любом случае');
  });

  testWidgets('название сервиса пустое — общая подпись, но кнопка своя',
      (tester) async {
    await pump(tester, serviceName: '');
    expect(find.widgetWithText(FilledButton, l.supportContact), findsOneWidget);
    expect(find.byType(SubscriptionAvatar), findsOneWidget);
  });
}
