// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonCopied => 'Copiado';

  @override
  String get commonRefresh => 'Actualizar';

  @override
  String get commonCheck => 'Comprobar';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonPathCopied => 'Ruta copiada';

  @override
  String get languageTitle => 'Idioma de la interfaz';

  @override
  String get languageSubtitle => 'Elige el idioma de la aplicación';

  @override
  String get languageSystem => 'Predeterminado del sistema';

  @override
  String get sectionAppearance => 'Apariencia y comportamiento';

  @override
  String get sectionCapture => 'Captura de tráfico';

  @override
  String get sectionReliability => 'Fiabilidad de la conexión';

  @override
  String get sectionPing => 'Ping';

  @override
  String get sectionIdentity => 'Identidad del panel';

  @override
  String get sectionNetwork => 'Red';

  @override
  String get sectionAbout => 'Acerca de';

  @override
  String get sectionSupport => 'Soporte';

  @override
  String get appearanceTheme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get closeToTrayTitle => 'Minimizar a la bandeja al cerrar';

  @override
  String get closeToTraySubtitle =>
      'El botón de cerrar oculta la ventana en la bandeja; desactívalo para cerrar la aplicación';

  @override
  String get autoUpdateSubTitle => 'Actualización automática de la suscripción';

  @override
  String get autoUpdateSubText =>
      'Actualizar periódicamente la lista de servidores';

  @override
  String get captureSystemProxy => 'Proxy del sistema';

  @override
  String get captureSystemProxySub =>
      'Funciona ahora. Sin permisos de administrador.';

  @override
  String get captureTun => 'TUN (túnel completo)';

  @override
  String get captureTunBadgeUac => 'requiere UAC';

  @override
  String get captureTunSub =>
      'Todo el tráfico, incluido UDP y las apps que ignoran el proxy. Pedirá permisos de administrador.';

  @override
  String get tunProvider => 'Proveedor TUN';

  @override
  String get tunRoutingTitle => 'TUN y enrutamiento';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'Pila $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'Túnel dividido';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n reglas ($apps apps, $sites sitios)';
  }

  @override
  String get captureTunHint =>
      'Los ajustes de TUN, DNS y túnel dividido aparecen al seleccionar el modo TUN — en modo proxy del sistema no tienen efecto.';

  @override
  String get dnsShortVpn => 'por VPN';

  @override
  String get dnsShortSystem => 'sistema';

  @override
  String get dnsShortCustom => 'propio';

  @override
  String get tunUacTitle => 'TUN requiere permisos de administrador';

  @override
  String get tunUacBody =>
      'Puedes configurarlo una vez: la aplicación creará una tarea en el Programador de tareas de Windows con los máximos permisos, y luego el túnel se iniciará SIN pedir UAC.\n\nAhora aparecerá una solicitud de administrador. La aplicación seguirá funcionando sin permisos elevados.';

  @override
  String get tunUacLater => 'Más tarde (preguntar siempre)';

  @override
  String get tunUacSetup => 'Configurar';

  @override
  String get tunUacDone => 'Listo: TUN se iniciará sin pedir UAC';

  @override
  String get tunUacFail =>
      'No se pudo crear la tarea — se pedirá UAC al conectar';

  @override
  String get autoReconnectTitle => 'Reconexión automática';

  @override
  String get autoReconnectSub =>
      'Restaurar la conexión al caer o cambiar de red';

  @override
  String get killSwitchTitle => 'Kill switch';

  @override
  String get alwaysOnTitle => 'Protección del sistema';

  @override
  String get alwaysOnSub =>
      'VPN siempre activa y «bloquear conexiones sin VPN» — funciona incluso con la app cerrada';

  @override
  String get killSwitchSubTun =>
      'No dejar que el tráfico eluda la VPN mientras se reconecta';

  @override
  String get killSwitchSubProxy =>
      'En modo «Proxy del sistema» solo protege las apps que respetan el proxy. Completamente — solo TUN';

  @override
  String get killSwitchSubOff => 'Requiere la reconexión automática activada';

  @override
  String get networkRecoverTitle => 'Recuperar la red';

  @override
  String get networkRecoverSub =>
      'Si no hay internet tras la VPN. Requiere permisos de administrador';

  @override
  String get networkRecoverConfirmTitle => '¿Recuperar la red?';

  @override
  String get networkRecoverConfirmBody =>
      'Restablecimiento de winsock, pila IP, DNS y proxy del sistema. Se requieren permisos de administrador (UAC). El restablecimiento de winsock/IP surtirá efecto tras reiniciar.';

  @override
  String get networkRecoverConfirmOk => 'Recuperar';

  @override
  String get interferenceTitle => 'Comprobar interferencias (otras VPN)';

  @override
  String get interferenceDialogTitle => 'Interferencias en la red';

  @override
  String get interferenceNoneFound =>
      'No se detectaron otras VPN ni interferencias.';

  @override
  String get interferenceIgnore => 'Ignorar';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'Se actualiza automáticamente con la versión de la app. También se envían: X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'Esquemas URL';

  @override
  String get urlSchemesSub =>
      'Importar y controlar la VPN por enlace (connect / toggle / update)';

  @override
  String get panelOwnerTitle => 'Para el dueño del panel';

  @override
  String get panelOwnerBody =>
      'Los usuarios normales no lo necesitan — puedes omitirlo.\n\nPara que la app reciba tu suscripción en el formato JSON correcto (XRAY_JSON), añade este bloque a las «Reglas de respuesta» (Response Rules) de tu panel Remnawave — coincide con nuestro User-Agent:';

  @override
  String get panelOwnerCopy => 'Copiar bloque';

  @override
  String get aboutVersion => 'Versión de SilentGate';

  @override
  String get aboutXrayCore => 'Núcleo Xray';

  @override
  String get aboutHwid => 'HWID del dispositivo';

  @override
  String get aboutThirdPartyTitle => 'Componentes de terceros y licencias';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — se ejecutan como procesos separados';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — integrados en la app';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'Registros';

  @override
  String get logsSub =>
      'App y TUN (sing-box): importación de suscripción, ping, errores';

  @override
  String get thirdPartyTitle => 'Componentes de terceros';

  @override
  String get thirdPartyBody =>
      'SilentGate se distribuye junto con ejecutables de terceros. Se ejecutan como procesos SEPARADOS y no están integrados en la aplicación.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  Túnel TUN y núcleo proxy para Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — licencia Wintun\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — datos de enrutamiento, CC-BY-SA-4.0\n\nLos textos completos de las licencias están en la carpeta «licenses» junto a la aplicación.';

  @override
  String get supportSectionNote =>
      'Pulsa «Contactar con soporte» — se abrirá una ventana donde tú mismo generas un archivo de registro (versiones, SO, ajustes, app.log + final de singbox.log; sin contraseñas ni token de suscripción, la URL oculta). Después aparecerá un botón para enviarlo al soporte de Telegram.';

  @override
  String get supportButtonTitle => 'Contactar con soporte';

  @override
  String get supportButtonSub =>
      'Generar un registro y abrir el chat de soporte';

  @override
  String get supportDialogTitle => 'Soporte';

  @override
  String get supportDialogTitleDone =>
      'El registro está listo — a dónde enviarlo';

  @override
  String get supportWhatWillHappen => 'Qué se hará:';

  @override
  String get supportBullet1 =>
      '• En un archivo se recopilarán versiones, SO, ajustes y registros (app.log + final de singbox.log). No contiene contraseñas ni el token de suscripción, la URL de la suscripción está oculta.';

  @override
  String get supportBullet2 =>
      '• Tras pulsar, se abrirá PRIMERO la carpeta con el archivo, luego el archivo. Describe el problema arriba, guárdalo — y aparecerá un botón para enviarlo al soporte.';

  @override
  String supportError(String error) {
    return 'No se pudo generar el informe: $error';
  }

  @override
  String get supportDoneText =>
      'El informe está generado y abierto (carpeta, luego archivo). Describe el problema arriba, guarda el archivo y envíalo al soporte — la app ayudará a abrir Telegram.';

  @override
  String get supportWhoTo => 'A dónde enviar:';

  @override
  String get supportContact => 'Contactar con soporte';

  @override
  String supportContactNamed(String name) {
    return 'Contactar con soporte ($name)';
  }

  @override
  String get supportDevServiceName => 'Desarrollador del cliente';

  @override
  String get supportShowOnPc => 'Mostrar en el PC';

  @override
  String get supportCopyPath => 'Copiar ruta';

  @override
  String get supportGenerating => 'Generando…';

  @override
  String get supportGenerateButton => 'Generar un registro para soporte';

  @override
  String get pingTwoPhaseTitle => 'Verificar que funciona (a través del túnel)';

  @override
  String get pingTwoPhaseSubOn =>
      'Tras TCP — una petición a través del servidor: descarta los que no funcionan (Reality, etc.)';

  @override
  String get pingTwoPhaseSubOff =>
      'Solo se usa el único método seleccionado (abajo)';

  @override
  String get pingMethodCheck => 'Método de verificación:';

  @override
  String get pingMethodPing => 'Método de ping:';

  @override
  String get speedTestProbe => 'Prueba de velocidad:';

  @override
  String get speedTestFull => '20 MB (más preciso)';

  @override
  String get speedTestLight => '5 MB (económico)';

  @override
  String get testUrlLabel => 'URL de prueba (via Proxy)';

  @override
  String get appUpdateServerUnavailable =>
      'Servidor de actualizaciones no disponible';

  @override
  String appUpdateAvailable(String version) {
    return 'Versión $version disponible';
  }

  @override
  String get appUpdateLatest => 'Tienes la última versión';

  @override
  String get appUpdateDownload => 'Descargar';

  @override
  String get appUpdateCheckTitle => 'Buscar actualizaciones al iniciar';

  @override
  String get appUpdateManual => 'Descarga e instalación — manual';

  @override
  String get appUpdateEndpointLabel => 'Endpoint de versión';

  @override
  String get urlSchemeSilentgateTitle => 'Enlaces silentgate://';

  @override
  String get urlSchemeSilentgateSub =>
      'Importar y controlar la VPN por enlace. Activado por defecto';

  @override
  String get urlSchemeDisableTitle => '¿Desactivar los enlaces silentgate://?';

  @override
  String get urlSchemeDisableBody =>
      'Dejarán de funcionar la importación por enlace y los esquemas de control (connect / disconnect / toggle / update). Déjalo activado si no estás seguro.';

  @override
  String get urlSchemeDisableOk => 'Desactivar';

  @override
  String get urlSchemeServerTitle => 'Abrir enlaces de servidores';

  @override
  String get urlSchemeServerSub =>
      'Interceptar vless:// y otros de otros clientes';

  @override
  String get urlSchemeServerConfirmTitle =>
      '¿Interceptar enlaces de servidores?';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nEstos enlaces suelen estar asociados a otro cliente VPN (Happ, v2rayTun). SilentGate los tomará para sí.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'Interceptar';

  @override
  String get urlSchemeAutoConnect => 'Conectar tras importar';

  @override
  String get autoTitle => 'Configuración automática';

  @override
  String get autoClearResults => 'Borrar resultados';

  @override
  String autoFoundWorking(Object count) {
    return 'Funcionales encontrados: $count';
  }

  @override
  String get autoPinnedTop => ' — fijados al principio de la lista';

  @override
  String get autoSearchContinues => ' (la búsqueda continúa…)';

  @override
  String get autoCheckServices => 'Comprobar servicios';

  @override
  String get autoPinFoundOnTop =>
      'Fijar los encontrados al principio de la lista';

  @override
  String get autoTryFragment => 'Probar evasión (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'No hay suscripción. Pega una clave: encontraremos la configuración que funcione:';

  @override
  String get autoTuneByKey => 'Configurar por clave';

  @override
  String autoTesting(int index, int total) {
    return 'Probando $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'Variante: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$ok de $total servicios';
  }

  @override
  String get autoConnect => 'Conectar';

  @override
  String get autoStopSearch => 'Detener búsqueda';

  @override
  String get autoDoneRefreshPing =>
      'Listo — actualizar el ping de los encontrados';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return 'Encontrados $count, fijados arriba. Actualizando el ping…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'Servidores para configurar ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'Todos';

  @override
  String get autoDeselectAll => 'Quitar';

  @override
  String get autoTuneSelected => 'Configurar seleccionados';

  @override
  String autoTuned(Object label) {
    return 'Configurado: $label';
  }

  @override
  String get infoDialogTitle => 'Explicación';

  @override
  String get infoCopied => 'Explicación copiada';

  @override
  String get commonGotIt => 'Entendido';

  @override
  String get enumSplitAll => 'Todo — por VPN';

  @override
  String get enumSplitOnly => 'Solo los marcados — por VPN';

  @override
  String get enumSplitExcept => 'Los marcados — fuera de la VPN';

  @override
  String get enumActionTunnel => 'Túnel';

  @override
  String get enumActionDirect => 'Directo';

  @override
  String get enumActionBlock => 'Bloquear';

  @override
  String homeUpdateAvailable(Object version) {
    return 'Versión $version disponible';
  }

  @override
  String get homeDownload => 'Descargar';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'Suscripción actualizada: $summary';
  }

  @override
  String get homeReconnect => 'Reconectar';

  @override
  String homePingProgress(int done, int total) {
    return 'Haciendo ping a servidores: $done de $total';
  }

  @override
  String get homeAutoConfigStarting => 'Iniciando la configuración automática…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'Configuración automática: $current de $total — $name';
  }

  @override
  String get homeImport => 'Importar';

  @override
  String get homeSettings => 'Configuración';

  @override
  String get homeAutoBest => 'Auto (mejor servidor)';

  @override
  String get homeAutoConfig => 'Configuración automática';

  @override
  String homeServersCount(Object count) {
    return 'Servidores ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return 'Encontrados $found de $total';
  }

  @override
  String get homePingServers => 'Hacer ping a servidores';

  @override
  String get homePingFound => 'Ping a encontrados';

  @override
  String get homeNothingFound => 'No se encontró nada';

  @override
  String get homeOnboardingTitle => 'Comience importando una suscripción';

  @override
  String get homeOnboardingSubtitle =>
      'Pegue un enlace de Remnawave o una clave individual';

  @override
  String get homeImportSubscription => 'Importar suscripción';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'Esta sesión: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(String used, String total) {
    return '$used de $total';
  }

  @override
  String get subBarSubscription => 'Suscripción';

  @override
  String get subBarRefreshing => 'Actualizando…';

  @override
  String get subBarRefreshSubscription => 'Actualizar suscripción';

  @override
  String get subBarSupport => 'Soporte';

  @override
  String get subBarRefresh => 'Actualizar';

  @override
  String get subBarAddSubscription => 'Agregar suscripción';

  @override
  String get subBarCopyLink => 'Copiar enlace';

  @override
  String get subBarDeleteSubscription => 'Eliminar suscripción';

  @override
  String get subBarLinkCopied => 'Enlace copiado';

  @override
  String get subBarDeleteConfirmTitle => '¿Eliminar suscripción?';

  @override
  String get subBarDeleteConfirmBody =>
      'Los servidores de esta suscripción se eliminarán de la lista.';

  @override
  String subBarDeletePinned(Object count) {
    return 'Eliminar también los fijados ($count) con sus ediciones';
  }

  @override
  String get subBarDeletePinnedHint =>
      'De lo contrario, permanecerán en la lista y sobrevivirán a la eliminación';

  @override
  String get subBarCancel => 'Cancelar';

  @override
  String get subBarDelete => 'Eliminar';

  @override
  String get subBarSubscriptionDeleted => 'Suscripción eliminada';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'Suscripción actualizada: $summary';
  }

  @override
  String get subBarMore => 'Detalles';

  @override
  String subBarAdded(Object count) {
    return 'Agregados ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'Eliminados ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· actualización automática ${hours}h';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'Válida: sin límite  $auto';
  }

  @override
  String get subBarExpired => 'Suscripción vencida:';

  @override
  String get subBarValidUntil => 'Válida hasta:';

  @override
  String get infoCaptureMode =>
      'Cómo se intercepta el tráfico. «Proxy del sistema»: configura un proxy local en el sistema (sin permisos de administrador; captura navegadores y la mayoría de las aplicaciones). «TUN»: adaptador de red virtual que captura TODO el tráfico (incluidos UDP y las aplicaciones que ignoran el proxy), pero requiere permisos de administrador.';

  @override
  String get infoSystemProxy =>
      'Un proxy HTTP local en la configuración del sistema (registro WinINET). Sin permisos de administrador. No intercepta UDP ni las aplicaciones que ignoran el proxy del sistema.';

  @override
  String get infoTunMode =>
      'Un túnel completo a través del adaptador virtual wintun + sing-box. Captura todo el tráfico, incluido UDP. Solicita permisos de administrador (UAC) al activarse.';

  @override
  String get infoTunProvider =>
      'El controlador del adaptador de red virtual. En Windows se usa wintun (incluido con el núcleo). No se requieren otros controladores.';

  @override
  String get infoTunStack =>
      'La pila de red TUN (sing-box).\n\n«auto»: SELECCIÓN AUTOMÁTICA: si el túnel no se levanta, la propia aplicación recorre system → gvisor → mixed y luego reduce el MTU (1400, 1280). La combinación con la que todo funcionó se recuerda y se prueba primero la próxima vez. El progreso de la selección se ve en el estado y en el registro.\n\nUna elección explícita desactiva la selección automática: system — pila del SO, la más rápida, pero más susceptible a los antivirus; gvisor — espacio de usuario, más lenta, máxima compatibilidad; mixed — TCP por system, UDP por gvisor.';

  @override
  String get infoTunMtu =>
      'El tamaño máximo de paquete en el adaptador TUN. El valor predeterminado es 1500; redúcelo (1400, 1280) si hay cortes — un valor demasiado bajo reduce la velocidad.\n\nCon la pila «auto» este es solo el valor inicial: si el túnel no se levanta, la propia aplicación probará MTU menores.';

  @override
  String get infoTunStrictRoute =>
      'Enrutamiento estricto de sing-box. En Windows soluciona dos problemas típicos: fugas de DNS (por defecto el sistema envía las consultas a todos los adaptadores a la vez) y errores de «red no disponible». Desactívalo solo si rompe VirtualBox/Hyper-V.';

  @override
  String get infoTunIpv6 =>
      'Enrutar IPv6 dentro del túnel. Si lo desactivas mientras tu proveedor tiene IPv6 activado, parte del tráfico irá FUERA de la VPN (filtrando tu dirección real) o se quedará colgado. Desactívalo solo si tienes problemas con la red IPv6.';

  @override
  String get infoTunEndpointIndependentNat =>
      'Modo NAT para UDP. Necesario para juegos, chats de voz y WebRTC — sin él, las conexiones pueden no establecerse. Desactívalo solo para ahorrar memoria.';

  @override
  String get infoTunBypassLan =>
      'La red local (direcciones privadas 192.168.*, 10.*, router, impresoras, NAS) pasa fuera de la VPN. Normalmente conviene tenerlo activado; de lo contrario perderás el acceso a los dispositivos de la red.';

  @override
  String get infoTunExcludeCidrs =>
      'Subredes adicionales que siempre pasan fuera de la VPN (formato CIDR, p. ej. 10.8.0.0/24). Útil para redes corporativas y otras VPN.';

  @override
  String get infoTunPrivilege =>
      'TUN requiere permisos de administrador. Una sola vez creamos una tarea en el Programador de tareas de Windows con los máximos privilegios — después de eso el túnel arranca SIN pedir UAC en cada conexión. La tarea te pertenece y se elimina con el botón de abajo o al desinstalar el programa.';

  @override
  String get infoAppUpdate =>
      'Una vez por inicio, la aplicación pregunta a tu servidor si hay una versión más reciente y muestra una notificación con el botón «Descargar».\n\nLa aplicación NO descarga ni ejecuta nada por sí sola: el instalador no está firmado con un certificado, y ejecutar automáticamente un exe descargado choca con SmartScreen y para los antivirus parece comportamiento de malware. La actualización la instalas tú.\n\nSi el servidor no está disponible, la aplicación simplemente calla y deja una entrada en el registro. El formato de la respuesta y la configuración del servidor se describen en docs/APP_UPDATE.md.';

  @override
  String get infoSpeedTest =>
      'La cantidad de datos que se descargan al medir la velocidad (clic derecho en un servidor → «Información del servidor» → «Medir velocidad»).\n\n20 MB — el modo principal: en enlaces rápidos (100+ Mbps) una prueba corta no llega a acelerarse y subestima el resultado.\n5 MB — el modo económico: bastante más barato en tráfico, cómodo para recorrer muchos servidores.\n\nLa medición se ejecuta SOLO manualmente y consume el tráfico de tu suscripción. La velocidad se mide dos veces: directamente y a través del servidor elegido, para que se vea exactamente cuánto se pierde con la VPN.';

  @override
  String get infoAutoReconnect =>
      'Si el núcleo se cayó, el servidor se desconectó o cambió la red (Wi-Fi ↔ cable, salida de suspensión, nueva IP), la aplicación restablece la conexión por sí sola. Las pausas entre intentos aumentan: 0,8 s → 3 s → 8 s → 20 s, hasta 8 intentos, tras lo cual se muestra un error. Desconectar con el botón siempre cancela la recuperación.\n\nEl cambio de red se detecta por las direcciones reales de otros adaptadores: el propio túnel y las direcciones de servicio (link-local) no se tienen en cuenta, un cambio se acepta solo si se mantuvo durante dos sondeos seguidos, y la señal se ignora durante los primeros 15 segundos tras conectar. Sin estas protecciones, levantar el túnel se consideraría a sí mismo un «cambio de red» y provocaría reconexiones infinitas.';

  @override
  String get infoKillSwitch =>
      'No dejar salir el tráfico fuera de la VPN mientras se restablece la conexión. La captura NO se libera entre intentos: en modo TUN el adaptador permanece levantado, en modo «Proxy del sistema» el proxy permanece configurado — las aplicaciones reciben un error de conexión en lugar de una salida a internet sin cifrar.\n\nCon honestidad sobre los límites: en modo «Proxy del sistema» esto protege solo a los programas que respetan el proxy del sistema (navegadores y la mayoría de las aplicaciones). Los programas que ignoran el proxy, y UDP, irán directamente — la hermeticidad total la da solo el modo TUN. Requiere la reconexión automática activada.';

  @override
  String get infoUserAgent =>
      'Cómo se identifica la aplicación ante el panel (encabezado User-Agent). Siempre envía «SilentGate/versión (Windows)».\n\nPor este nombre el panel Remnawave elige el FORMATO de la suscripción. Se necesita XRAY_JSON — en él llegan configuraciones de servidor ya listas; desde una lista de enlaces en base64 parte de los ajustes se restaura de forma aproximada, y la selección automática (burstObservatory) funciona peor.\n\nSe configura en el panel: Templates → Response Rules → una regla con la condición user-agent CONTAINS SilentGate y tipo de respuesta XRAY_JSON (colócala por encima de la regla Fallback Base64).\n\nEl campo de sustitución solo se necesita como solución temporal — si el panel aún no conoce la aplicación, puedes identificarte como un cliente que sí conoce.';

  @override
  String get infoDnsMode =>
      'Quién resuelve los dominios en modo TUN. «A través de la VPN» (recomendado) — las consultas van al túnel por TCP y tu proveedor no ve qué sitios abres. «Del sistema» — como en Windows: es posible una fuga de DNS, y si el servidor no deja pasar UDP, internet puede caerse por completo. «Propio» — el servidor que indiques, a través del túnel.';

  @override
  String get infoDnsCustomServer =>
      'La dirección del servidor DNS para el modo «Propio» (por ejemplo 9.9.9.9 o 8.8.8.8). Las consultas a él van a través del túnel por TCP.';

  @override
  String get infoDnsHijack =>
      'Interceptar las consultas DNS (puerto UDP 53) dentro del túnel. Sin esto, las consultas se escapan de las reglas: es posible una fuga y las reglas por dominio del túnel dividido funcionan con menor precisión.';

  @override
  String get infoDnsStrategy =>
      'Qué direcciones solicitar: prefer_ipv4 (recomendado) — primero IPv4, ipv4_only — solo IPv4 (soluciona problemas con IPv6 defectuoso), prefer_ipv6/ipv6_only — para redes IPv6.';

  @override
  String get infoSingboxLogLevel =>
      'El nivel de detalle del registro de sing-box (%APPDATA%\\SilentGate\\singbox.log). warn — modo normal. info/debug — si el túnel no funciona: el registro mostrará la causa exacta. debug aumenta notablemente el tamaño del archivo.';

  @override
  String get infoSplitMode =>
      'La base — adónde va todo lo que no tiene una acción asignada manualmente y qué acción se asigna a las nuevas entradas. «Todo — por la VPN»: por defecto todo el tráfico al túnel. «Solo los marcados — por la VPN»: por defecto directo, al túnel solo los marcados como «Túnel». «Los marcados — fuera de la VPN»: al contrario, todo al túnel, y los marcados como «Directo» van directamente.';

  @override
  String get infoSplitApps =>
      'Haz clic en una aplicación — se abre una ventana donde eliges la acción (Túnel — por la VPN, Directo — fuera de la VPN, Bloquear — sin red) y el método de coincidencia: por nombre del exe (fiable) o por ruta completa. Puedes elegir entre las aplicaciones en ejecución o indicar un .exe.';

  @override
  String get infoSplitDomains =>
      'Dominios (sufijos). Por ejemplo, youtube.com también cubre www.youtube.com. Funciona por el nombre de la conexión TLS (SNI).';

  @override
  String get infoVerifyViaProxy =>
      'Primero comprobamos el funcionamiento a través del proxy (el servidor devuelve realmente 204), y solo si el servidor respondió medimos por separado la latencia con el método elegido (TCP/ICMP).';

  @override
  String get infoProxyGet =>
      'Una petición GET a través del túnel a la URL de prueba. Comprueba que el servidor realmente deja pasar el tráfico y devuelve 204. La prueba de funcionamiento más honesta; algo más lenta.';

  @override
  String get infoProxyHead =>
      'Como GET, pero solo los encabezados — más rápido y menos tráfico. Algunos servidores/CDN pueden no admitir HEAD.';

  @override
  String get infoTcp =>
      'El tiempo del apretón de manos TCP hasta la dirección del servidor. Un indicador de latencia rápido y preciso, pero no demuestra que el túnel funcione: un servidor Reality responderá al TCP aunque el proxy esté bloqueado. Recomendado para la latencia.';

  @override
  String get infoIcmp =>
      'Ping del sistema. A menudo inútil para Reality/CDN: el ICMP puede estar bloqueado, o mide el nodo de CDN más cercano. Déjalo para el diagnóstico de red.';

  @override
  String get infoTestUrl =>
      'La URL para comprobar el funcionamiento a través del proxy. Por defecto https://www.gstatic.com/generate_204 — devuelve una respuesta 204 vacía, lo cual es cómodo y rápido.';

  @override
  String get infoAutoConfig =>
      'Recorre los servidores y las variantes de evasión (fragment, fingerprint) y arma una lista de aquellos donde funcionan los servicios elegidos. No se detiene en el primero — eliges entre los encontrados. La comprobación se hace a través del proxy; la VPN no se activa durante ese tiempo.';

  @override
  String get infoAutoConfigServices =>
      'Qué servicios deben funcionar para que un servidor se considere apto. La comprobación es resistente a las páginas de sustitución del proveedor (se verifica la firma de la respuesta, no solo un «200 OK»).';

  @override
  String get infoAutoPinFound =>
      'Las combinaciones funcionales encontradas (servidor + variante de evasión) se fijan de inmediato en la parte superior de la lista común de servidores, para que puedas usarlas sin volver aquí. Desactívalo si no quieres que la configuración automática cambie el orden de tu lista — los resultados seguirán siendo visibles en esta pantalla.';

  @override
  String get infoTryFragment =>
      'Probar la variante con fragmentación del TLS ClientHello (evasión de DPI) si el servidor «desnudo» no funciona. Algo más lento, pero encuentra una combinación funcional en servidores restringidos.';

  @override
  String get infoAutoStrategy =>
      '«El primero que funcione» — recorrer todo y conectarse a cualquiera que se encuentre (tú eliges). «El mejor dentro del presupuesto» — buscar dentro de un límite de tiempo y elegir el más rápido.';

  @override
  String get infoScheme =>
      'Registra el protocolo silentgate:// en el sistema (para el usuario actual, sin permisos de administrador). Después de eso, hacer clic en un enlace silentgate://import?url=… (importar) o silentgate://connect / toggle (control) en el navegador abre la aplicación y ejecuta la acción. Activado por defecto.';

  @override
  String get infoAutoConnectAfterImport =>
      'Conectar al primer servidor inmediatamente después de importar correctamente una suscripción por enlace.';

  @override
  String get infoNetworkRecover =>
      'Restablece los parámetros de red si internet desaparece tras un fallo/apagado del PC con la VPN activada: winsock, la pila IP, la caché de DNS, el proxy del sistema. Requiere permisos de administrador; el restablecimiento de winsock y de la pila IP surte efecto tras REINICIAR.';

  @override
  String get infoInterference =>
      'Una comprobación de otras VPN e interferencias en la red (adaptadores TUN ajenos, procesos de VPN, zapret/GoodbyeDPI) que pueden entrar en conflicto con SilentGate. Puedes cerrarlos o ignorarlos.';

  @override
  String get pingInfoProxyGet =>
      'Una petición GET a través del túnel a la URL de prueba. Comprueba que el servidor realmente deja pasar el tráfico y devuelve 204. La prueba de funcionamiento más honesta; algo más lenta por la descarga completa de la respuesta. Recomendada para comprobar el funcionamiento.';

  @override
  String get pingInfoProxyHead =>
      'Como GET, pero solicita solo los encabezados — menos tráfico y más rápido. Comprueba el funcionamiento del túnel; algunos servidores/CDN pueden no admitir HEAD.';

  @override
  String get pingInfoTcp =>
      'Mide el tiempo del apretón de manos TCP hasta la dirección del servidor. Un indicador rápido y preciso de la latencia del endpoint, pero no demuestra que el túnel funcione: un servidor Reality responderá al TCP aunque el proxy esté bloqueado. Recomendado para la latencia.';

  @override
  String get pingInfoIcmp =>
      'Ping del sistema (solicitud de eco). A menudo inútil para Reality/CDN: el ICMP puede estar bloqueado, o mide el nodo de CDN más cercano en lugar del servidor. Déjalo para el diagnóstico de red.';

  @override
  String get pingInfoTwoPhase =>
      'Tras la comprobación TCP, los servidores que respondieron se comprueban adicionalmente con una petición a través del túnel (GET/HEAD a la URL de prueba). Así se descartan los servidores que mantienen el puerto abierto pero no hacen de proxy del tráfico. La latencia se sigue mostrando por TCP.';

  @override
  String get pingInfoTunStage =>
      'El túnel completo (TUN) es la siguiente etapa. Por ahora funciona el modo «Proxy del sistema». En modo TUN todo el tráfico (incluidos UDP y las aplicaciones que ignoran el proxy) pasará por el adaptador virtual wintun + tun2socks. Requiere permisos de administrador.';

  @override
  String get pingInfoTunStack =>
      'La pila de red TUN (sing-box). auto — dejarlo a criterio del núcleo (actualmente mixed). system — pila del SO: máxima velocidad, pero más susceptible a permisos/antivirus. gvisor — pila en espacio de usuario: más lenta, pero la más compatible. mixed — TCP por system, UDP por gvisor (equilibrio). Si TUN no se conecta o corta las conexiones — prueba gvisor.';

  @override
  String get pingInfoAutoConfig =>
      'Al activarse, la aplicación misma recorre los servidores y las variantes de evasión (fragment, fingerprint) y se conecta al primero donde funcionan los servicios elegidos (comprobación a través del proxy, sin activar la VPN durante el recorrido).';

  @override
  String get logsTabApp => 'Aplicación';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'Actualizar';

  @override
  String get logsCopy => 'Copiar';

  @override
  String get logsClearApp => 'Borrar registro de la app';

  @override
  String get logsCopied => 'Registro copiado';

  @override
  String get logsLoading => 'Cargando…';

  @override
  String get logsEmpty => 'Vacío por ahora.';

  @override
  String get logsTunEmpty =>
      'Vacío: TUN aún no se ha iniciado en este sistema.';

  @override
  String get importScrDone => 'Importado';

  @override
  String get importScrWelcome => 'Bienvenido a SilentGate';

  @override
  String get importScrTitle => 'Importar suscripción';

  @override
  String get importScrSubscriptionFallback => 'Suscripción';

  @override
  String get importScrHint =>
      'Pega un enlace de suscripción (Remnawave), un deep link silentgate:// o un único enlace vless:// / vmess:// / trojan:// / ss:// / hysteria2://';

  @override
  String get importScrLoading => 'Cargando…';

  @override
  String get importScrPasteImport => 'Importar desde el portapapeles';

  @override
  String get importScrImportField => 'Importar del campo';

  @override
  String get serversTitle => 'Servidores';

  @override
  String serversFound(int found, int total) {
    return 'Servidores: $found de $total encontrados';
  }

  @override
  String get serversRefresh => 'Actualizar suscripción';

  @override
  String get serversPinging => 'Haciendo ping…';

  @override
  String get serversPingAll => 'Hacer ping a todos';

  @override
  String get serversPingFound => 'Hacer ping a los encontrados';

  @override
  String get serversEmpty =>
      'La lista de servidores está vacía. Importa una suscripción.';

  @override
  String get serversNothingFound => 'No se encontró nada';

  @override
  String get toastCopied => 'Copiado';

  @override
  String get toastHide => 'Ocultar';

  @override
  String get srvInfoTitle => 'Información del servidor';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'No se pudo iniciar la conexión de prueba: $error';
  }

  @override
  String get srvInfoServerAddressFailed =>
      'No se pudo determinar la dirección del servidor';

  @override
  String get srvInfoSectionExit => 'Por dónde sales';

  @override
  String get srvInfoExitHint =>
      'Se determina por la dirección del servidor: no se establece ningún túnel para ello.';

  @override
  String get srvInfoAddressLocation => 'Dirección y ubicación del servidor';

  @override
  String get srvInfoCheckAgain => 'Comprobar de nuevo';

  @override
  String get srvInfoSectionSpeed => 'Velocidad';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'La prueba descarga $size y consume tráfico de tu suscripción. El tamaño se cambia en los ajustes.';
  }

  @override
  String get srvInfoViaServer => 'A través del servidor';

  @override
  String get srvInfoWithoutVpn => 'Sin VPN';

  @override
  String get srvInfoMeasuring => 'Midiendo…';

  @override
  String get srvInfoMeasureSpeed => 'Medir velocidad';

  @override
  String get srvInfoSectionParams => 'Parámetros de conexión';

  @override
  String get srvInfoParamAddress => 'Dirección';

  @override
  String get srvInfoParamProtocol => 'Protocolo';

  @override
  String get srvInfoParamTransport => 'Transporte';

  @override
  String get srvInfoParamTlsFingerprint => 'Huella TLS';

  @override
  String get srvInfoParamType => 'Tipo';

  @override
  String get srvInfoPanelAutoProfile =>
      'Perfil de selección automática del panel';

  @override
  String get srvInfoCouldNotDetermine => 'no se pudo determinar';

  @override
  String get srvInfoCopy => 'Copiar';

  @override
  String get editorJsonTitle => 'Configuración JSON';

  @override
  String get editorCopy => 'Copiar';

  @override
  String get editorClose => 'Cerrar';

  @override
  String get editorTitle => 'Editar servidor';

  @override
  String get editorFieldName => 'Nombre';

  @override
  String get editorFieldAddress => 'Dirección';

  @override
  String get editorFieldPort => 'Puerto';

  @override
  String get editorFieldUuidPassword => 'UUID / contraseña';

  @override
  String get editorFieldObfs => 'Ofuscación (normalmente salamander)';

  @override
  String get editorFieldObfsPassword => 'Contraseña de ofuscación';

  @override
  String get editorFieldPortHopping => 'Salto de puertos (p. ej. 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'Permitir certificado autofirmado';

  @override
  String get editorAllowSelfSignedSub =>
      'Necesario solo si el servidor está configurado así';

  @override
  String get editorTransport => 'Transporte';

  @override
  String get editorSecurity => 'Seguridad';

  @override
  String get editorNone => '(ninguno)';

  @override
  String get editorCancel => 'Cancelar';

  @override
  String get editorSave => 'Guardar';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count servidores$burst';
  }

  @override
  String get jsonCompositionUnknown => 'composición desconocida';

  @override
  String get jsonYourSavedOverride => 'Tu JSON guardado (override)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'Perfil de selección automática del panel: $summary — se aplica por completo';
  }

  @override
  String get jsonPanelConfig => 'Configuración del panel (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'Creado a partir del enlace compartido: el panel no envió JSON. Actualiza la suscripción; si no ayuda, revisa la regla Response Rules en el panel.';

  @override
  String get jsonInvalidJson => 'JSON no válido';

  @override
  String get jsonSaved => 'Guardado';

  @override
  String get jsonTitle => 'Configuración JSON';

  @override
  String get jsonFieldEditor => 'Editor de campos';

  @override
  String get jsonCopy => 'Copiar';

  @override
  String get jsonClose => 'Cerrar';

  @override
  String get jsonSave => 'Guardar';

  @override
  String get srvTileEdit => 'Editar';

  @override
  String get srvTileNotice => 'Aviso';

  @override
  String get srvTileRefresh => 'Actualizar';

  @override
  String get srvTileSubscriptionUpdated => 'Suscripción actualizada';

  @override
  String get srvTileCopy => 'Copiar';

  @override
  String get srvTileInfo => 'Información del servidor';

  @override
  String get srvTilePing => 'Hacer ping';

  @override
  String get srvTileUnpin => 'Desanclar';

  @override
  String get srvTilePin => 'Anclar';

  @override
  String get srvTileJsonConfig => 'Configuración JSON';

  @override
  String get srvTileSmart => 'Ajuste inteligente de parámetros';

  @override
  String get srvTileDelete => 'Eliminar';

  @override
  String get srvTileServerDeleted => 'Servidor eliminado';

  @override
  String get srvTileSaved => 'Guardado';

  @override
  String get pingNa => 'n/d';

  @override
  String get pingNaTooltip =>
      'Sin respuesta TCP: servidor no disponible (muerto)';

  @override
  String get pingTimeout => 'tiempo agotado';

  @override
  String get pingTimeoutTooltip =>
      'La prueba TCP no se completó dentro del tiempo límite: servidor no disponible';

  @override
  String pingMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get pingNoProxy => 'sin proxy';

  @override
  String get pingNoProxyTooltip =>
      'Responde por TCP (se muestra la latencia), pero la comprobación por el túnel (GET/HEAD) falló: el tráfico no pasa';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip =>
      'Latencia TCP al servidor. El servidor funciona: respondió por TCP y superó la comprobación por el túnel (GET/HEAD)';

  @override
  String get searchHint => 'Buscar por nombre, país, dirección…';

  @override
  String get searchReset => 'Borrar';

  @override
  String get splitTitle => 'Túnel dividido';

  @override
  String get splitTunOnlyBanner =>
      'Solo funciona en modo TUN. En el modo «Proxy del sistema», las aplicaciones deciden por sí mismas si usan el proxy; no se les puede forzar.';

  @override
  String get splitEnableTun => 'Activar TUN';

  @override
  String get splitModeHeader => 'Modo';

  @override
  String get splitAppsHeader => 'Aplicaciones';

  @override
  String get splitAppsHint =>
      'Toca una aplicación para elegir la acción (Túnel / Directo / Bloquear) y el método de coincidencia. La casilla de la izquierda activa/desactiva la regla.';

  @override
  String get splitByName => 'Por nombre';

  @override
  String get splitByPath => 'Por ruta';

  @override
  String get splitRuleDisabled => 'Desactivada — la regla no se aplica';

  @override
  String get splitRemove => 'Quitar';

  @override
  String get splitFromRunning => 'De las abiertas';

  @override
  String get splitPickInstalled => 'Elegir aplicación';

  @override
  String get splitInstalledApps => 'Aplicaciones instaladas';

  @override
  String get splitPickExe => 'Elegir .exe';

  @override
  String get splitSitesHeader => 'Sitios (dominios)';

  @override
  String get splitSitesHint =>
      'Toca un sitio para elegir una acción (Túnel / Directo / Bloquear). Un dominio también cubre sus subdominios; los subdominios se agrupan en árbol. Puedes indicar un puerto.';

  @override
  String splitOnlyPort(Object port) {
    return 'solo puerto $port';
  }

  @override
  String get splitProgramsFileType => 'Programas';

  @override
  String get splitRunningApps => 'Aplicaciones en ejecución';

  @override
  String get splitSearchByName => 'Buscar por nombre';

  @override
  String get splitNothingFound => 'No se encontró nada';

  @override
  String get splitClose => 'Cerrar';

  @override
  String get splitPortRange => 'Puerto 1–65535';

  @override
  String get splitAction => 'Acción';

  @override
  String get splitPortOptional => 'Puerto (opcional)';

  @override
  String get splitAnyPort => 'cualquiera';

  @override
  String get splitPortHelper =>
      'Vacío = cualquier puerto. Si no, la regla se aplica solo a este puerto';

  @override
  String get splitMatching => 'Coincidencia';

  @override
  String get splitByNameSubtitle =>
      'Nombre del exe, sin importar su ubicación (fiable)';

  @override
  String get splitByPathSubtitle =>
      'Ruta completa al exe (coincidencia exacta)';

  @override
  String get splitDone => 'Listo';

  @override
  String get splitEnterDomain => 'Introduce un dominio';

  @override
  String get splitAddSite => 'Añadir sitio';

  @override
  String get splitPort => 'Puerto';

  @override
  String get splitAdd => 'Añadir';

  @override
  String get routeBlock => 'Bloquear';

  @override
  String get routeBlocked => 'Bloqueado';

  @override
  String get routeYourPc => 'Tu PC';

  @override
  String get routeTunnel => 'Túnel';

  @override
  String get routeViaVpn => 'Por VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'Internet';

  @override
  String get routeRest => 'Lo demás';

  @override
  String get routeDirectly => 'Directamente';

  @override
  String get routeDirectPlusRest => 'Directo + lo demás';

  @override
  String get routeDirect => 'Directo';

  @override
  String get routeEmptyList => 'lista vacía';

  @override
  String get trayShow => 'Mostrar';

  @override
  String get trayToggle => 'Conectar / Desconectar';

  @override
  String get trayQuit => 'Salir';

  @override
  String get trayMinimizeTitle => 'Minimizar a la bandeja';

  @override
  String get trayMinimizeBody =>
      'La aplicación seguirá funcionando en la bandeja.';

  @override
  String get trayDontAsk => 'No preguntar de nuevo';

  @override
  String get trayMinimizeOk => 'Minimizar';

  @override
  String get trayVpnTitle => 'VPN conectada';

  @override
  String get trayVpnBody => '¿Desconectar la VPN y salir de la aplicación?';

  @override
  String get trayStay => 'Quedarse';

  @override
  String get trayQuitVpn => 'Desconectar y salir';

  @override
  String get tunTaskDone => 'Listo: TUN se iniciará sin solicitud de UAC';

  @override
  String get tunTaskFailed =>
      'No se pudo crear la tarea (UAC rechazado o bloqueado por directiva)';

  @override
  String get tunLogTitle => 'Registro TUN (sing-box)';

  @override
  String get tunLogEmpty =>
      'El registro está vacío: el túnel aún no se ha iniciado.';

  @override
  String get tunCopy => 'Copiar';

  @override
  String get tunClose => 'Cerrar';

  @override
  String get tunTitle => 'TUN y enrutamiento';

  @override
  String get tunSectionPrivilege => 'Permisos de administrador';

  @override
  String get tunChecking => 'Comprobando…';

  @override
  String get tunNoUacConfigured => 'Inicio sin UAC configurado';

  @override
  String get tunUacEachConnect => 'Se solicitará UAC en cada conexión';

  @override
  String get tunTaskSubtitle =>
      'Una tarea del Programador de tareas de Windows con privilegios máximos (se crea una vez).';

  @override
  String get tunRecreateTask => 'Recrear tarea';

  @override
  String get tunSetupOneUac => 'Configurar (un UAC)';

  @override
  String get tunRemoveTask => 'Eliminar tarea';

  @override
  String get tunSectionAdapter => 'Adaptador';

  @override
  String get tunStack => 'Pila TUN';

  @override
  String get tunSectionRouting => 'Enrutamiento';

  @override
  String get tunStrictRoute => 'Enrutamiento estricto (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 en el túnel';

  @override
  String get tunEndpointNat => 'NAT independiente de extremos (UDP, juegos)';

  @override
  String get tunLanBypass => 'Red local fuera de la VPN';

  @override
  String get tunDnsServer => 'Servidor DNS';

  @override
  String get tunDnsHijack => 'Interceptar DNS (puerto 53)';

  @override
  String get tunResolveStrategy => 'Estrategia de resolución';

  @override
  String get tunSectionDiagnostics => 'Diagnóstico';

  @override
  String get tunSingboxLogLevel => 'Nivel de registro de sing-box';

  @override
  String get tunShowLog => 'Mostrar registro TUN';

  @override
  String get tunDnsVpn => 'A través de VPN (recomendado)';

  @override
  String get tunDnsSystem => 'Sistema';

  @override
  String get tunDnsCustom => 'Servidor propio';

  @override
  String get tunDnsVpnHint => 'Las consultas van al túnel por TCP: sin fugas';

  @override
  String get tunDnsSystemHint => 'Como en Windows: posible fuga de DNS';

  @override
  String get tunDnsCustomHint =>
      'El servidor indicado, también a través del túnel';

  @override
  String get tunExcludeSubnets => 'Subredes fuera de la VPN';

  @override
  String get tunAdd => 'Añadir';

  @override
  String get urlGroupImport => 'Importar';

  @override
  String get urlGroupControl => 'Control';

  @override
  String get urlHintSubUrl => 'URL de suscripción';

  @override
  String get urlHintServerLink => 'enlace del servidor';

  @override
  String get urlDescImportSub => 'Importar una suscripción';

  @override
  String get urlDescImportServer =>
      'Añadir un solo servidor (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'Conectar la VPN';

  @override
  String get urlDescDisconnect => 'Desconectar la VPN';

  @override
  String get urlDescToggle => 'Alternar la VPN';

  @override
  String get urlDescUpdate => 'Actualizar la suscripción activa';

  @override
  String get urlSupportedImport =>
      'Al importar, la app entiende: una URL de suscripción (http/https), y servidores individuales vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — informe para soporte técnico';

  @override
  String get reportDescribeHere =>
      '>>> DESCRIBE EL PROBLEMA AQUÍ (rellena y guarda el archivo): <<<';

  @override
  String get reportWhatDid => 'Qué hacías:';

  @override
  String get reportWhatExpected => 'Qué esperabas:';

  @override
  String get reportWhatHappened => 'Qué ocurrió:';

  @override
  String get reportWhenStarted => 'Cuándo empezó:';

  @override
  String get reportTechNoticeLine1 =>
      'A continuación, información técnica. Revísala antes de enviar;';

  @override
  String get reportTechNoticeLine2 =>
      'aquí no hay contraseñas ni el token de suscripción, la URL de suscripción está oculta.';

  @override
  String get noRealIpTitle => 'Nunca usar mi IP real';

  @override
  String get noRealIpSub =>
      'Incluso con la VPN activa, todo el tráfico «directo» pasa por la VPN (también los sitios RU). La red local sigue directa.';

  @override
  String get flagAuto => 'AUTO';

  @override
  String get autoUpdateIntervalLabel => 'Intervalo de actualización, h';

  @override
  String get autoUpdatePreferSub => 'Usar el intervalo de la suscripción';

  @override
  String get pingLegendInfo =>
      'Color de la etiqueta de ping: verde/amarillo/naranja — el servidor funciona (TCP + comprobación por el túnel). Gris — responde por TCP pero no reenvía el tráfico (puerto Reality típico). Rojo «n/a» — sin respuesta, excluido. El ping siempre se mide DIRECTAMENTE (fuera de la VPN).';

  @override
  String get pingUntestedHint =>
      'Aún no probado. En móvil, Hysteria2 y los perfiles «Auto» se miden solo con la conexión activa.';

  @override
  String get panelTunnelMarker => 'Tiene su propio túnel dividido';

  @override
  String panelInfoServers(Object n) {
    return 'Servidores en el perfil: $n (se elige el mejor)';
  }

  @override
  String get panelInfoDirect =>
      'Parte del tráfico (p. ej. sitios locales) va directo, fuera de la VPN';

  @override
  String get panelInfoBlock =>
      'Parte del tráfico se bloquea (anuncios/torrents)';

  @override
  String get serviceChecksTitle => 'Comprobar servicios';

  @override
  String get serviceChecksInfo =>
      'Seis servicios populares se comprueban solos: primero al iniciar la aplicación con la VPN apagada, y otra vez justo después de conectar. Los dos puntos muestran «antes → después», para ver qué cambió realmente la VPN. Toca para volver a comprobar. Verde: abre; naranja: bloqueo por región; rojo: inaccesible.';

  @override
  String get serviceStatusOk => 'Funciona';

  @override
  String get serviceStatusGeo => 'Se abre, pero bloqueado en el país de salida';

  @override
  String get serviceStatusFail => 'No se abre';

  @override
  String get serviceStatusChecking => 'Comprobando…';

  @override
  String get serviceStatusTap => 'Toca para comprobar';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get homeTunAutotuneProgress => 'Ajustando parámetros de TUN…';

  @override
  String get homeTunAutotuneDone => 'Parámetros de TUN ajustados';

  @override
  String get homeTunAutotuneFailed =>
      'No se pudieron ajustar los parámetros de TUN';

  @override
  String get hy2NoteTitle => 'Servidores Hysteria2';

  @override
  String get hy2NoteBody =>
      'Los servidores Hysteria2 llegan solo en formato XRAY_JSON — SilentGate solicita justamente ese, y sing-box los levanta automáticamente. Si Hysteria2 no aparece en la lista: (para el dueño del panel Remnawave) habilita los inbounds de hysteria y asígnalos a la suscripción. Nota: Remnawave antes de 2.8.0 entrega Hysteria2 SOLO en XRAY_JSON — no está en base64/CLASH/SINGBOX, por eso la regla Response Rules → XRAY_JSON de arriba es obligatoria.';

  @override
  String get enumStatusDisconnected => 'Desconectado';

  @override
  String get enumStatusConnecting => 'Conectando…';

  @override
  String get enumStatusConnected => 'Conectado';

  @override
  String get enumStatusDisconnecting => 'Desconectando…';

  @override
  String get enumStatusError => 'Error';

  @override
  String get enumVariantPlain => 'estándar';

  @override
  String get tagAutoSelect => 'AUTO';

  @override
  String get tagPanel => 'PANEL';

  @override
  String get tagPortHopping => 'SALTO DE PUERTOS';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count servidores',
      one: '$count servidor',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'sin cambios';

  @override
  String get errInvalidJson => 'JSON no válido';

  @override
  String get errPickServerFirst => 'Primero seleccione un servidor';

  @override
  String get errImportSubscriptionFirst => 'Primero importe una suscripción';

  @override
  String get speedSizeFull => '20 MB';

  @override
  String get speedSizeLight => '5 MB';

  @override
  String speedMbPerSec(String value) {
    return '$value MB/s';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value KB/s';
  }

  @override
  String portBusyTitle(int port, String by) {
    return 'El puerto $port ya está ocupado por $by.';
  }

  @override
  String get srvTileMenu => 'Acciones del servidor';

  @override
  String get supportCopyReport => 'Copiar informe';

  @override
  String get supportReportCopied =>
      'Informe copiado: péguelo en el chat de soporte';

  @override
  String subBarUsedOnly(String used) {
    return 'Usado $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'tráfico ilimitado';

  @override
  String get supportDescribeLabel => 'Describa el problema';

  @override
  String get supportDescribeHint =>
      'Qué hizo, qué esperaba, qué ocurrió y cuándo empezó';

  @override
  String get supportDescribeRequired =>
      'Describa el problema: sin descripción el informe es inútil';

  @override
  String get supportNoScreenshots =>
      'No pegue capturas aquí: envíelas en un mensaje aparte en el chat de Telegram.';

  @override
  String get supportDescriptionSection => 'DESCRIPCIÓN DEL USUARIO';

  @override
  String get splitAllowRealIp => 'Permitir IP real para esta regla';

  @override
  String get splitAllowRealIpOn =>
      'Activada: es una excepción, el tráfico saldrá con tu dirección real';

  @override
  String get splitAllowRealIpOff =>
      'Desactivada: la regla va por la VPN — la protección está por encima de todas';

  @override
  String get splitRealIpExposed => 'IP real';

  @override
  String get splitRealIpProtected => 'por VPN';

  @override
  String get vpnActiveBadge => 'VPN activa';

  @override
  String get splitCopyDomain => 'Copiar dirección';

  @override
  String get splitCopyPath => 'Copiar ruta';

  @override
  String get homeServerInfo => 'Info del servidor';

  @override
  String get serverInfoVerifyInBrowser => 'Verificar en el navegador';

  @override
  String get tunDnsForAll => 'DNS de todas las apps por la VPN';

  @override
  String get infoDnsForAll =>
      'Solo en el modo «Solo seleccionadas». ⚠️ Se aplica tras reconectar.';

  @override
  String get homeSettingsNeedReconnect =>
      'Ajuste cambiado: reconéctate para aplicar';

  @override
  String blockPageWindowTitle(String app) {
    return 'Bloqueado — $app';
  }

  @override
  String get blockPageHeading => 'Sitio bloqueado';

  @override
  String blockPageBody(String host, String app) {
    return '$host está bloqueado por una regla de túnel dividido en $app.';
  }

  @override
  String get blockPageHint =>
      'Puedes cambiar la regla: Ajustes → Túnel dividido → Sitios.';

  @override
  String get blockPageNote =>
      'Esta página proviene de la propia aplicación, no es un error de red. El sitio no se abre porque tú mismo lo añadiste a la lista de bloqueo.';

  @override
  String get settingsBlockPage => 'Página de aviso de bloqueo';

  @override
  String get settingsBlockPageSub =>
      'En lugar de un error de conexión se abre una página que explica qué regla cerró el sitio. Solo funciona con http: una página https no se puede sustituir sin instalar nuestro propio certificado raíz en el sistema, y ese certificado permitiría leer todo tu tráfico cifrado.';

  @override
  String get trayCloseFully => 'Cerrar por completo';

  @override
  String errorVpnConflictApp(String app) {
    return 'Parece que $app interfiere: tiene su propio túnel VPN activo. Dos túneles a la vez compiten por la ruta predeterminada.';
  }

  @override
  String errorCloseApp(String app) {
    return 'Cerrar $app';
  }

  @override
  String toastAppClosed(String app) {
    return '$app cerrado';
  }

  @override
  String toastAppCloseFailed(String app) {
    return 'No se pudo cerrar $app: ciérralo manualmente';
  }

  @override
  String get tunBlockQuic => 'Bloquear QUIC (HTTP/3)';

  @override
  String get infoBlockQuic =>
      'Las reglas de sitios coinciden con el NOMBRE, y la aplicación solo ve el nombre en TLS normal. Un navegador que pasa a HTTP/3 no muestra el nombre, así que la regla de dominio no hace nada en silencio. Bloquearlo devuelve el navegador a una conexión normal donde el nombre es visible. Los sitios siguen funcionando: HTTP/3 es opcional, aunque el vídeo puede cargar algo más lento.';

  @override
  String get tunBlockEncryptedDns => 'Bloquear DNS cifrado (DoH/DoT)';

  @override
  String get infoBlockEncryptedDns =>
      'Los navegadores y Windows pueden resolver direcciones por HTTPS, evitando nuestra intercepción. Entonces las reglas «Directo» y «Bloquear» no funcionan a nivel de DNS. ⚠️ Si el navegador tiene un proveedor de DNS cifrado fijo, no volverá al DNS normal: simplemente dejará de abrir sitios. La lista de proveedores conocidos es incompleta por naturaleza.';

  @override
  String get autoUseSpeed => 'Tener en cuenta la velocidad';

  @override
  String get infoAutoUseSpeed =>
      'Tras filtrar por servicios y latencia, los tres mejores candidatos se comprueban descargando y el realmente más rápido queda primero. La velocidad se compara con TU canal: un servidor que ya entrega casi todo deja de juzgarse por megabits y decide la latencia. ⚠️ Consume tráfico de la suscripción: 5 MB para tu canal más 5 MB por candidato, unos 20 MB por pasada.';

  @override
  String get autoSpeedOwn => 'Midiendo tu propia velocidad…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'Midiendo velocidad: $server ($index de $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent % de tu canal';
  }

  @override
  String get conflictDialogTitle => 'Se detectó otro VPN';

  @override
  String conflictDialogBody(String app) {
    return 'Parece que $app está en marcha con su propio túnel activo. Dos túneles a la vez compiten por la ruta predeterminada, así que la conexión puede fallar o quedarse sin acceso a la red.';
  }

  @override
  String get conflictCloseAndConnect => 'Cerrar y conectar';

  @override
  String get conflictConnectAnyway => 'Conectar de todos modos';

  @override
  String get serviceChecksLegendBefore => 'Disponibilidad comprobada sin VPN';

  @override
  String get serviceChecksLegendAfter =>
      'Izquierda — sin VPN, derecha — con VPN';

  @override
  String get serviceChecksBefore => 'Sin VPN';

  @override
  String get serviceChecksAfter => 'Con VPN';

  @override
  String get serviceChecksNoBaseline => 'No comprobado sin VPN';

  @override
  String autoSpeedValue(String value) {
    return '$value Mbit/s';
  }

  @override
  String get splitShowBlockPage => 'Mostrar la página de bloqueo';

  @override
  String get splitBlockPageNeedsVpn =>
      'La página de bloqueo solo funciona con la VPN activa';

  @override
  String get srvInfoNeedsConnection =>
      'En esta plataforma la medición a través del servidor requiere la VPN activa';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ Esta comprobación no detecta la ralentización de YouTube: el proveedor responde con normalidad pero limita la velocidad del vídeo. Verde significa «servicio accesible», no «el vídeo se reproduce».';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<nombre del servidor>';

  @override
  String get urlDescConnectServer =>
      'Conectar a un servidor CONCRETO. El nombre es el que se ve en la lista y envía la suscripción, p. ej. «Polonia 1.5». Los emoji de bandera y las mayúsculas se pueden omitir. Si no hay coincidencia exacta, se busca por país, dirección o protocolo. También funciona con toggle.';

  @override
  String get splitSelectAllFound => 'Marcar todo lo encontrado';

  @override
  String splitAddSelected(int count) {
    return 'Añadir ($count)';
  }

  @override
  String get splitQuicNote =>
      'Mientras exista al menos una regla de sitio, la aplicación desactiva HTTP/3 (QUIC) para todo el tráfico. Si no, el navegador usa HTTP/3, no deja el nombre del sitio y la regla falla en silencio. Los sitios siguen funcionando: pasan a TLS normal, solo algo más lentos.';

  @override
  String get splitNoRealIpBanner =>
      '«Nunca usar mi IP real» está activo: las reglas «Directo» sin la casilla van por la VPN';

  @override
  String get settingsNoRealIpAffects =>
      'Afecta a las reglas «Directo»: sin la casilla «permitir IP real» irán por la VPN';

  @override
  String get splitAppOverrideSites => 'Prioridad sobre las reglas de sitios';

  @override
  String get splitAppOverrideSitesSub =>
      'Todo el tráfico de la aplicación sigue esta regla aunque un sitio diga otra cosa';

  @override
  String get settingsMyRulesOverridePanel =>
      'Mis reglas tienen prioridad sobre las del panel';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'El panel trae su propio enrutamiento, normalmente «los sitios locales evitan la VPN». Se aplica después de tus reglas, así que un sitio marcado «Túnel» puede salir directo con tu IP real. Activado: túnel significa túnel. Coste: los sitios locales darán un rodeo y serán más lentos.';

  @override
  String get commonOpen => 'Abrir';
}
