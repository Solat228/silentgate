# Linux — план и фичи (этап M9)

Переиспользует общий Flutter-код и desktop-логику движка (как Windows/macOS).

---

## Стек

- UI: общий Flutter-код (`flutter create --platforms=linux .`).
- Движок: `xray` отдельным процессом + системный прокси (GSettings/`gsettings set org.gnome.system.proxy`)
  или TUN (`tun` + `hev-socks5-tunnel`, права через `setcap`/polkit-хелпер).
- Общий `DesktopEngine` с Windows/macOS, специфична только установка прокси/TUN.

---

## Задачи

- [ ] `DesktopEngine` c абстракцией установки системного прокси по среде (GNOME/KDE).
- [ ] Сборка `xray` под Linux x64/arm64, раскладка ассетов рядом с бинарником.
- [ ] Упаковка: AppImage (портативно), затем `.deb`/`.rpm` (как у Happ desktop).
- [ ] Автозапуск (`.desktop` в autostart), трей (если DE поддерживает).

## Особенности

- Зоопарк окружений (GNOME/KDE/прочие) — установка системного прокси различается; TUN надёжнее, но требует прав.
- Flutter Linux требует GTK-зависимостей на машине сборки.
- Наименее приоритетная платформа — делать после стабилизации Windows/macOS desktop-кода.
