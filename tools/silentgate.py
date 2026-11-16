"""Обёртка над локальным API SilentGate (1.18.7+).

Требует только `requests` (``pip install requests``). Токен и порт берутся из
настроек приложения: Настройки -> API для автоматизации.

Поддерживает:
- Фиксированный порт «Умный Автовыбор» (`10818`, `proxies_for("auto")` / `auto_proxies()`);
- Фиксированный порт «Прямо» (`10819`, `proxies_for(None)` / `direct_proxies()`);
- Липкие (`sticky`) и ручные порты отдельных серверов до 250 узлов (включая все
  профили «Авто» из всех подписок с дедупликацией общих нод);
- Работу во всех режимах захвата (`tun`, `systemProxy`, `proxyOnly`) и в
  автономном фоновом режиме при выключенном VPN;
- Управление подписками (`subscriptions()`, `select_subscription()`, `refresh_subscription()`),
  настройку выходов (`configure_exits()`) и живую проверку портов (`test_exit()`).
"""
from __future__ import annotations

import time
import urllib.parse
import requests


class SilentGateError(RuntimeError):
    """Ошибка ответа API — сообщение и код берутся из тела {"error": {...}}."""

    def __init__(self, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


class SilentGate:
    """Клиент локального API SilentGate (только Windows, только 127.0.0.1)."""

    def __init__(
        self,
        token: str,
        host: str = "127.0.0.1",
        port: int = 10870,
        proxy_user: str | None = None,
        proxy_password: str | None = None,
    ):
        if not token:
            raise ValueError("нужен токен: Настройки -> API для автоматизации")
        self._base = f"http://{host}:{port}/v1"
        self._headers = {"Authorization": f"Bearer {token}"}
        self._token = token
        self._host = host
        self._proxy_user = proxy_user
        self._proxy_password = proxy_password
        self._session = requests.Session()

    def _raise_for_error(self, resp: requests.Response) -> None:
        try:
            body = resp.json()
            err = body.get("error") if isinstance(body, dict) else None
        except ValueError:
            err = None
        if err:
            raise SilentGateError(err.get("code", "unknown"), err.get("message", ""))
        resp.raise_for_status()

    def _get(self, path: str, timeout: float = 15.0) -> dict:
        r = self._session.get(self._base + path, headers=self._headers, timeout=timeout)
        if r.status_code != 200:
            self._raise_for_error(r)
        return r.json()

    def _post(self, path: str, body: dict | None = None, timeout: float = 30.0) -> dict:
        r = self._session.post(
            self._base + path, headers=self._headers, json=body or {}, timeout=timeout
        )
        if r.status_code != 200:
            self._raise_for_error(r)
        return r.json()

    # ── Чтение состояния ────────────────────────────────────────────────────

    def status(self, verify: bool = False) -> dict:
        """Состояние клиента; при verify=True добавляет поле egress."""
        q = "?verify=1" if verify else ""
        return self._get(f"/status{q}", timeout=20.0 if verify else 5.0)

    def servers(self, all_subscriptions: bool = False) -> list[dict]:
        """Список серверов активной подписки или всех подписок (all_subscriptions=True)."""
        q = "?scope=all" if all_subscriptions else ""
        return self._get(f"/servers{q}")["servers"]

    def exits(self, verify: bool = False) -> list[dict]:
        """Активные прокси-порты: Умный Автовыбор (serverKey='auto'), серверы и Прямо (serverKey=None)."""
        q = "?verify=1" if verify else ""
        return self._get(f"/exits{q}", timeout=60.0 if verify else 5.0)["exits"]

    def traffic(self) -> dict:
        """uplinkBytes/downlinkBytes за время работы приложения."""
        return self._get("/traffic")

    def subscription(self) -> dict:
        """Сводка по активной подписке (title/usedBytes/totalBytes/unlimited/expiresAt)."""
        return self._get("/subscription")

    def subscriptions(self) -> list[dict]:
        """Список всех подписок с непрозрачными id (без секретных URL)."""
        return self._get("/subscriptions")["subscriptions"]

    # ── Управление ──────────────────────────────────────────────────────────

    def connect(self, server_key: str | None = None, auto: bool = False) -> dict:
        """Подключиться к серверу по id/ключу (поддерживает и серверы других подписок) или включить Авто."""
        return self._post("/connect", {"server": server_key, "auto": auto})

    def connect_by_name(self, name: str) -> dict:
        """Подключиться по отображаемому имени."""
        return self._post("/connect", {"name": name})

    def disconnect(self) -> dict:
        """Отключить VPN."""
        return self._post("/disconnect")

    def ping(self, all_subscriptions: bool = False) -> dict:
        """Запустить фоновый пинг серверов (активной подписки или всех подписок)."""
        body = {"scope": "all"} if all_subscriptions else {}
        return self._post("/ping", body)

    def wait_ping(self, timeout: float = 300.0, step: float = 1.0) -> bool:
        """Дождаться конца прогона пинга."""
        deadline = time.monotonic() + timeout
        while True:
            if not self.status().get("pinging"):
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(step)

    def select_subscription(self, sub_id: str | None = None, title: str | None = None) -> dict:
        """Переключить активную подписку по id из subscriptions() или по названию."""
        return self._post("/subscriptions/select", {"id": sub_id, "title": title})

    def refresh_subscription(self, sub_id: str | None = None, all_subs: bool = False) -> dict:
        """Запустить обновление активной, указанной или всех сетевых подписок."""
        return self._post("/subscriptions/refresh", {"id": sub_id, "all": all_subs})

    def configure_exits(
        self,
        *,
        enable_all_auto: bool | None = None,
        enable_all: bool | None = None,
        clear: bool | None = None,
        auto_port_enabled: bool | None = None,
        auto_include_auto_profiles: bool | None = None,
        keep_alive_when_disconnected: bool | None = None,
        dns_via_exit: bool | None = None,
        auth_mode: str | None = None,
        assign_port: tuple[str, int] | None = None,
    ) -> dict:
        """Настроить порты выходов и режимы API на лету."""
        body: dict = {}
        if enable_all_auto is not None:
            body["enableAllAuto"] = enable_all_auto
        if enable_all is not None:
            body["enableAll"] = enable_all
        if clear is not None:
            body["clear"] = clear
        if auto_port_enabled is not None:
            body["autoPortEnabled"] = auto_port_enabled
        if auto_include_auto_profiles is not None:
            body["autoIncludeAutoProfiles"] = auto_include_auto_profiles
        if keep_alive_when_disconnected is not None:
            body["keepAliveWhenDisconnected"] = keep_alive_when_disconnected
        if dns_via_exit is not None:
            body["dnsViaExit"] = dns_via_exit
        if auth_mode is not None:
            body["authMode"] = auth_mode
        if assign_port is not None:
            body["assignPort"] = {"server": assign_port[0], "port": assign_port[1]}
        return self._post("/exits/configure", body)

    def test_exit(self, port: int | None = None, server_key: str | None = None) -> dict:
        """Проверить задержку и реальный внешний IP/страну локального порта."""
        return self._post("/exits/test", {"port": port, "server": server_key})

    # ── Хелперы для requests ────────────────────────────────────────────────

    def _format_proxy_url(self, entry: dict, socks: bool = False) -> str:
        scheme = "socks5h" if socks else "http"
        mode = entry.get("authMode", "token")
        if mode == "none" or entry.get("authRequired") is False:
            auth = ""
        elif mode == "custom":
            if not self._proxy_user:
                raise ValueError(
                    "Порт использует режим 'custom' — передайте proxy_user и proxy_password в SilentGate(...)"
                )
            u = urllib.parse.quote(self._proxy_user, safe="")
            p = urllib.parse.quote(self._proxy_password or "", safe="")
            auth = f"{u}:{p}@"
        else:
            p = urllib.parse.quote(self._token, safe="")
            auth = f"sg:{p}@"
        return f"{scheme}://{auth}{self._host}:{entry['port']}"

    def proxies_for(self, server_key: str | None = "auto", socks: bool = False) -> dict:
        """Прокси-словарь для requests.get(..., proxies=...).

        - ``server_key="auto"`` — балансируемый порт «Умный Автовыбор» (10818);
        - ``server_key=None`` — порт «Прямо» мимо VPN (10819);
        - ``server_key="srv-..."`` — выделенный липкий порт конкретного сервера.
        """
        for e in self.exits():
            if e.get("serverKey") == server_key:
                url = self._format_proxy_url(e, socks=socks)
                return {"http": url, "https": url}
        raise KeyError(
            f"нет активного порта для {server_key!r} — проверьте GET /v1/exits "
            "или вызовите configure_exits(enable_all_auto=True)"
        )

    def auto_proxies(self, socks: bool = False) -> dict:
        """Прокси-словарь для фиксированного порта «Умный Автовыбор» (10818)."""
        return self.proxies_for("auto", socks=socks)

    def direct_proxies(self, socks: bool = False) -> dict:
        """Прокси-словарь для фиксированного порта «Прямо» мимо VPN (10819)."""
        return self.proxies_for(None, socks=socks)


if __name__ == "__main__":
    import os

    sg = SilentGate(token=os.environ.get("SILENTGATE_TOKEN", "ВСТАВЬТЕ_ТОКЕН"))
    print(sg.status())
    for exit_ in sg.exits():
        print(f"{exit_['name']} ({exit_.get('kind')}) -> 127.0.0.1:{exit_['port']}")
