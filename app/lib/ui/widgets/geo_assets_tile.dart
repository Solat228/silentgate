import 'package:flutter/material.dart';

import '../../core/geo/geo_assets.dart';
import '../../l10n/gen/app_localizations.dart';
import 'app_toast.dart';
import 'info_tooltip.dart';

/// Строка «Гео-базы маршрутизации»: состояние и кнопка скачивания.
///
/// ⚠️ ПОЧЕМУ ЭТО ВООБЩЕ ЕСТЬ НА ЭКРАНЕ, А НЕ ДЕЛАЕТСЯ САМО. Файлы весят около
/// 30 МБ — это трафик пользователя, часто мобильный. Качать столько без спроса
/// нельзя. При этом молчать тоже нельзя: без баз правила панели по странам и
/// категориям не применяются, и человек будет считать, что они работают.
/// Поэтому состояние видно всегда, а решение принимает он.
class GeoAssetsTile extends StatefulWidget {
  const GeoAssetsTile({super.key});

  @override
  State<GeoAssetsTile> createState() => _GeoAssetsTileState();
}

class _GeoAssetsTileState extends State<GeoAssetsTile> {
  GeoAssetsStatus? _status;
  bool _busy = false;
  String _stage = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await GeoAssets.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _download() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      // Первый файл известен заранее — подставляем его сразу.
      // Раньше здесь была пустая строка, и до первого колбэка подпись читалась
      // как «Скачиваю ……» с двойным многоточием: в строке перевода своё, и
      // заглушка добавляла второе.
      _stage = 'geoip.dat';
    });
    final err = await GeoAssets.download(
      onProgress: (f) {
        if (mounted) setState(() => _stage = f);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (!mounted) return;
    if (err == null) {
      AppToast.show(context, l.geoDone, kind: ToastKind.success);
    } else {
      // Причину показываем целиком: «не удалось» без неё не даёт ничего сделать.
      AppToast.show(context, l.geoFailed(err), kind: ToastKind.warning);
    }
  }

  static String _size(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = _status;
    final present = s?.present == true;
    return ListTile(
      dense: true,
      leading: Icon(Icons.public,
          color: present ? null : Theme.of(context).colorScheme.tertiary),
      title: Row(children: [
        Flexible(child: Text(l.geoTitle)),
        InfoTooltip(l.infoGeoAssets, title: l.geoTitle),
      ]),
      subtitle: Text(
        _busy
            ? l.geoDownloading(_stage)
            : present
                ? l.geoPresent(_size(s!.bytes),
                    s.updatedAt == null ? '—' : _date(s.updatedAt!))
                : l.geoMissing,
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: _download,
              child: Text(present ? l.geoUpdate : l.geoDownload),
            ),
    );
  }
}
