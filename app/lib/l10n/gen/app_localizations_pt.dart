// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonClose => 'Fechar';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonCopied => 'Copiado';

  @override
  String get commonRefresh => 'Atualizar';

  @override
  String get commonCheck => 'Verificar';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => 'Concluído';

  @override
  String get commonPathCopied => 'Caminho copiado';

  @override
  String get languageTitle => 'Idioma da interface';

  @override
  String get languageSubtitle => 'Escolha o idioma do aplicativo';

  @override
  String get languageSystem => 'Padrão do sistema';

  @override
  String get sectionAppearance => 'Aparência e comportamento';

  @override
  String get sectionCapture => 'Captura de tráfego';

  @override
  String get sectionReliability => 'Confiabilidade da conexão';

  @override
  String get sectionPing => 'Ping';

  @override
  String get sectionIdentity => 'Identidade do painel';

  @override
  String get sectionNetwork => 'Rede';

  @override
  String get sectionAbout => 'Sobre';

  @override
  String get sectionSupport => 'Suporte';

  @override
  String get appearanceTheme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Escuro';

  @override
  String get closeToTrayTitle => 'Minimizar para a bandeja ao fechar';

  @override
  String get closeToTraySubtitle =>
      'O botão de fechar oculta a janela na bandeja; desative para encerrar o aplicativo';

  @override
  String get autoUpdateSubTitle => 'Atualização automática da assinatura';

  @override
  String get autoUpdateSubText =>
      'Atualizar periodicamente a lista de servidores';

  @override
  String get captureSystemProxy => 'Proxy do sistema';

  @override
  String get captureSystemProxySub =>
      'Funciona agora. Sem direitos de administrador.';

  @override
  String get captureTun => 'TUN (túnel completo)';

  @override
  String get captureTunBadgeUac => 'requer UAC';

  @override
  String get captureTunSub =>
      'Todo o tráfego, incluindo UDP e aplicativos que ignoram o proxy. Requer direitos de administrador.';

  @override
  String get tunProvider => 'Provedor TUN';

  @override
  String get tunRoutingTitle => 'TUN e roteamento';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'Pilha $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'Túnel dividido';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n regras ($apps aplicativos, $sites sites)';
  }

  @override
  String get captureTunHint =>
      'As configurações de TUN, DNS e túnel dividido aparecem quando o modo TUN está selecionado — no modo de proxy do sistema elas não têm efeito.';

  @override
  String get dnsShortVpn => 'via VPN';

  @override
  String get dnsShortSystem => 'sistema';

  @override
  String get dnsShortCustom => 'personalizado';

  @override
  String get tunUacTitle => 'TUN requer direitos de administrador';

  @override
  String get tunUacBody =>
      'Você pode configurá-lo uma vez: o aplicativo criará uma tarefa no Agendador de Tarefas do Windows com os privilégios mais altos e, depois disso, o túnel iniciará SEM uma solicitação de UAC.\n\nUma solicitação de administrador aparecerá agora. O próprio aplicativo continua funcionando sem direitos elevados.';

  @override
  String get tunUacLater => 'Mais tarde (perguntar sempre)';

  @override
  String get tunUacSetup => 'Configurar';

  @override
  String get tunUacDone =>
      'Concluído: o TUN iniciará sem uma solicitação de UAC';

  @override
  String get tunUacFail =>
      'Não foi possível criar a tarefa — o UAC será solicitado ao conectar';

  @override
  String get autoReconnectTitle => 'Reconexão automática';

  @override
  String get autoReconnectSub =>
      'Restaurar a conexão em caso de queda e mudança de rede';

  @override
  String get killSwitchTitle => 'Kill switch';

  @override
  String get alwaysOnTitle => 'Proteção do sistema';

  @override
  String get alwaysOnSub =>
      'VPN sempre ativa e «bloquear conexões sem VPN» — funciona mesmo com o app fechado';

  @override
  String get killSwitchSubTun =>
      'Não deixar o tráfego contornar a VPN durante a reconexão';

  @override
  String get killSwitchSubProxy =>
      'No modo “Proxy do sistema” protege apenas os aplicativos compatíveis com proxy. Totalmente — somente TUN';

  @override
  String get killSwitchSubOff =>
      'Requer que a reconexão automática esteja ativada';

  @override
  String get networkRecoverTitle => 'Recuperar rede';

  @override
  String get networkRecoverSub =>
      'Se a internet sumiu após a VPN. Requer direitos de administrador';

  @override
  String get networkRecoverConfirmTitle => 'Recuperar rede?';

  @override
  String get networkRecoverConfirmBody =>
      'Redefinição do winsock, da pilha de IP, do DNS e do proxy do sistema. São necessários direitos de administrador (UAC). A redefinição do winsock/IP passa a valer após uma reinicialização.';

  @override
  String get networkRecoverConfirmOk => 'Recuperar';

  @override
  String get interferenceTitle => 'Verificar interferência (outras VPNs)';

  @override
  String get interferenceDialogTitle => 'Interferência de rede';

  @override
  String get interferenceNoneFound =>
      'Nenhuma outra VPN ou interferência detectada.';

  @override
  String get interferenceIgnore => 'Ignorar';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'Atualizado automaticamente com a versão do aplicativo. Também são enviados: X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'Esquemas de URL';

  @override
  String get urlSchemesSub =>
      'Importar e controlar a VPN por links (conectar / alternar / atualizar)';

  @override
  String get panelOwnerTitle => 'Para o dono do painel';

  @override
  String get panelOwnerBody =>
      'Usuários comuns não precisam disso — você pode pular.\n\nPara que o aplicativo receba sua assinatura no formato JSON correto (XRAY_JSON), adicione este bloco às Response Rules do seu painel Remnawave — ele corresponde ao nosso User-Agent:';

  @override
  String get panelOwnerCopy => 'Copiar bloco';

  @override
  String get aboutVersion => 'Versão do SilentGate';

  @override
  String get aboutXrayCore => 'Núcleo Xray';

  @override
  String get aboutHwid => 'HWID do dispositivo';

  @override
  String get aboutThirdPartyTitle => 'Componentes de terceiros e licenças';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — executados como processos separados';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — integrados ao aplicativo';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'Registros';

  @override
  String get logsSub =>
      'Aplicativo e TUN (sing-box): importação da assinatura, ping, erros';

  @override
  String get thirdPartyTitle => 'Componentes de terceiros';

  @override
  String get thirdPartyBody =>
      'O SilentGate é distribuído junto com executáveis de terceiros. Eles são executados como processos SEPARADOS e não estão incorporados ao aplicativo.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  Túnel TUN e núcleo de proxy para Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — licença Wintun\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — dados de roteamento, CC-BY-SA-4.0\n\nOs textos completos das licenças estão na pasta “licenses” ao lado do aplicativo.';

  @override
  String get supportSectionNote =>
      'Toque em “Contatar o suporte” — abre-se uma janela onde você mesmo gera um arquivo de registro (versões, SO, configurações, app.log + o final do singbox.log; sem senhas ou token de assinatura, URL oculta). Depois disso aparece um botão para enviá-lo ao suporte no Telegram.';

  @override
  String get supportButtonTitle => 'Contatar o suporte';

  @override
  String get supportButtonSub => 'Gerar um registro e abrir o chat de suporte';

  @override
  String get supportDialogTitle => 'Suporte';

  @override
  String get supportDialogTitleDone =>
      'O registro está pronto — para onde enviar';

  @override
  String get supportWhatWillHappen => 'O que vai acontecer:';

  @override
  String get supportBullet1 =>
      '• Um único arquivo reunirá versões, SO, configurações e registros (app.log + o final do singbox.log). Ele não contém senhas ou token de assinatura, e a URL da assinatura está oculta.';

  @override
  String get supportBullet2 =>
      '• Após tocar, PRIMEIRO abre-se a pasta com o arquivo e depois o próprio arquivo. Descreva o problema no topo, salve-o — e aparece um botão para enviá-lo ao suporte.';

  @override
  String supportError(String error) {
    return 'Falha ao gerar o relatório: $error';
  }

  @override
  String get supportDoneText =>
      'O relatório foi gerado e aberto (pasta, depois arquivo). Descreva o problema no topo, salve o arquivo e envie-o ao suporte — o aplicativo ajudará a abrir o Telegram.';

  @override
  String get supportWhoTo => 'Para onde enviar:';

  @override
  String get supportContact => 'Contatar o suporte';

  @override
  String supportContactNamed(String name) {
    return 'Contatar o suporte ($name)';
  }

  @override
  String get supportDevServiceName => 'Desenvolvedor do cliente';

  @override
  String get supportShowOnPc => 'Mostrar no PC';

  @override
  String get supportCopyPath => 'Copiar caminho';

  @override
  String get supportGenerating => 'Gerando…';

  @override
  String get supportGenerateButton => 'Gerar um registro de suporte';

  @override
  String get pingTwoPhaseTitle => 'Verificar se funciona (pelo túnel)';

  @override
  String get pingTwoPhaseSubOn =>
      'Após o TCP — uma solicitação pelo servidor: filtra os que não funcionam (Reality etc.)';

  @override
  String get pingTwoPhaseSubOff =>
      'É usado apenas o único método selecionado (abaixo)';

  @override
  String get pingMethodCheck => 'Método de verificação:';

  @override
  String get pingMethodPing => 'Método de ping:';

  @override
  String get speedTestProbe => 'Sonda de teste de velocidade:';

  @override
  String get speedTestFull => '20 MB (mais preciso)';

  @override
  String get speedTestLight => '5 MB (econômico)';

  @override
  String get testUrlLabel => 'URL de teste (via proxy)';

  @override
  String get appUpdateServerUnavailable =>
      'Servidor de atualização indisponível';

  @override
  String appUpdateAvailable(String version) {
    return 'Versão $version disponível';
  }

  @override
  String get appUpdateLatest => 'Você tem a versão mais recente';

  @override
  String get appUpdateDownload => 'Baixar';

  @override
  String get appUpdateCheckTitle => 'Verificar atualizações ao iniciar';

  @override
  String get appUpdateManual => 'Download e instalação — manuais';

  @override
  String get appUpdateEndpointLabel => 'Endpoint de versão';

  @override
  String get urlSchemeSilentgateTitle => 'Links silentgate://';

  @override
  String get urlSchemeSilentgateSub =>
      'Importar e controlar a VPN por links. Ativado por padrão';

  @override
  String get urlSchemeDisableTitle => 'Desativar os links silentgate://?';

  @override
  String get urlSchemeDisableBody =>
      'A importação por link e os esquemas de controle (conectar / desconectar / alternar / atualizar) deixarão de funcionar. Deixe ativado se não tiver certeza.';

  @override
  String get urlSchemeDisableOk => 'Desativar';

  @override
  String get urlSchemeServerTitle => 'Abrir links de servidor';

  @override
  String get urlSchemeServerSub =>
      'Interceptar vless:// e outros de outros clientes';

  @override
  String get urlSchemeServerConfirmTitle => 'Interceptar links de servidor?';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nEsses links geralmente estão vinculados a outro cliente VPN (Happ, v2rayTun). O SilentGate assumirá o controle deles.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'Interceptar';

  @override
  String get urlSchemeAutoConnect => 'Conectar após a importação';

  @override
  String get autoTitle => 'Configuração automática';

  @override
  String get autoClearResults => 'Limpar resultados';

  @override
  String autoFoundWorking(Object count) {
    return 'Funcionando encontrados: $count';
  }

  @override
  String get autoPinnedTop => ' — fixados no topo da lista';

  @override
  String get autoSearchContinues => ' (a busca continua…)';

  @override
  String get autoCheckServices => 'Verificar serviços';

  @override
  String get autoPinFoundOnTop =>
      'Fixar os servidores encontrados no topo da lista';

  @override
  String get autoTryFragment => 'Tentar contornar (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'Sem assinatura. Cole uma única chave — encontraremos configurações que funcionam:';

  @override
  String get autoTuneByKey => 'Ajustar pela chave';

  @override
  String autoTesting(int index, int total) {
    return 'Testando $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'Variante: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$ok de $total serviços';
  }

  @override
  String get autoConnect => 'Conectar';

  @override
  String get autoStopSearch => 'Parar busca';

  @override
  String get autoDoneRefreshPing =>
      'Concluído — atualizar o ping dos encontrados';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return 'Encontrados $count, fixados no topo. Atualizando ping…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'Servidores para ajustar ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'Todos';

  @override
  String get autoDeselectAll => 'Limpar';

  @override
  String get autoTuneSelected => 'Ajustar selecionados';

  @override
  String autoTuned(Object label) {
    return 'Ajustado: $label';
  }

  @override
  String get infoDialogTitle => 'Informação';

  @override
  String get infoCopied => 'Explicação copiada';

  @override
  String get commonGotIt => 'Entendi';

  @override
  String get enumSplitAll => 'Tudo — pela VPN';

  @override
  String get enumSplitOnly => 'Apenas selecionados — pela VPN';

  @override
  String get enumSplitExcept => 'Selecionados — fora da VPN';

  @override
  String get enumActionTunnel => 'Túnel';

  @override
  String get enumActionDirect => 'Direto';

  @override
  String get enumActionBlock => 'Bloquear';

  @override
  String homeUpdateAvailable(Object version) {
    return 'Versão $version disponível';
  }

  @override
  String get homeDownload => 'Baixar';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'Assinatura atualizada: $summary';
  }

  @override
  String get homeReconnect => 'Reconectar';

  @override
  String homePingProgress(int done, int total) {
    return 'Testando servidores: $done de $total';
  }

  @override
  String get homeAutoConfigStarting => 'Iniciando configuração automática…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'Configuração automática: $current de $total — $name';
  }

  @override
  String get homeImport => 'Importar';

  @override
  String get homeSettings => 'Configurações';

  @override
  String get homeAutoBest => 'Automático (melhor servidor)';

  @override
  String get homeAutoConfig => 'Configuração automática';

  @override
  String homeServersCount(Object count) {
    return 'Servidores ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return 'Encontrados $found de $total';
  }

  @override
  String get homePingServers => 'Testar servidores';

  @override
  String get homePingFound => 'Testar encontrados';

  @override
  String get homeNothingFound => 'Nada encontrado';

  @override
  String get homeOnboardingTitle => 'Comece importando uma assinatura';

  @override
  String get homeOnboardingSubtitle =>
      'Cole um link Remnawave ou uma única chave';

  @override
  String get homeImportSubscription => 'Importar assinatura';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'Esta sessão: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(String used, String total) {
    return '$used de $total';
  }

  @override
  String get subBarSubscription => 'Assinatura';

  @override
  String get subBarRefreshing => 'Atualizando…';

  @override
  String get subBarRefreshSubscription => 'Atualizar assinatura';

  @override
  String get subBarSupport => 'Suporte';

  @override
  String get subBarRefresh => 'Atualizar';

  @override
  String get subBarAddSubscription => 'Adicionar assinatura';

  @override
  String get subBarCopyLink => 'Copiar link';

  @override
  String get subBarDeleteSubscription => 'Excluir assinatura';

  @override
  String get subBarLinkCopied => 'Link copiado';

  @override
  String get subBarDeleteConfirmTitle => 'Excluir assinatura?';

  @override
  String get subBarDeleteConfirmBody =>
      'Os servidores desta assinatura serão removidos da lista.';

  @override
  String subBarDeletePinned(Object count) {
    return 'Também excluir os fixados ($count) com suas edições';
  }

  @override
  String get subBarDeletePinnedHint =>
      'Caso contrário, eles permanecem na lista e sobrevivem à exclusão';

  @override
  String get subBarCancel => 'Cancelar';

  @override
  String get subBarDelete => 'Excluir';

  @override
  String get subBarSubscriptionDeleted => 'Assinatura excluída';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'Assinatura atualizada: $summary';
  }

  @override
  String get subBarMore => 'Detalhes';

  @override
  String subBarAdded(Object count) {
    return 'Adicionados ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'Removidos ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· atualização automática ${hours}h';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'Válida: ilimitada  $auto';
  }

  @override
  String get subBarExpired => 'Assinatura expirada:';

  @override
  String get subBarValidUntil => 'Válida até:';

  @override
  String get infoCaptureMode =>
      'Como o tráfego é interceptado. «Proxy do sistema» define um proxy local no sistema (sem direitos de administrador; captura navegadores e a maioria dos aplicativos). «TUN» é um adaptador de rede virtual que captura TODO o tráfego (incluindo UDP e aplicativos que ignoram o proxy), mas requer direitos de administrador.';

  @override
  String get infoSystemProxy =>
      'Um proxy HTTP local nas configurações do sistema (registro WinINET). Sem direitos de administrador. Não intercepta UDP nem aplicativos que ignoram o proxy do sistema.';

  @override
  String get infoTunMode =>
      'Um túnel completo pelo adaptador virtual wintun + sing-box. Captura todo o tráfego, incluindo UDP. Solicita direitos de administrador (UAC) quando ativado.';

  @override
  String get infoTunProvider =>
      'O driver do adaptador de rede virtual. No Windows, é usado o wintun (incluído com o núcleo). Nenhum outro driver é necessário.';

  @override
  String get infoTunStack =>
      'A pilha de rede TUN (sing-box).\n\n«auto» — SELEÇÃO AUTOMÁTICA: se o túnel não conseguir subir, o próprio aplicativo percorre system → gvisor → mixed e depois reduz o MTU (1400, 1280). A combinação que funcionou é lembrada e testada primeiro na próxima vez. O progresso da seleção é mostrado no status e no registro.\n\nUma escolha explícita desativa a seleção automática: system — a pilha do SO, a mais rápida, mas mais delicada com antivírus; gvisor — em espaço de usuário, mais lenta, máxima compatibilidade; mixed — TCP via system, UDP via gvisor.';

  @override
  String get infoTunMtu =>
      'O tamanho máximo do pacote no adaptador TUN. O padrão é 1500; reduza-o (1400, 1280) se ocorrerem desconexões — um valor muito pequeno reduz a velocidade.\n\nCom a pilha «auto» este é apenas o valor inicial: se o túnel não conseguir subir, o próprio aplicativo tentará MTUs menores.';

  @override
  String get infoTunStrictRoute =>
      'Roteamento estrito no sing-box. No Windows corrige dois problemas típicos: vazamentos de DNS (por padrão o sistema envia consultas a todos os adaptadores de uma vez) e erros de «rede inacessível». Desative-o apenas se ele quebrar o VirtualBox/Hyper-V.';

  @override
  String get infoTunIpv6 =>
      'Rotear IPv6 para o túnel. Se você desativá-lo enquanto seu provedor tem IPv6 ativado, parte do tráfego sairá FORA da VPN (vazando seu endereço real) ou travará. Desative-o apenas se você tiver problemas de rede IPv6.';

  @override
  String get infoTunEndpointIndependentNat =>
      'Modo NAT para UDP. Necessário para jogos, chats de voz e WebRTC — sem ele, as conexões podem não se estabelecer. Desative-o apenas para economizar memória.';

  @override
  String get infoTunBypassLan =>
      'A rede local (endereços privados 192.168.*, 10.*, roteador, impressoras, NAS) contorna a VPN. Normalmente você quer isso ativado, caso contrário perde o acesso aos dispositivos da rede.';

  @override
  String get infoTunExcludeCidrs =>
      'Sub-redes adicionais que sempre contornam a VPN (formato CIDR, por exemplo 10.8.0.0/24). Útil para redes corporativas e outras VPNs.';

  @override
  String get infoTunPrivilege =>
      'O TUN requer direitos de administrador. Uma vez, criamos uma tarefa no Agendador de Tarefas do Windows com os privilégios mais altos — depois disso o túnel inicia SEM uma solicitação de UAC a cada conexão. A tarefa pertence a você e é removida com o botão abaixo ou quando o programa é desinstalado.';

  @override
  String get infoAppUpdate =>
      'Uma vez por inicialização, o aplicativo pergunta ao seu servidor se existe uma versão mais nova e mostra uma notificação com um botão «Baixar».\n\nO aplicativo não baixa nem executa NADA por conta própria: o instalador não é assinado com um certificado, e a execução automática de um exe baixado esbarra no SmartScreen e parece, para os antivírus, comportamento de malware. Você mesmo instala a atualização.\n\nSe o servidor estiver indisponível, o aplicativo simplesmente fica em silêncio e grava uma entrada no registro. O formato da resposta e a configuração do servidor estão descritos em docs/APP_UPDATE.md.';

  @override
  String get infoSpeedTest =>
      'A quantidade de dados baixados ao medir a velocidade (clique com o botão direito em um servidor → «Informações do servidor» → «Medir velocidade»).\n\n20 MB — o modo principal: em links rápidos (100+ Mbps) uma sonda curta não tem tempo de acelerar e subestima o resultado.\n5 MB — o modo econômico: consideravelmente mais barato em tráfego, útil para percorrer muitos servidores.\n\nA medição ocorre APENAS manualmente e consome o tráfego da sua assinatura. A velocidade é medida duas vezes: diretamente e pelo servidor selecionado, para que você veja exatamente quanto é perdido na VPN.';

  @override
  String get infoAutoReconnect =>
      'Se o núcleo travou, o servidor caiu ou a rede mudou (Wi-Fi ↔ cabo, retorno da suspensão, um novo IP), o aplicativo restabelece a conexão por conta própria. As pausas entre as tentativas aumentam: 0,8 s → 3 s → 8 s → 20 s, até 8 tentativas, após as quais um erro é mostrado. Desconectar pelo botão sempre cancela a recuperação.\n\nUma mudança de rede é detectada pelos endereços reais de outros adaptadores: o seu próprio túnel e endereços de serviço (link-local) não são contados, uma mudança só é aceita se persistir por duas verificações seguidas, e o sinal é ignorado nos primeiros 15 segundos após a conexão. Sem essas salvaguardas, subir o túnel seria por si só considerado uma «mudança de rede» e causaria reconexões infinitas.';

  @override
  String get infoKillSwitch =>
      'Não deixar o tráfego sair contornando a VPN enquanto a conexão está sendo restaurada. A captura NÃO é liberada entre as tentativas: no modo TUN o adaptador permanece ativo, no modo «Proxy do sistema» o proxy permanece configurado — os aplicativos recebem um erro de conexão em vez de acesso não criptografado à internet.\n\nHonestamente sobre os limites: no modo «Proxy do sistema» isso protege apenas os programas que respeitam o proxy do sistema (navegadores e a maioria dos aplicativos). Programas que ignoram o proxy, e o UDP, sairão diretamente — a total estanqueidade é fornecida apenas pelo modo TUN. Requer a reconexão automática ativada.';

  @override
  String get infoUserAgent =>
      'Como o aplicativo se identifica ao painel (o cabeçalho User-Agent). Ele sempre envia «SilentGate/versão (Windows)».\n\nPor esse nome, o painel Remnawave escolhe o FORMATO da assinatura. É necessário o XRAY_JSON — ele entrega configurações de servidor prontas; a partir de uma lista base64 de links algumas configurações são restauradas aproximadamente, e a seleção automática (burstObservatory) funciona pior.\n\nConfigurado no painel: Templates → Response Rules → uma regra com a condição user-agent CONTAINS SilentGate e tipo de resposta XRAY_JSON (coloque-a acima da regra Fallback Base64).\n\nO campo de substituição é necessário apenas como uma solução temporária — se o painel ainda não conhece o aplicativo, você pode se identificar como um cliente que ele conhece.';

  @override
  String get infoDnsMode =>
      'Quem resolve os domínios no modo TUN. «Via VPN» (recomendado) — as consultas entram no túnel por TCP, e seu provedor não vê quais sites você abre. «Sistema» — como no Windows: um vazamento de DNS é possível, e se o servidor não passar UDP, a internet pode cair completamente. «Personalizado» — o servidor que você especificar, pelo túnel.';

  @override
  String get infoDnsCustomServer =>
      'O endereço do servidor DNS para o modo «Personalizado» (por exemplo 9.9.9.9 ou 8.8.8.8). As consultas a ele passam pelo túnel por TCP.';

  @override
  String get infoDnsHijack =>
      'Interceptar consultas DNS (porta UDP 53) dentro do túnel. Sem isso, as consultas escapam das regras: um vazamento é possível, e as regras de domínio do túnel dividido funcionam com menos precisão.';

  @override
  String get infoDnsStrategy =>
      'Quais endereços solicitar: prefer_ipv4 (recomendado) — IPv4 primeiro, ipv4_only — apenas IPv4 (corrige problemas com IPv6 quebrado), prefer_ipv6/ipv6_only — para redes IPv6.';

  @override
  String get infoSingboxLogLevel =>
      'A verbosidade do registro do sing-box (%APPDATA%\\SilentGate\\singbox.log). warn — modo normal. info/debug — se o túnel não funcionar: o registro mostrará a causa exata. debug aumenta consideravelmente o tamanho do arquivo.';

  @override
  String get infoSplitMode =>
      'A base — para onde vai tudo que não tem uma ação definida manualmente, e qual ação é atribuída às novas entradas. «Tudo — pela VPN»: por padrão todo o tráfego para o túnel. «Apenas selecionados — pela VPN»: por padrão diretamente, para o túnel apenas os marcados como «Túnel». «Selecionados — fora da VPN»: o oposto, tudo para o túnel, e os marcados como «Direto» vão diretamente.';

  @override
  String get infoSplitApps =>
      'Clique em um aplicativo — abre-se uma janela onde você escolhe a ação (Túnel — pela VPN, Direto — fora da VPN, Bloquear — sem rede) e o método de correspondência: pelo nome do exe (confiável) ou pelo caminho completo. Você pode escolher entre os aplicativos em execução ou especificar um .exe.';

  @override
  String get infoSplitDomains =>
      'Domínios (sufixos). Por exemplo, youtube.com também cobre www.youtube.com. Funciona pelo nome da conexão TLS (SNI).';

  @override
  String get infoVerifyViaProxy =>
      'Primeiro verificamos a funcionalidade pelo proxy (o servidor realmente retorna 204) e, só se o servidor respondeu, medimos separadamente a latência com o método escolhido (TCP/ICMP).';

  @override
  String get infoProxyGet =>
      'Uma solicitação GET pelo túnel para a URL de teste. Verifica se o servidor realmente passa tráfego e retorna 204. O teste de funcionalidade mais honesto; um pouco mais lento.';

  @override
  String get infoProxyHead =>
      'Como o GET, mas apenas os cabeçalhos — mais rápido e menos tráfego. Alguns servidores/CDNs podem não suportar HEAD.';

  @override
  String get infoTcp =>
      'O tempo do handshake TCP com o endereço do servidor. Um indicador de latência rápido e preciso, mas não prova que o túnel funciona: um servidor Reality responderá ao TCP mesmo se o proxy estiver bloqueado. Recomendado para latência.';

  @override
  String get infoIcmp =>
      'Ping do sistema. Muitas vezes inútil para Reality/CDN: o ICMP pode estar bloqueado, ou mede o nó CDN mais próximo. Mantenha-o para diagnóstico de rede.';

  @override
  String get infoTestUrl =>
      'A URL para verificar a funcionalidade pelo proxy. Por padrão https://www.gstatic.com/generate_204 — ela retorna uma resposta 204 vazia, o que é conveniente e rápido.';

  @override
  String get infoAutoConfig =>
      'Percorre servidores e variantes de evasão (fragment, fingerprint) e cria uma lista daqueles em que os serviços selecionados funcionam. Não para no primeiro — você escolhe entre os encontrados. A verificação é feita pelo proxy; a VPN não é ativada durante esse período.';

  @override
  String get infoAutoConfigServices =>
      'Quais serviços devem funcionar para que um servidor seja considerado adequado. A verificação é resistente às páginas de bloqueio do provedor (a assinatura da resposta é verificada, não apenas um «200 OK»).';

  @override
  String get infoAutoPinFound =>
      'As combinações funcionais encontradas (servidor + variante de evasão) são imediatamente fixadas no topo da lista geral de servidores, para que você possa usá-las sem voltar aqui. Desative-o se você não quiser que a configuração automática altere a ordem da sua lista — os resultados ainda ficarão visíveis nesta tela.';

  @override
  String get infoTryFragment =>
      'Tentar a variante com fragmentação do TLS ClientHello (evasão de DPI) se o servidor «puro» não funcionar. Um pouco mais demorado, mas encontra uma combinação funcional em servidores com restrições.';

  @override
  String get infoAutoStrategy =>
      '«Primeiro funcional» — percorrer tudo e conectar a qualquer um encontrado (você escolhe). «Melhor dentro do orçamento» — buscar dentro de um limite de tempo e escolher o mais rápido.';

  @override
  String get infoScheme =>
      'Registra o protocolo silentgate:// no sistema (para o usuário atual, sem direitos de administrador). Depois disso, clicar em um link silentgate://import?url=… (importação) ou silentgate://connect / toggle (controle) em um navegador abre o aplicativo e executa a ação. Ativado por padrão.';

  @override
  String get infoAutoConnectAfterImport =>
      'Conectar ao primeiro servidor imediatamente após uma importação de assinatura bem-sucedida por link.';

  @override
  String get infoNetworkRecover =>
      'Redefine os parâmetros de rede se a internet sumiu após uma falha/desligamento do PC com a VPN ativada: winsock, a pilha de IP, o cache de DNS, o proxy do sistema. Requer direitos de administrador; a redefinição do winsock e da pilha de IP passa a valer após uma REINICIALIZAÇÃO.';

  @override
  String get infoInterference =>
      'Uma verificação de outras VPNs e interferências de rede (adaptadores TUN estranhos, processos de VPN, zapret/GoodbyeDPI) que podem entrar em conflito com o SilentGate. Você pode fechá-los ou ignorá-los.';

  @override
  String get pingInfoProxyGet =>
      'Uma solicitação GET pelo túnel para a URL de teste. Verifica se o servidor realmente passa tráfego e retorna 204. O teste de funcionalidade mais honesto; um pouco mais lento por baixar a resposta completa. Recomendado para uma verificação de funcionalidade.';

  @override
  String get pingInfoProxyHead =>
      'Como o GET, mas solicita apenas os cabeçalhos — menos tráfego e mais rápido. Verifica a funcionalidade do túnel; alguns servidores/CDNs podem não suportar HEAD.';

  @override
  String get pingInfoTcp =>
      'Mede o tempo do handshake TCP com o endereço do servidor. Um indicador rápido e preciso da latência do endpoint, mas não prova que o túnel funciona: um servidor Reality responderá ao TCP mesmo se o proxy estiver bloqueado. Recomendado para latência.';

  @override
  String get pingInfoIcmp =>
      'Ping do sistema (echo request). Muitas vezes inútil para Reality/CDN: o ICMP pode estar bloqueado, ou mede o nó CDN mais próximo em vez do servidor. Mantenha-o para diagnóstico de rede.';

  @override
  String get pingInfoTwoPhase =>
      'Após a verificação TCP, os servidores que responderam são verificados adicionalmente com uma solicitação pelo túnel (GET/HEAD para a URL de teste). Isso filtra os servidores que mantêm a porta aberta mas não passam tráfego. A latência ainda é mostrada pelo TCP.';

  @override
  String get pingInfoTunStage =>
      'Um túnel completo (TUN) é a próxima etapa. Agora está em uso o modo «Proxy do sistema». No modo TUN, todo o tráfego (incluindo UDP e aplicativos que ignoram o proxy) passará pelo adaptador virtual wintun + tun2socks. Requer direitos de administrador.';

  @override
  String get pingInfoTunStack =>
      'A pilha de rede TUN (sing-box). auto — deixar a critério do núcleo (atualmente mixed). system — a pilha do SO: velocidade máxima, mas mais delicada com direitos/antivírus. gvisor — uma pilha em espaço de usuário: mais lenta, mas a mais compatível. mixed — TCP via system, UDP via gvisor (um equilíbrio). Se o TUN não conectar ou derrubar as conexões — tente o gvisor.';

  @override
  String get pingInfoAutoConfig =>
      'Quando ativado, o próprio aplicativo percorre servidores e variantes de evasão (fragment, fingerprint) e conecta ao primeiro em que os serviços selecionados funcionam (verificando pelo proxy, sem ativar a VPN durante a busca).';

  @override
  String get logsTabApp => 'Aplicativo';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'Atualizar';

  @override
  String get logsCopy => 'Copiar';

  @override
  String get logsClearApp => 'Limpar registro do aplicativo';

  @override
  String get logsCopied => 'Registro copiado';

  @override
  String get logsLoading => 'Carregando…';

  @override
  String get logsEmpty => 'Vazio por enquanto.';

  @override
  String get logsTunEmpty =>
      'Vazio — o TUN ainda não foi iniciado neste sistema.';

  @override
  String get importScrDone => 'Importado';

  @override
  String get importScrWelcome => 'Bem-vindo ao SilentGate';

  @override
  String get importScrTitle => 'Importar assinatura';

  @override
  String get importScrSubscriptionFallback => 'Assinatura';

  @override
  String get importScrHint =>
      'Cole um link de assinatura (Remnawave), um deep link silentgate:// ou um único link vless:// / vmess:// / trojan:// / ss:// / hysteria2://';

  @override
  String get importScrLoading => 'Carregando…';

  @override
  String get importScrPasteImport => 'Importar da área de transferência';

  @override
  String get importScrImportField => 'Importar do campo';

  @override
  String get serversTitle => 'Servidores';

  @override
  String serversFound(int found, int total) {
    return 'Servidores — encontrados $found de $total';
  }

  @override
  String get serversRefresh => 'Atualizar assinatura';

  @override
  String get serversPinging => 'Testando…';

  @override
  String get serversPingAll => 'Testar todos';

  @override
  String get serversPingFound => 'Testar encontrados';

  @override
  String get serversEmpty =>
      'A lista de servidores está vazia. Importe uma assinatura.';

  @override
  String get serversNothingFound => 'Nada encontrado';

  @override
  String get toastCopied => 'Copiado';

  @override
  String get toastHide => 'Ocultar';

  @override
  String get srvInfoTitle => 'Informações do servidor';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'Falha ao iniciar a conexão de teste: $error';
  }

  @override
  String get srvInfoServerAddressFailed =>
      'Não foi possível determinar o endereço do servidor';

  @override
  String get srvInfoSectionExit => 'Onde você sai';

  @override
  String get srvInfoExitHint =>
      'Determinado a partir do endereço do servidor — nenhum túnel é iniciado para isso.';

  @override
  String get srvInfoAddressLocation => 'Endereço e localização do servidor';

  @override
  String get srvInfoCheckAgain => 'Verificar novamente';

  @override
  String get srvInfoSectionSpeed => 'Velocidade';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'A sonda baixa $size e usa o tráfego da sua assinatura. O tamanho pode ser alterado nas configurações.';
  }

  @override
  String get srvInfoViaServer => 'Via servidor';

  @override
  String get srvInfoWithoutVpn => 'Sem VPN';

  @override
  String get srvInfoMeasuring => 'Medindo…';

  @override
  String get srvInfoMeasureSpeed => 'Medir velocidade';

  @override
  String get srvInfoSectionParams => 'Parâmetros de conexão';

  @override
  String get srvInfoParamAddress => 'Endereço';

  @override
  String get srvInfoParamProtocol => 'Protocolo';

  @override
  String get srvInfoParamTransport => 'Transporte';

  @override
  String get srvInfoParamTlsFingerprint => 'Impressão digital TLS';

  @override
  String get srvInfoParamType => 'Tipo';

  @override
  String get srvInfoPanelAutoProfile =>
      'Perfil de seleção automática do painel';

  @override
  String get srvInfoCouldNotDetermine => 'não foi possível determinar';

  @override
  String get srvInfoCopy => 'Copiar';

  @override
  String get editorJsonTitle => 'Configuração JSON';

  @override
  String get editorCopy => 'Copiar';

  @override
  String get editorClose => 'Fechar';

  @override
  String get editorTitle => 'Editar servidor';

  @override
  String get editorFieldName => 'Nome';

  @override
  String get editorFieldAddress => 'Endereço';

  @override
  String get editorFieldPort => 'Porta';

  @override
  String get editorFieldUuidPassword => 'UUID / senha';

  @override
  String get editorFieldObfs => 'Ofuscação (geralmente salamander)';

  @override
  String get editorFieldObfsPassword => 'Senha de ofuscação';

  @override
  String get editorFieldPortHopping => 'Salto de portas (ex.: 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'Permitir certificado autoassinado';

  @override
  String get editorAllowSelfSignedSub =>
      'Necessário apenas se o servidor estiver configurado assim';

  @override
  String get editorTransport => 'Transporte';

  @override
  String get editorSecurity => 'Segurança';

  @override
  String get editorNone => '(nenhum)';

  @override
  String get editorCancel => 'Cancelar';

  @override
  String get editorSave => 'Salvar';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count servidores$burst';
  }

  @override
  String get jsonCompositionUnknown => 'composição desconhecida';

  @override
  String get jsonYourSavedOverride => 'Seu JSON salvo (substituição)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'Perfil de seleção automática do painel: $summary — aplicado por completo';
  }

  @override
  String get jsonPanelConfig => 'Configuração do painel (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'Criado a partir do link de compartilhamento — o painel não enviou JSON. Atualize a assinatura; se isso não ajudar, verifique a regra Response Rules no painel.';

  @override
  String get jsonInvalidJson => 'JSON inválido';

  @override
  String get jsonSaved => 'Salvo';

  @override
  String get jsonTitle => 'Configuração JSON';

  @override
  String get jsonFieldEditor => 'Editor de campos';

  @override
  String get jsonCopy => 'Copiar';

  @override
  String get jsonClose => 'Fechar';

  @override
  String get jsonSave => 'Salvar';

  @override
  String get srvTileEdit => 'Editar';

  @override
  String get srvTileNotice => 'Aviso';

  @override
  String get srvTileRefresh => 'Atualizar';

  @override
  String get srvTileSubscriptionUpdated => 'Assinatura atualizada';

  @override
  String get srvTileCopy => 'Copiar';

  @override
  String get srvTileInfo => 'Informações do servidor';

  @override
  String get srvTilePing => 'Ping';

  @override
  String get srvTileUnpin => 'Desafixar';

  @override
  String get srvTilePin => 'Fixar';

  @override
  String get srvTileJsonConfig => 'Configuração JSON';

  @override
  String get srvTileSmart => 'Ajuste inteligente de parâmetros';

  @override
  String get srvTileDelete => 'Excluir';

  @override
  String get srvTileServerDeleted => 'Servidor excluído';

  @override
  String get srvTileSaved => 'Salvo';

  @override
  String get pingNa => 'n/d';

  @override
  String get pingNaTooltip =>
      'Sem resposta TCP — servidor indisponível (morto)';

  @override
  String get pingTimeout => 'tempo esgotado';

  @override
  String get pingTimeoutTooltip =>
      'A sonda TCP não foi concluída dentro do tempo limite — servidor indisponível';

  @override
  String pingMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get pingNoProxy => 'sem proxy';

  @override
  String get pingNoProxyTooltip =>
      'Responde por TCP (latência mostrada), mas a verificação do túnel (GET/HEAD) falhou — o tráfego não está passando';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip =>
      'Latência TCP até o servidor. O servidor está funcionando: respondeu por TCP e passou na verificação do túnel (GET/HEAD)';

  @override
  String get searchHint => 'Buscar por nome, país, endereço…';

  @override
  String get searchReset => 'Limpar';

  @override
  String get splitTitle => 'Túnel dividido';

  @override
  String get splitTunOnlyBanner =>
      'Funciona apenas no modo TUN. No modo \"Proxy do sistema\", os aplicativos decidem por si mesmos se usam o proxy — não é possível forçá-los.';

  @override
  String get splitEnableTun => 'Ativar TUN';

  @override
  String get splitModeHeader => 'Modo';

  @override
  String get splitAppsHeader => 'Aplicativos';

  @override
  String get splitAppsHint =>
      'Toque em um aplicativo para definir sua ação (Túnel / Direto / Bloquear) e o método de correspondência. A caixa de seleção à esquerda ativa/desativa a regra.';

  @override
  String get splitByName => 'Por nome';

  @override
  String get splitByPath => 'Por caminho';

  @override
  String get splitRuleDisabled => 'Desativada — a regra não é aplicada';

  @override
  String get splitRemove => 'Remover';

  @override
  String get splitFromRunning => 'Dos em execução';

  @override
  String get splitPickInstalled => 'Escolher aplicativo';

  @override
  String get splitInstalledApps => 'Aplicativos instalados';

  @override
  String get splitPickExe => 'Escolher .exe';

  @override
  String get splitSitesHeader => 'Sites (domínios)';

  @override
  String get splitSitesHint =>
      'Toque em um site para escolher uma ação (Túnel / Direto / Bloquear). Um domínio também cobre seus subdomínios; os subdomínios são agrupados em uma árvore. Você pode especificar uma porta.';

  @override
  String splitOnlyPort(Object port) {
    return 'somente porta $port';
  }

  @override
  String get splitProgramsFileType => 'Programas';

  @override
  String get splitRunningApps => 'Aplicativos em execução';

  @override
  String get splitSearchByName => 'Buscar por nome';

  @override
  String get splitNothingFound => 'Nada encontrado';

  @override
  String get splitClose => 'Fechar';

  @override
  String get splitPortRange => 'Porta 1–65535';

  @override
  String get splitAction => 'Ação';

  @override
  String get splitPortOptional => 'Porta (opcional)';

  @override
  String get splitAnyPort => 'qualquer';

  @override
  String get splitPortHelper =>
      'Vazio = qualquer porta. Caso contrário, a regra se aplica apenas a esta porta';

  @override
  String get splitMatching => 'Correspondência';

  @override
  String get splitByNameSubtitle =>
      'Nome do exe, independentemente da localização (confiável)';

  @override
  String get splitByPathSubtitle =>
      'Caminho completo do exe (correspondência exata)';

  @override
  String get splitDone => 'Concluído';

  @override
  String get splitEnterDomain => 'Digite um domínio';

  @override
  String get splitAddSite => 'Adicionar site';

  @override
  String get splitPort => 'Porta';

  @override
  String get splitAdd => 'Adicionar';

  @override
  String get routeBlock => 'Bloquear';

  @override
  String get routeBlocked => 'Bloqueado';

  @override
  String get routeYourPc => 'Seu PC';

  @override
  String get routeTunnel => 'Túnel';

  @override
  String get routeViaVpn => 'Via VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'Internet';

  @override
  String get routeRest => 'Todo o resto';

  @override
  String get routeDirectly => 'Diretamente';

  @override
  String get routeDirectPlusRest => 'Direto + resto';

  @override
  String get routeDirect => 'Direto';

  @override
  String get routeEmptyList => 'a lista está vazia';

  @override
  String get trayShow => 'Mostrar';

  @override
  String get trayToggle => 'Conectar / Desconectar';

  @override
  String get trayQuit => 'Sair';

  @override
  String get trayMinimizeTitle => 'Minimizar para a bandeja';

  @override
  String get trayMinimizeBody =>
      'O aplicativo continuará em execução na bandeja.';

  @override
  String get trayDontAsk => 'Não perguntar novamente';

  @override
  String get trayMinimizeOk => 'Minimizar';

  @override
  String get trayVpnTitle => 'VPN conectada';

  @override
  String get trayVpnBody => 'Desconectar a VPN e sair do aplicativo?';

  @override
  String get trayStay => 'Permanecer';

  @override
  String get trayQuitVpn => 'Desconectar e sair';

  @override
  String get tunTaskDone =>
      'Concluído: o TUN iniciará sem uma solicitação de UAC';

  @override
  String get tunTaskFailed =>
      'Falha ao criar a tarefa (UAC recusado ou bloqueado por política)';

  @override
  String get tunLogTitle => 'Registro do TUN (sing-box)';

  @override
  String get tunLogEmpty =>
      'O registro está vazio — o túnel ainda não foi iniciado.';

  @override
  String get tunCopy => 'Copiar';

  @override
  String get tunClose => 'Fechar';

  @override
  String get tunTitle => 'TUN e roteamento';

  @override
  String get tunSectionPrivilege => 'Direitos de administrador';

  @override
  String get tunChecking => 'Verificando…';

  @override
  String get tunNoUacConfigured => 'Início sem UAC está configurado';

  @override
  String get tunUacEachConnect => 'O UAC será solicitado a cada conexão';

  @override
  String get tunTaskSubtitle =>
      'Uma tarefa do Agendador de Tarefas do Windows com os privilégios mais altos (criada uma vez).';

  @override
  String get tunRecreateTask => 'Recriar tarefa';

  @override
  String get tunSetupOneUac => 'Configurar (um UAC)';

  @override
  String get tunRemoveTask => 'Remover tarefa';

  @override
  String get tunSectionAdapter => 'Adaptador';

  @override
  String get tunStack => 'Pilha TUN';

  @override
  String get tunSectionRouting => 'Roteamento';

  @override
  String get tunStrictRoute => 'Roteamento estrito (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 no túnel';

  @override
  String get tunEndpointNat => 'NAT independente de endpoint (UDP, jogos)';

  @override
  String get tunLanBypass => 'A rede local contorna a VPN';

  @override
  String get tunDnsServer => 'Servidor DNS';

  @override
  String get tunDnsHijack => 'Interceptar DNS (porta 53)';

  @override
  String get tunResolveStrategy => 'Estratégia de resolução';

  @override
  String get tunSectionDiagnostics => 'Diagnóstico';

  @override
  String get tunSingboxLogLevel => 'Nível de registro do sing-box';

  @override
  String get tunShowLog => 'Mostrar registro do TUN';

  @override
  String get tunDnsVpn => 'Via VPN (recomendado)';

  @override
  String get tunDnsSystem => 'Sistema';

  @override
  String get tunDnsCustom => 'Servidor personalizado';

  @override
  String get tunDnsVpnHint =>
      'As solicitações entram no túnel por TCP — sem vazamentos';

  @override
  String get tunDnsSystemHint => 'Igual ao Windows: vazamento de DNS possível';

  @override
  String get tunDnsCustomHint => 'O servidor especificado, também pelo túnel';

  @override
  String get tunExcludeSubnets => 'Sub-redes que contornam a VPN';

  @override
  String get tunAdd => 'Adicionar';

  @override
  String get urlGroupImport => 'Importar';

  @override
  String get urlGroupControl => 'Controle';

  @override
  String get urlHintSubUrl => 'URL da assinatura';

  @override
  String get urlHintServerLink => 'link do servidor';

  @override
  String get urlDescImportSub => 'Importar uma assinatura';

  @override
  String get urlDescImportServer =>
      'Adicionar um único servidor (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'Conectar a VPN';

  @override
  String get urlDescDisconnect => 'Desconectar a VPN';

  @override
  String get urlDescToggle => 'Alternar a VPN';

  @override
  String get urlDescUpdate => 'Atualizar a assinatura ativa';

  @override
  String get urlSupportedImport =>
      'Na importação, o aplicativo entende: uma URL de assinatura (http/https) e servidores individuais vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — relatório de suporte';

  @override
  String get reportDescribeHere =>
      '>>> DESCREVA O PROBLEMA AQUI (preencha e salve o arquivo): <<<';

  @override
  String get reportWhatDid => 'O que você fez:';

  @override
  String get reportWhatExpected => 'O que você esperava:';

  @override
  String get reportWhatHappened => 'O que aconteceu:';

  @override
  String get reportWhenStarted => 'Quando começou:';

  @override
  String get reportTechNoticeLine1 =>
      'Abaixo estão as informações técnicas. Revise-as antes de enviar;';

  @override
  String get reportTechNoticeLine2 =>
      'não há senhas ou token de assinatura aqui, e a URL da assinatura está oculta.';

  @override
  String get noRealIpTitle => 'Nunca usar meu IP real';

  @override
  String get noRealIpSub =>
      'Mesmo com a VPN ativa, todo o tráfego «direto» passa pela VPN (sites RU também). A rede local continua direta.';

  @override
  String get flagAuto => 'AUTO';

  @override
  String get autoUpdateIntervalLabel => 'Intervalo de atualização, h';

  @override
  String get autoUpdatePreferSub => 'Usar o intervalo da assinatura';

  @override
  String get pingLegendInfo =>
      'Cor da etiqueta de ping: verde/amarelo/laranja — o servidor funciona (TCP + verificação pelo túnel). Cinza — responde por TCP mas não encaminha o tráfego (porta Reality típica). Vermelho «n/a» — sem resposta, excluído. O ping é sempre medido DIRETAMENTE (fora da VPN).';

  @override
  String get panelTunnelMarker => 'Tem seu próprio túnel dividido';

  @override
  String panelInfoServers(Object n) {
    return 'Servidores no perfil: $n (o melhor é escolhido)';
  }

  @override
  String get panelInfoDirect =>
      'Parte do tráfego (ex. sites locais) vai direto, fora da VPN';

  @override
  String get panelInfoBlock =>
      'Parte do tráfego é bloqueada (anúncios/torrents)';

  @override
  String get serviceChecksTitle => 'Verificar serviços';

  @override
  String get serviceChecksInfo =>
      'Toque num serviço para verificar se ele abre pela conexão VPN ativa. A verificação é manual — nada é verificado automaticamente. Para serviços de IA, também é detectado o bloqueio por país de saída.';

  @override
  String get serviceStatusOk => 'Funciona';

  @override
  String get serviceStatusGeo => 'Abre, mas bloqueado no país de saída';

  @override
  String get serviceStatusFail => 'Não abre';

  @override
  String get serviceStatusChecking => 'Verificando…';

  @override
  String get serviceStatusTap => 'Toque para verificar';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get homeTunAutotuneProgress => 'Ajustando parâmetros do TUN…';

  @override
  String get homeTunAutotuneDone => 'Parâmetros do TUN ajustados';

  @override
  String get homeTunAutotuneFailed =>
      'Não foi possível ajustar os parâmetros do TUN';

  @override
  String get hy2NoteTitle => 'Servidores Hysteria2';

  @override
  String get hy2NoteBody =>
      'Os servidores Hysteria2 chegam apenas no formato XRAY_JSON — o SilentGate solicita exatamente esse, e o sing-box os inicia automaticamente. Se o Hysteria2 não aparecer na lista: (para o dono do painel Remnawave) ative os inbounds de hysteria e atribua-os à assinatura. Observação: o Remnawave antes de 2.8.0 entrega Hysteria2 SÓ em XRAY_JSON — não está em base64/CLASH/SINGBOX, por isso a regra Response Rules → XRAY_JSON acima é obrigatória.';

  @override
  String get enumStatusDisconnected => 'Desconectado';

  @override
  String get enumStatusConnecting => 'Conectando…';

  @override
  String get enumStatusConnected => 'Conectado';

  @override
  String get enumStatusDisconnecting => 'Desconectando…';

  @override
  String get enumStatusError => 'Erro';

  @override
  String get enumVariantPlain => 'padrão';

  @override
  String get tagAutoSelect => 'AUTO';

  @override
  String get tagPanel => 'PAINEL';

  @override
  String get tagPortHopping => 'SALTO DE PORTAS';

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
  String get syncNoChanges => 'sem alterações';

  @override
  String get errInvalidJson => 'JSON inválido';

  @override
  String get errPickServerFirst => 'Selecione um servidor primeiro';

  @override
  String get errImportSubscriptionFirst => 'Importe uma assinatura primeiro';

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
    return 'A porta $port já está ocupada por $by.';
  }

  @override
  String get srvTileMenu => 'Ações do servidor';

  @override
  String get supportCopyReport => 'Copiar relatório';

  @override
  String get supportReportCopied =>
      'Relatório copiado — cole-o no chat de suporte';

  @override
  String subBarUsedOnly(String used) {
    return 'Usado $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'tráfego ilimitado';

  @override
  String get supportDescribeLabel => 'Descreva o problema';

  @override
  String get supportDescribeHint =>
      'O que fez, o que esperava, o que aconteceu e quando começou';

  @override
  String get supportDescribeRequired =>
      'Descreva o problema — sem descrição o relatório é inútil';

  @override
  String get supportNoScreenshots =>
      'Não cole capturas de tela aqui — envie-as em mensagem separada no chat do Telegram.';

  @override
  String get supportDescriptionSection => 'DESCRIÇÃO DO USUÁRIO';

  @override
  String get splitAllowRealIp => 'Permitir IP real';

  @override
  String get splitAllowRealIpOn =>
      'Esta regra ignora a VPN — o site verá o seu endereço real';

  @override
  String get splitAllowRealIpOff =>
      'Esta regra está protegida — passa pela VPN';

  @override
  String get splitRealIpExposed => 'IP real';

  @override
  String get splitRealIpProtected => 'via VPN';

  @override
  String get vpnActiveBadge => 'VPN ativa';

  @override
  String get splitCopyDomain => 'Copiar endereço';

  @override
  String get splitCopyPath => 'Copiar caminho';
}
