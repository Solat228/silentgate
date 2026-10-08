import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/platform_services.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/tun_task_result_text.dart';

/// «UAC отклонён» — только когда права действительно не дали.
///
/// ⚠️ Прежде этот текст ставился на любой отказ создания задачи, включая
/// случай, когда UAC не спрашивался вовсе, а Планировщик отвергал саму
/// команду. Человек жал «Да» в окне прав и читал, что отказал сам.
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    test('${locale.languageCode}: три исхода — три разных текста', () async {
      final l = await AppLocalizations.delegate.load(locale);
      final done = tunTaskResultText(l, PrivilegeSetupResult.done);
      final denied = tunTaskResultText(l, PrivilegeSetupResult.denied);
      final failed = tunTaskResultText(l, PrivilegeSetupResult.failed);
      expect({done, denied, failed}.length, 3);
      expect(done, l.tunTaskDone);
      expect(denied, l.tunTaskFailed);
      expect(failed, l.tunTaskSchedulerFailed);
    });
  }

  test('ru: отказ Планировщика не винит UAC', () async {
    final l = await AppLocalizations.delegate.load(const Locale('ru'));
    expect(tunTaskResultText(l, PrivilegeSetupResult.failed),
        isNot(contains('UAC')));
  });
}
