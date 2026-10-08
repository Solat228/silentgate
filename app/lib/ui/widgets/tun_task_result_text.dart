import '../../core/platform/platform_services.dart';
import '../../l10n/gen/app_localizations.dart';

/// Текст итога «создать задачу Планировщика» — общий для заметки на главном и
/// экрана TUN, чтобы одна и та же беда не называлась в двух местах по-разному.
///
/// ⚠️ «UAC отклонён» — ТОЛЬКО когда права действительно не дали. Прежде этот
/// текст ставился на любой отказ, и человек, только что нажавший «Да» в окне
/// UAC, читал, что он его отклонил.
String tunTaskResultText(AppLocalizations l, PrivilegeSetupResult result) =>
    switch (result) {
      PrivilegeSetupResult.done => l.tunTaskDone,
      PrivilegeSetupResult.denied => l.tunTaskFailed,
      PrivilegeSetupResult.failed => l.tunTaskSchedulerFailed,
    };
