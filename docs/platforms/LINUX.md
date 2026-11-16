# Linux — план и фичи (этап M9)

> **Актуальная спецификация (09.11.2026):** перед началом работ по Linux обязательно читать **[../silentgate_linux_gateway_spec.md](../silentgate_linux_gateway_spec.md)** и соответствующий раздел в [../BACKLOG.md](../BACKLOG.md). Вместо описанного ниже старого наброска (`hev-socks5-tunnel` и несуществующего `DesktopEngine`) на Ubuntu 24.04 LTS уже проверена штатная архитектура `LinuxEngine` (`Xray-core + sing-box` `sg-tun0`), Headless CLI и режим изолированного L3-шлюза (`--gateway-iface`, `nftables` fail-closed kill-switch, `resolvectl revert sg-tun0`, `rp_filter=0`, DNS DNAT и MSS clamping).

Переиспользует общий Flutter-код и базовый контракт `engine/engine_base.dart` + `core/xray/` + `core/singbox/`.

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
