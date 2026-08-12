import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/home_screen.dart' show TunToastStep, tunToastStep;
import 'package:silentgate/ui/widgets/app_toast.dart';

/// Страж закреплённой карточки прогресса (задача 7 плана 1.4.1).
///
/// Ловит три класса дефектов, которых не видит ни компилятор, ни `analyze`:
///  1. свёрнутость, положенная в `State` виджета: раскладку присылает поток
///     счётчиков, и следующий такт (а тем более следующий прогон, когда
///     карточку снимают целиком) вернул бы карточку развёрнутой. Ровно это
///     случилось в 1.3.0 с кнопкой сворачивания уведомления на Android;
///  2. второй экземпляр экрана: карточка живёт в Overlay навигатора и
///     обновляется поверх уже открытых экранов, поэтому «просто push» на каждое
///     нажатие кладёт на стек копию за копией;
///  3. карточка, которая не уходит никогда: обратный отсчёт заводится только
///     по `finished: true`, а отменённый подбор стека TUN итога не даёт.
///
/// ⚠️ `pumpAndSettle` при живой карточке прогресса зависает: внутри неё
/// бесконечный `CircularProgressIndicator`. Пампим явными интервалами.
void main() {
  late BuildContext ctx;

  /// Дать карточкам доехать. ⚠️ Двумя кадрами: анимация появления стартует
  /// внутри ПЕРВОЙ сборки карточки, поэтому одиночный `pump(300ms)` меряет её
  /// в стартовой точке слайда — карточка оказывается на 22 px ниже места.
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpHost(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('главный'));
      }),
    ));
    await t.pump();
  }

  // Реестр карточек статический и переживает пересоздание дерева: без сброса
  // соседний тест видел бы свёрнутость и карточки предыдущего.
  setUp(() {
    AppToast.resetProgressForTest();
    AppToast.dismiss();
  });

  group('Закреплённая карточка: сворачивание живёт в реестре', () {
    testWidgets('свёрнутость переживает такты счётчиков', (t) async {
      await pumpHost(t);
      AppToast.progress(ctx,
          id: 'autoconfig',
          message: 'Кандидат 1 из 40',
          value: 0.025,
          pinned: true);
      await settle(t);

      expect(find.byIcon(Icons.unfold_less), findsOneWidget,
          reason: 'у закреплённой карточки обязана быть кнопка сворачивания');

      await t.tap(find.byIcon(Icons.unfold_less));
      await settle(t);
      expect(find.byIcon(Icons.unfold_more), findsOneWidget,
          reason: 'после нажатия карточка свёрнута (кнопка стала «развернуть»)');

      // Такты прогресса — то самое, что возвращало карточку развёрнутой.
      for (var i = 2; i <= 8; i++) {
        AppToast.progress(ctx,
            id: 'autoconfig',
            message: 'Кандидат $i из 40',
            value: i / 40,
            pinned: true);
        await settle(t);
      }

      expect(find.byIcon(Icons.unfold_more), findsOneWidget,
          reason: 'семь тактов подряд не имеют права развернуть карточку');
      expect(find.byIcon(Icons.unfold_less), findsNothing);
    });

    testWidgets('свёрнутость переживает снятие карточки и новый прогон',
        (t) async {
      await pumpHost(t);
      AppToast.progress(ctx,
          id: 'autoconfig', message: 'Кандидат 1 из 40', pinned: true);
      await settle(t);
      await t.tap(find.byIcon(Icons.unfold_less));
      await settle(t);

      // Штатная смерть карточки: после прогона её сносят, а с пустым списком
      // уходит и сам оверлей — вместе с любым состоянием внутри виджета.
      AppToast.dismissProgress('autoconfig');
      await settle(t);
      expect(find.textContaining('Кандидат'), findsNothing);

      AppToast.progress(ctx,
          id: 'autoconfig', message: 'Кандидат 1 из 12', pinned: true);
      await settle(t);

      expect(find.byIcon(Icons.unfold_more), findsOneWidget,
          reason: 'выбор пользователя пережил снятие карточки — значит он '
              'лежит в реестре, а не в State виджета');
    });

    testWidgets('обычная карточка кнопки сворачивания не получает', (t) async {
      await pumpHost(t);
      AppToast.progress(ctx, id: 'ping', message: 'Пинг 3 из 40', value: 0.075);
      await settle(t);

      expect(find.text('Пинг 3 из 40'), findsOneWidget);
      expect(find.byIcon(Icons.unfold_less), findsNothing,
          reason: 'у карточек, которые уходят сами, сворачивать нечего');
      expect(find.byIcon(Icons.unfold_more), findsNothing);
    });
  });

  group('Закреплённая карточка: нажатие', () {
    testWidgets('нажатие по карточке вызывает обработчик', (t) async {
      await pumpHost(t);
      var taps = 0;
      AppToast.progress(ctx,
          id: 'autoconfig',
          message: 'Идёт подбор',
          pinned: true,
          tapTooltip: 'Открыть автонастройку',
          onTap: () => taps++);
      await settle(t);

      await t.tap(find.text('Идёт подбор'));
      await settle(t);
      expect(taps, 1);
    });

    testWidgets('обработчик не теряется между тактами прогресса', (t) async {
      await pumpHost(t);
      var taps = 0;
      for (var i = 1; i <= 3; i++) {
        AppToast.progress(ctx,
            id: 'autoconfig',
            message: 'Кандидат $i',
            pinned: true,
            onTap: () => taps++);
        await settle(t);
      }
      await t.tap(find.text('Кандидат 3'));
      await settle(t);
      expect(taps, 1);
    });

    testWidgets('повторное нажатие не открывает второй экран', (t) async {
      await pumpHost(t);

      // ⚠️ Без `await`: карточка вызывает `openOnce` именно так (`unawaited`),
      // и ждать здесь нельзя — future живёт, пока экран не закроют.
      void tapCard() {
        AppToast.openOnce(ctx,
            key: 'autoconfig',
            builder: (_) => const Scaffold(body: Text('АВТОНАСТРОЙКА')));
      }

      // Первое нажатие открывает экран.
      tapCard();
      await t.pumpAndSettle();
      expect(find.text('АВТОНАСТРОЙКА'), findsOneWidget);

      // Второе — карточка всё это время жива поверх открытого экрана.
      tapCard();
      await t.pumpAndSettle();
      expect(find.text('АВТОНАСТРОЙКА'), findsOneWidget,
          reason: 'второй экземпляр экрана класть на стек нельзя');

      // Доказательство, что push был ровно один: одного «назад» хватает.
      Navigator.of(ctx).pop();
      await t.pumpAndSettle();
      expect(find.text('главный'), findsOneWidget);
      expect(find.text('АВТОНАСТРОЙКА'), findsNothing);
    });

    testWidgets('экран, открытый мимо карточки, тоже не дублируется', (t) async {
      await pumpHost(t);
      // Так его открывает меню сервера (`server_tile`) — про наш ключ оно не
      // знает, поэтому гейт смотрит ещё и на то, открыто ли что-то поверх.
      Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('АВТОНАСТРОЙКА'))));
      await t.pumpAndSettle();

      AppToast.openOnce(ctx,
          key: 'autoconfig',
          builder: (_) => const Scaffold(body: Text('АВТОНАСТРОЙКА')));
      await t.pumpAndSettle();
      expect(find.text('АВТОНАСТРОЙКА'), findsOneWidget);

      Navigator.of(ctx).pop();
      await t.pumpAndSettle();
      expect(find.text('главный'), findsOneWidget);
      expect(find.text('АВТОНАСТРОЙКА'), findsNothing);
    });
  });

  group('Остальные уведомления работают как раньше', () {
    testWidgets('обычное уведомление уходит само', (t) async {
      await pumpHost(t);
      AppToast.show(ctx, 'Подписка обновлена',
          duration: const Duration(seconds: 1));
      await t.pump();
      await settle(t);
      expect(find.text('Подписка обновлена'), findsOneWidget);

      await t.pump(const Duration(seconds: 1));
      await settle(t);
      await settle(t);
      expect(find.text('Подписка обновлена'), findsNothing,
          reason: 'стопка обычных уведомлений не должна была измениться');
    });

    testWidgets('закреплённая стоит ниже обычной и не прыгает от соседей',
        (t) async {
      await pumpHost(t);
      AppToast.progress(ctx,
          id: 'autoconfig', message: 'Подбор', pinned: true);
      await settle(t);
      final alone = t.getTopLeft(find.text('Подбор')).dy;

      AppToast.progress(ctx, id: 'ping', message: 'Пинг');
      await settle(t);
      expect(t.getTopLeft(find.text('Подбор')).dy, alone,
          reason: 'закреплённую карточку соседи двигать не могут');
      expect(t.getTopLeft(find.text('Пинг')).dy, lessThan(alone),
          reason: 'обычные встают НАД закреплённой, а не под неё');

      AppToast.dismissProgress('ping');
      await settle(t);
      expect(t.getTopLeft(find.text('Подбор')).dy, alone);
    });
  });

  group('Карточка без итога снимается, а не висит вечно', () {
    testWidgets('dismissProgress убирает незавершённую карточку', (t) async {
      await pumpHost(t);
      AppToast.progress(ctx,
          id: 'tun-autotune', message: 'Пробую system, MTU 1500');
      await settle(t);
      expect(find.text('Пробую system, MTU 1500'), findsOneWidget);

      AppToast.dismissProgress('tun-autotune');
      await settle(t);
      expect(find.text('Пробую system, MTU 1500'), findsNothing,
          reason: 'без этого карточка с крутящейся полоской висела бы до '
              'перезапуска приложения: отсчёт заводится только у finished');
    });

    testWidgets('снятие несуществующей карточки не трогает соседей', (t) async {
      await pumpHost(t);
      AppToast.progress(ctx, id: 'ping', message: 'Пинг 1 из 5');
      await settle(t);

      AppToast.dismissProgress('tun-autotune');
      await settle(t);
      expect(find.text('Пинг 1 из 5'), findsOneWidget);
    });

    test('решение по карточке подбора TUN', () {
      final t1 = DateTime(2026, 8, 12, 10);
      final t2 = DateTime(2026, 8, 12, 11);

      expect(
          tunToastStep(
              running: true,
              finishedAt: null,
              shownFinishedAt: null,
              cardLive: false),
          TunToastStep.progress);

      expect(
          tunToastStep(
              running: false,
              finishedAt: t2,
              shownFinishedAt: t1,
              cardLive: true),
          TunToastStep.summary,
          reason: 'новый исход — показываем итог');

      // Отмена: `TunAutotuneTracking.next` гасит running и НЕ ставит finishedAt.
      expect(
          tunToastStep(
              running: false,
              finishedAt: null,
              shownFinishedAt: null,
              cardLive: true),
          TunToastStep.dismiss,
          reason: 'подбор отменили — итога нет, карточку надо снять');
      expect(
          tunToastStep(
              running: false,
              finishedAt: t1,
              shownFinishedAt: t1,
              cardLive: true),
          TunToastStep.dismiss,
          reason: 'отмена при уже показанном старом исходе — тот же случай');

      expect(
          tunToastStep(
              running: false,
              finishedAt: t1,
              shownFinishedAt: t1,
              cardLive: false),
          TunToastStep.none,
          reason: 'итог показан и досчитывает свои 10 секунд — не трогать, '
              'иначе он исчезал бы, не дав себя прочитать');
      expect(
          tunToastStep(
              running: false,
              finishedAt: null,
              shownFinishedAt: null,
              cardLive: false),
          TunToastStep.none,
          reason: 'подбора не было вовсе — снимать нечего');
    });
  });
}
