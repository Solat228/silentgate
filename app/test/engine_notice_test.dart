import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';

/// Заметки движка — то, чего не хватило 08.08.2026.
///
/// ⚠️ ЧТО ИМЕННО СТЕРЕЖЁМ. У владельца VPN перестал работать, и он заметил это
/// сам: приложение промолчало. Причина не в том, что событие потерялось, а в
/// том, что его негде было показать — статус отвечает на вопрос «что сейчас», а
/// обрыв, восстановившийся за пару секунд, в нём не остаётся вовсе.
///
/// Раскладка событий согласована с владельцем: НЕ каждая попытка, а три штуки —
/// оборвалось, восстановилось, не удалось. Восьми всплывашек подряд человек не
/// читает, он их отмахивает, а вместе с ними пропускает и важную.
void main() {
  group('Разделение на «проблему» и «заметку»', () {
    test('обрыв и отказ требуют внимания', () {
      // Красный тост и более долгий показ: это то, из-за чего у пользователя
      // прямо сейчас не работает интернет.
      expect(
          const EngineNotice(EngineNoticeKind.reconnecting, 'x').isProblem,
          isTrue);
      expect(
          const EngineNotice(EngineNoticeKind.failed, 'x').isProblem, isTrue);
    });

    test('восстановление и блокировка — обычные заметки', () {
      // Восстановление это хорошая новость; блокировка — то, что пользователь
      // настроил сам. Красить их как ошибку значит обесценить настоящие ошибки.
      expect(
          const EngineNotice(EngineNoticeKind.recovered, 'x').isProblem,
          isFalse);
      expect(
          const EngineNotice(EngineNoticeKind.blocked, 'x').isProblem, isFalse);
    });
  });

  group('Состав события', () {
    test('уточнение необязательно', () {
      const n = EngineNotice(EngineNoticeKind.recovered, 'Соединение восстановлено');
      expect(n.detail, isNull);
      expect(n.text, isNotEmpty);
    });

    test('уточнение доезжает целиком', () {
      // В нём едет причина обрыва и имя домена — без них сообщение
      // превращается в «что-то случилось».
      const n = EngineNotice(EngineNoticeKind.blocked, 'Сайт заблокирован',
          detail: 'example.com');
      expect(n.detail, 'example.com');
    });

    test('все виды перечислены — набор закрыт', () {
      // Страж на случай, если кто-то добавит вид и забудет решить, проблема
      // это или заметка: тест упадёт и заставит подумать.
      expect(EngineNoticeKind.values, hasLength(6));
      for (final k in EngineNoticeKind.values) {
        final n = EngineNotice(k, 'x');
        expect(n.isProblem, isA<bool>());
      }
    });
  });
}
