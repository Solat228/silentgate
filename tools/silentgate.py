"""Минимальная обёртка над локальным API SilentGate.

Требует только `requests` (``pip install requests``). Токен и порт берутся из
настроек приложения: Настройки -> API для автоматизации (там же кнопка
«Скопировать пример для Python» — отдаёт уже заполненный фрагмент с реальным
токеном).

Подробности протокола, коды ответов и раздел «Безопасность» — в docs/API.md.

⚠️ Порты выходов (см. exits()) ОБЯЗАНЫ читаться из /v1/exits на каждый вызов
proxies_for(), а не запоминаться числом заранее: раскладка портов
пересчитывается при каждом изменении списка «серверов с отдельным портом» в
настройках, и захардкоженный номер рано или поздно уведёт трафик не туда.
"""
from __future__ import annotations

import requests


class SilentGateError(RuntimeError):
    """Ошибка ответа API — сообщение и код берутся из тела {"error": {...}}."""

    def __init__(self, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


class SilentGate:
    """Клиент локального API SilentGate (только Windows, только 127.0.0.1)."""

    def __init__(self, token: str, host: str = "127.0.0.1", port: int = 10870):
        if not token:
            # Пустой токен на стороне приложения означает «канал не поднят
            # вовсе» — здесь та же логика: нет смысла открывать сессию requests
            # ради гарантированных 401.
            raise ValueError("нужен токен: Настройки -> API для автоматизации")
        self._base = f"http://{host}:{port}/v1"
        self._headers = {"Authorization": f"Bearer {token}"}
        self._token = token
        self._host = host
        self._session = requests.Session()

    def _raise_for_error(self, resp: requests.Response) -> None:
        """Читает {"error": {"code", "message"}} и превращает в SilentGateError.

        Обычный ``raise_for_status()`` отдал бы только код и текст HTTP —
        здесь же в теле уже лежит человекочитаемая причина (401/403/404/409),
        и молча её терять не стоит.
        """
        try:
            body = resp.json()
            err = body.get("error") if isinstance(body, dict) else None
        except ValueError:
            err = None
        if err:
            raise SilentGateError(err.get("code", "unknown"), err.get("message", ""))
        resp.raise_for_status()

    def _get(self, path: str) -> dict:
        r = self._session.get(self._base + path, headers=self._headers, timeout=5)
        if r.status_code != 200:
            self._raise_for_error(r)
        return r.json()

    def _post(self, path: str, body: dict | None = None) -> dict:
        r = self._session.post(
            self._base + path, headers=self._headers, json=body or {}, timeout=30
        )
        if r.status_code != 200:
            self._raise_for_error(r)
        return r.json()

    # ── Чтение состояния ────────────────────────────────────────────────────

    def status(self) -> dict:
        """state/server/captureMode/connectedSeconds. См. docs/API.md §5."""
        return self._get("/status")

    def servers(self) -> list[dict]:
        """Все серверы активной подписки: key/name/country/protocol/pingMs/working."""
        return self._get("/servers")["servers"]

    def exits(self) -> list[dict]:
        """Серверы с отдельным портом + запись "Прямо" (serverKey=None, порт 10819).

        ⚠️ Это раскладка портов из настроек, а не список того, что реально
        слушает прямо сейчас — порт выхода отвечает, только когда VPN
        подключён и способ захвата — TUN либо «Только прокси» (docs/API.md §3).
        """
        return self._get("/exits")["exits"]

    def traffic(self) -> dict:
        """uplinkBytes/downlinkBytes текущей сессии (обнуляются новым connect)."""
        return self._get("/traffic")

    def subscription(self) -> dict:
        """title/usedBytes/totalBytes/unlimited/expiresAt. URL подписки не отдаётся никогда."""
        return self._get("/subscription")

    # ── Управление ──────────────────────────────────────────────────────────

    def connect(self, server_key: str | None = None, auto: bool = False) -> dict:
        """Подключиться к серверу по ключу либо включить режим «Авто».

        ⚠️ На уже живом канале это СМЕНА сервера, а не отключение — команда
        безопасна вызывать повторно, VPN не гаснет.
        """
        return self._post("/connect", {"server": server_key, "auto": auto})

    def connect_by_name(self, name: str) -> dict:
        """Подключиться по отображаемому имени — только для ручных проб.

        Панель меняет имена серверов когда угодно; для скриптов используйте
        connect(server_key=...) с ключом из servers().
        """
        return self._post("/connect", {"name": name})

    def disconnect(self) -> dict:
        """Отключить VPN. Идемпотентно — на уже выключенном тоже {"ok": True}."""
        return self._post("/disconnect")

    def ping(self) -> dict:
        """Запустить пинг всех серверов подписки; результат — потом через servers()."""
        return self._post("/ping")

    # ── Хелпер для requests ─────────────────────────────────────────────────

    def proxies_for(self, server_key: str | None) -> dict:
        """Прокси-словарь для requests.get(..., proxies=...).

        server_key=None — порт «Прямо» (мимо VPN, реальный IP): удобно, чтобы
        сравнить «через VPN» / «без VPN» одним и тем же кодом, не выключая
        туннель.
        """
        for e in self.exits():
            if e["serverKey"] == server_key:
                url = f"http://sg:{self._token}@{self._host}:{e['port']}"
                return {"http": url, "https": url}
        raise KeyError(f"нет порта для сервера {server_key!r} — включите его в "
                        "настройках (API для автоматизации -> серверы с отдельным портом)")


if __name__ == "__main__":
    import os

    sg = SilentGate(token=os.environ.get("SILENTGATE_TOKEN", "ВСТАВЬТЕ_ТОКЕН"))
    print(sg.status())
    for exit_ in sg.exits():
        print(exit_["name"], "->", exit_["port"])
