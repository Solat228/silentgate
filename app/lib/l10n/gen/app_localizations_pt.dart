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
  String get commonClear => 'Limpar';

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
  String get settingsSearchHint => 'Pesquisar nas configurações';

  @override
  String settingsSearchEmpty(String query) {
    return 'Nada encontrado: «$query»';
  }

  @override
  String get settingsExpand => 'Expandir';

  @override
  String get settingsCollapse => 'Recolher';

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
  String get captureProxyOnly => 'Somente proxy';

  @override
  String get captureProxyOnlySub =>
      'O núcleo está ativo e as portas locais estão escutando, mas o computador não está no túnel: pela VPN passa só quem apontar explicitamente para o nosso proxy';

  @override
  String get apiSectionTitle => 'API para automação';

  @override
  String get apiEnableTitle => 'Ativar API local';

  @override
  String apiEnableSub(int port) {
    return 'HTTP em 127.0.0.1:$port — controlar o cliente a partir de scripts';
  }

  @override
  String get apiTokenTitle => 'Token';

  @override
  String get apiTokenUnset => 'Não definido — a API não inicia';

  @override
  String get apiTokenRegenerate => 'Renovar token';

  @override
  String get apiTokenWarning =>
      'O token fica no arquivo de configurações em texto puro. Ele não chega ao registro nem ao relatório de suporte, mas quem o tiver pode trocar de servidor e ler o estado da sua assinatura.';

  @override
  String get apiExitsTitle => 'Servidores com porta dedicada';

  @override
  String get apiExitsSub =>
      'Cada um recebe sua própria porta local — uma solicitação a ela passa por esse servidor';

  @override
  String get apiCopyPythonExample => 'Copiar exemplo para Python';

  @override
  String apiPortsHint(int control, int direct, int first) {
    return 'Controle — porta $control. «Direto» — porta $direct. Servidores — a partir de $first.';
  }

  @override
  String get apiRulesInProxyOnly => 'Aplicar regras de túnel dividido';

  @override
  String get apiRulesInProxyOnlySub =>
      'Nesse modo as regras padrão não se aplicam a nenhum programa. Ative se quiser que a lista «Bloquear» também valha para solicitações feitas pelas portas locais.';

  @override
  String apiCaptureModeWarning(int control) {
    return '⚠️ A captura está em «Proxy do sistema»: nesse modo as portas de saída não são abertas e as ligações a elas são recusadas. A porta de controlo $control funciona com qualquer captura. Se precisar das portas de saída, escolha «TUN (túnel completo)» ou «Somente proxy».';
  }

  @override
  String get apiPortBusyTitle => 'A API não arrancou';

  @override
  String apiPortBusy(int port, String holder) {
    return 'A porta $port está ocupada por $holder. Feche esse programa por completo, incluindo a área de notificação, e volte a ligar o interruptor.';
  }

  @override
  String apiPortBusyUnknown(int port) {
    return 'A porta $port está ocupada por outro programa que não foi possível identificar. Normalmente é outro cliente VPN. Feche-o e volte a ligar o interruptor.';
  }

  @override
  String get apiRulesInProxyOnlyEdit =>
      'A lista «Bloquear» edita-se no ecrã de túnel dividido';

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
  String get subSwitcherPingAll =>
      'Testar os servidores de todas as assinaturas';

  @override
  String get subSwitcherPingBusySpeed =>
      'Ping indisponível: há um teste de velocidade em andamento';

  @override
  String get subSwitcherExpired => 'Expirada';

  @override
  String subSwitcherExpiredOn(String date) {
    return 'A assinatura expirou em $date';
  }

  @override
  String subSwitcherCountTotal(int total) {
    return 'Servidores na assinatura: $total. O canal ainda não foi verificado — execute «Testar os servidores de todas as assinaturas».';
  }

  @override
  String subSwitcherCountWorking(int total, int working) {
    return 'Servidores na assinatura: $total. Destes, passaram na verificação do canal (requisição pelo servidor): $working.';
  }

  @override
  String subSwitcherCountChecking(int total) {
    return 'Servidores na assinatura: $total. A verificação está em andamento — o número dos que funcionam aparecerá quando ela terminar.';
  }

  @override
  String subSwitcherCountPartial(int total, int working) {
    return 'Servidores na assinatura: $total. A execução não foi concluída (cancelada ou interrompida), por isso o número está incompleto: $working passaram na verificação do canal entre aqueles que foi possível alcançar.';
  }

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
      'Se o núcleo caiu, o servidor desapareceu ou a rede mudou (Wi-Fi ↔ cabo, saída da suspensão, novo IP), o aplicativo restabelece a conexão sozinho. As pausas entre as tentativas aumentam: 0,8 s → 3 s → 8 s → 20 s e daí em diante ficam em 20 s. São oito tentativas, após as quais o aplicativo desiste e mostra um erro. Desconectar pelo botão sempre cancela a recuperação.\n\n⚠️ Com o kill switch ligado, as tentativas NÃO ACABAM. Enquanto continuam, o tráfego permanece bloqueado, e interrompê-las significaria deixá-lo sair por fora da VPN — por isso o aplicativo continua tentando a cada 20 segundos até que você mesmo desligue a VPN, e lembra da falha no máximo uma vez a cada 15 minutos. Um servidor que volta uma hora depois é retomado sozinho.\n\nNo modo «Auto (melhor servidor)», o aplicativo não gasta a última tentativa em um servidor morto: já na sétima de oito ele passa para o próximo candidato, e ali a contagem recomeça.\n\nA mudança de rede é detectada pelos endereços reais dos outros adaptadores: o próprio túnel e os endereços de serviço (link-local) não contam, uma mudança só é aceita se resistir a duas sondagens seguidas, e o sinal é ignorado nos primeiros 15 segundos após a conexão. Sem essas salvaguardas, levantar o túnel contaria a si mesmo como «mudança de rede» e causaria reconexão infinita.';

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
  String get tunLogLevelDebugCost =>
      'No nível debug o núcleo escreve centenas de linhas por segundo: o registo abrange minutos, não horas, e cresce em megabytes. É inútil para uma queda anterior — consulte o registo da aplicação.';

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
  String get splitProxyOnlyBanner =>
      'No modo «Somente proxy» não há nada a intercetar: as regras não se aplicam a nenhum programa do computador. A lista «Bloquear» aplica-se apenas às portas locais da API e só se estiver ligado «Aplicar regras de túnel dividido» na secção «Captura de tráfego». As restantes regras podem ser preparadas aqui: passam a funcionar quando mudar para TUN.';

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
  String get pingUntestedHint =>
      'Ainda não testado. No celular, Hysteria2 e perfis “Auto” são medidos apenas com a conexão ativa.';

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
      'Seis serviços populares são verificados sozinhos: primeiro ao abrir o aplicativo com a VPN desligada e de novo logo após conectar. Os dois pontos mostram «antes → depois», para ver o que a VPN realmente mudou. Toque para verificar de novo. Verde: abre; laranja: bloqueio por região; vermelho: inacessível.';

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
  String get splitAllowRealIp => 'Permitir IP real para esta regra';

  @override
  String get splitAllowRealIpOn =>
      'Ligada: é uma exceção, o tráfego sairá com seu endereço real';

  @override
  String get splitAllowRealIpOff =>
      'Desligada: a regra vai pela VPN — a proteção está acima de todas as regras';

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

  @override
  String get homeServerInfo => 'Info do servidor';

  @override
  String get serverInfoVerifyInBrowser => 'Verificar no navegador';

  @override
  String get tunDnsForAll => 'DNS de todos os apps pela VPN';

  @override
  String get infoDnsForAll =>
      'Apenas no modo “Somente selecionados”. ⚠️ Aplica-se após reconectar.';

  @override
  String get homeSettingsNeedReconnect =>
      'Configuração alterada — reconecte para aplicar';

  @override
  String blockPageWindowTitle(String app) {
    return 'Bloqueado — $app';
  }

  @override
  String get blockPageHeading => 'Site bloqueado';

  @override
  String blockPageBody(String host, String app) {
    return '$host está bloqueado por uma regra de túnel dividido no $app.';
  }

  @override
  String get blockPageHint =>
      'Você pode alterar a regra: Configurações → Túnel dividido → Sites.';

  @override
  String get blockPageNote =>
      'Esta página vem do próprio aplicativo, não é um erro de rede. O site não abre porque você mesmo o adicionou à lista de bloqueio.';

  @override
  String get settingsBlockPage => 'Página de aviso de bloqueio';

  @override
  String get settingsBlockPageSub =>
      'Em vez de um erro de conexão, uma página explica qual regra fechou o site. Funciona apenas com http: uma página https não pode ser substituída sem instalar nosso próprio certificado raiz no sistema, e esse certificado permitiria ler todo o seu tráfego criptografado.';

  @override
  String get trayCloseFully => 'Fechar completamente';

  @override
  String errorVpnConflictApp(String app) {
    return 'Parece que $app está atrapalhando: ele tem o próprio túnel VPN ativo. Dois túneis ao mesmo tempo disputam a rota padrão.';
  }

  @override
  String errorCloseApp(String app) {
    return 'Fechar $app';
  }

  @override
  String toastAppClosed(String app) {
    return '$app fechado';
  }

  @override
  String toastAppCloseFailed(String app) {
    return 'Não foi possível fechar $app — feche manualmente';
  }

  @override
  String get tunBlockQuic => 'Bloquear QUIC (HTTP/3)';

  @override
  String get infoBlockQuic =>
      'As regras de sites usam o NOME, e o aplicativo só vê o nome no TLS comum. Um navegador que passa para HTTP/3 não mostra o nome, então a regra de domínio simplesmente não age. O bloqueio devolve o navegador a uma conexão normal, onde o nome fica visível. Os sites continuam funcionando: HTTP/3 é opcional, embora o vídeo possa carregar um pouco mais devagar.';

  @override
  String get tunBlockEncryptedDns => 'Bloquear DNS criptografado (DoH/DoT)';

  @override
  String get infoBlockEncryptedDns =>
      'Navegadores e Windows podem resolver endereços por HTTPS, contornando nossa interceptação. Assim, as regras «Direto» e «Bloquear» não funcionam no nível de DNS. ⚠️ Se o navegador tiver um provedor de DNS criptografado fixo, ele não voltará ao DNS comum: apenas deixará de abrir sites. A lista de provedores conhecidos é incompleta por natureza.';

  @override
  String get autoUseSpeed => 'Considerar a velocidade';

  @override
  String get infoAutoUseSpeed =>
      'Após a triagem por serviços e latência, os três melhores candidatos são testados por download e o realmente mais rápido fica em primeiro. A velocidade é comparada com o SEU canal: um servidor que já entrega quase tudo deixa de ser julgado por megabits e a latência decide. ⚠️ Consome tráfego da assinatura: 5 MB para o seu canal mais 5 MB por candidato, cerca de 20 MB por execução.';

  @override
  String get autoSpeedOwn => 'Medindo a sua própria velocidade…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'Medindo velocidade: $server ($index de $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent% do seu canal';
  }

  @override
  String get conflictDialogTitle => 'Outro VPN detectado';

  @override
  String conflictDialogBody(String app) {
    return 'Parece que $app está em execução com o próprio túnel ativo. Dois túneis ao mesmo tempo disputam a rota padrão, então a conexão pode falhar ou subir sem acesso à rede.';
  }

  @override
  String get conflictCloseAndConnect => 'Fechar e conectar';

  @override
  String get conflictConnectAnyway => 'Conectar mesmo assim';

  @override
  String get serviceChecksLegendBefore => 'Disponibilidade verificada sem VPN';

  @override
  String get serviceChecksLegendAfter =>
      'À esquerda — sem VPN, à direita — pela VPN';

  @override
  String get serviceChecksBefore => 'Sem VPN';

  @override
  String get serviceChecksAfter => 'Pela VPN';

  @override
  String get serviceChecksNoBaseline => 'Não verificado sem VPN';

  @override
  String autoSpeedValue(String value) {
    return '$value MB/s';
  }

  @override
  String get splitShowBlockPage => 'Mostrar a página de bloqueio';

  @override
  String get splitBlockPageNeedsVpn =>
      'A página de bloqueio só funciona com a VPN ativa';

  @override
  String get srvInfoNeedsConnection =>
      'Nesta plataforma, a medição pelo servidor exige a VPN ligada';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ Esta verificação não detecta a limitação do YouTube: o provedor responde normalmente, mas reduz a velocidade do vídeo. Verde significa «serviço acessível», não «o vídeo reproduz».';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<nome do servidor>';

  @override
  String get urlDescConnectServer =>
      'Conectar a um servidor ESPECÍFICO. O nome é o que aparece na lista e vem da assinatura, por ex. «Polônia 1.5». Emoji de bandeira e maiúsculas podem ser omitidos. Sem correspondência exata, entra a busca: por país, endereço ou protocolo. Vale também para toggle.';

  @override
  String get splitSelectAllFound => 'Marcar tudo encontrado';

  @override
  String splitAddSelected(int count) {
    return 'Adicionar ($count)';
  }

  @override
  String get splitQuicNote =>
      'Enquanto houver ao menos uma regra de site, o aplicativo desativa HTTP/3 (QUIC) para todo o tráfego. Caso contrário, o navegador passa a HTTP/3, não deixa o nome do site e a regra falha em silêncio. Os sites continuam funcionando: voltam ao TLS comum, apenas um pouco mais lentos.';

  @override
  String get splitNoRealIpBanner =>
      '«Nunca usar meu IP real» está ligado: regras «Direto» sem a caixa marcada vão pela VPN';

  @override
  String get settingsNoRealIpAffects =>
      'Afeta as regras «Direto»: sem a caixa «permitir IP real» elas vão pela VPN';

  @override
  String get splitAppOverrideSites => 'Tem prioridade sobre regras de sites';

  @override
  String get splitAppOverrideSitesSub =>
      'Todo o tráfego do aplicativo segue esta regra mesmo se um site disser o contrário';

  @override
  String get settingsMyRulesOverridePanel =>
      'Minhas regras têm prioridade sobre as do painel';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'O painel traz o próprio roteamento, normalmente «sites locais fora da VPN». Ele se aplica depois das suas regras, então um site marcado «Túnel» pode sair direto com seu IP real. Ligado: túnel significa túnel. Custo: sites locais dão a volta e ficam mais lentos.';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get tunRouteOnlySubnets => 'No túnel APENAS estas sub-redes';

  @override
  String get infoTunRouteOnlyCidrs =>
      'A única forma, no Windows, de tornar parte do tráfego realmente independente do cliente VPN.\n\nNormalmente o túnel assume a rota padrão, e TODO o tráfego da máquina entra nele: a marcação «Direto» é resolvida já dentro do núcleo, que recebe o pacote e o reenvia para fora em seu próprio nome. Esse tráfego vive exatamente enquanto o núcleo viver, e trava junto com ele.\n\nSe a lista não estiver vazia, a rota padrão não é entregue ao túnel: ele assume apenas as sub-redes listadas, e todo o resto o sistema envia pelo adaptador comum — o cliente não chega a ver esse tráfego.\n\nO preço: a divisão é feita por endereço, enquanto as regras de aplicativos e de sites casam por nome. Um site cujo endereço não esteja na lista fica invisível para qualquer regra. Deixe vazio para que o túnel funcione como de costume.';

  @override
  String get tunRouteOnlyWarning =>
      'O túnel assume apenas as sub-redes listadas. As regras de aplicativos e de sites valem SOMENTE dentro delas: o que não entra no túnel nunca chega ao núcleo — não dá para bloquear nem redirecionar esse site.';

  @override
  String get tunAlsoSystemProxy => 'Proxy do sistema junto com o túnel';

  @override
  String get infoTunAlsoSystemProxy =>
      'Modo misto: o túnel e o proxy do sistema funcionam ao mesmo tempo.\n\nOs aplicativos que respeitam o proxy do sistema (navegadores, Telegram) seguem o caminho curto direto para a porta local, sem passar pela pilha em espaço de usuário do túnel, e entregam ao núcleo o nome do domínio em vez de um endereço puro — as regras de sites ficam mais precisas para eles e deixam de depender da análise do TLS.\n\nIsso NÃO os torna independentes do cliente: eles continuam passando pelo mesmo processo.';

  @override
  String get tunMixedModeWarning =>
      'Uma conexão que chega pelo proxy do sistema não tem processo dono — para o núcleo, é uma conexão local. Por isso as regras de APLICATIVOS não valem para esses programas. As regras de sites funcionam, e até com mais precisão que o normal.';

  @override
  String get tunWatchdog => 'Vigia de núcleo travado';

  @override
  String get infoTunWatchdog =>
      'Por quantos segundos o núcleo do túnel pode ficar sem responder antes de ser considerado travado e o túnel ser derrubado.\n\nSe o núcleo cai, o Windows limpa tudo sozinho — o adaptador, as rotas e as regras de firewall são removidos e a rede volta. Se o núcleo trava, nada é removido: o adaptador permanece e engole todo o tráfego da máquina, inclusive o marcado como «Direto». De fora, isso é «a internet sumiu por completo», e não se resolve sozinho.\n\nO vigia só é armado após a primeira resposta bem-sucedida do núcleo: caso contrário, ele derrubaria a conexão sempre que a porta de serviço não conseguisse subir. 0 — não vigiar. Mínimo de 10 segundos.';

  @override
  String get tunWatchdogOff =>
      'Desativado: um travamento do túnel não será detectado';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'Derrubar o túnel se o núcleo não responder por mais de $seconds s';
  }

  @override
  String get tunDnsForAllWarning =>
      'A resolução de nomes da máquina INTEIRA passará pelo túnel. Se o túnel travar, os nomes deixarão de ser resolvidos até para os aplicativos que vão direto e não precisam da VPN — de fora, isso parece uma perda total de internet.';

  @override
  String get tunCidrInvalid =>
      'É necessário um endereço com prefixo, por exemplo 10.8.0.0/24';

  @override
  String get geoTitle => 'Bases geo de roteamento';

  @override
  String get geoSubShort =>
      'Listas de países e categorias para as regras da assinatura';

  @override
  String get geoMissing =>
      'Não baixadas — as regras por país e categoria não funcionam';

  @override
  String geoPresent(String size, String date) {
    return '$size, atualizadas em $date';
  }

  @override
  String get geoDownload => 'Baixar';

  @override
  String get geoUpdate => 'Atualizar';

  @override
  String geoDownloading(String file) {
    return 'Baixando $file…';
  }

  @override
  String get geoDone => 'Bases geo atualizadas';

  @override
  String get geoWhy =>
      'Os arquivos geoip.dat e geosite.dat são listas de endereços por país e de domínios por categoria. Por eles o núcleo interpreta regras como geoip:ru e geosite:category-ads, definidas pelo painel da assinatura. Sem os arquivos, essas regras são removidas da configuração.';

  @override
  String geoFileOk(String size, String date) {
    return '$size, atualizado em $date';
  }

  @override
  String get geoFileMissing => 'arquivo ausente';

  @override
  String get geoFileCorrupt => 'arquivo danificado — o núcleo não vai lê-lo';

  @override
  String geoFolder(String path) {
    return 'Pasta: $path';
  }

  @override
  String get geoBundledWindows =>
      'No Windows os arquivos vêm junto com o núcleo e normalmente já estão no lugar. A atualização aqui os baixa de novo quando as listas ficam desatualizadas.';

  @override
  String get geoSource =>
      'A fonte é a mesma de onde os arquivos vêm na distribuição do Xray: Loyalsoldier/v2ray-rules-dat. O que é baixado é conferido com a soma de verificação publicada no mesmo lançamento.';

  @override
  String get geoReplaceWarning =>
      'Os arquivos anteriores são guardados: se o roteamento piorar depois da substituição, basta um botão para trazê-los de volta. A atualização não é instalada quando o arquivo novo não tem as categorias a que a sua assinatura se refere.';

  @override
  String geoBackupLine(String files, String size, String date) {
    return 'Há cópia de segurança: $files — $size, de $date';
  }

  @override
  String get geoRestore => 'Restaurar anteriores';

  @override
  String get geoRestored => 'Bases geo anteriores restauradas';

  @override
  String get geoRestoreTitle => 'Restaurar as bases geo anteriores?';

  @override
  String get geoRestoreBody =>
      'Os arquivos atuais serão substituídos pela cópia guardada antes da última atualização. Não é preciso internet. Depois disso, os atualizados só voltam baixando de novo.';

  @override
  String get geoErrorCategories =>
      'O arquivo novo não tem as categorias a que a sua assinatura se refere. A substituição foi cancelada e os arquivos anteriores continuam no lugar — o roteamento não foi afetado. A linha abaixo mostra quais categorias faltaram.';

  @override
  String get geoNoWrite =>
      'Não é possível gravar nesta pasta — baixar aqui não vai funcionar. Normalmente isso acontece com a instalação em Program Files: execute o aplicativo como administrador.';

  @override
  String get geoCheck => 'Verificar atualização';

  @override
  String get geoCheckAgain => 'Verificar novamente';

  @override
  String get geoChecking => 'Consultando o lançamento…';

  @override
  String geoLastCheck(String when) {
    return 'Última verificação: $when';
  }

  @override
  String get geoNeverChecked =>
      'A atualização ainda não foi verificada nenhuma vez';

  @override
  String geoUpdateAvailable(String files, String size) {
    return 'Há atualização: $files — $size';
  }

  @override
  String get geoSizeUnknown => 'o servidor não informou o tamanho';

  @override
  String get geoUpToDate =>
      'Não é necessário atualizar: os arquivos coincidem com o último lançamento.';

  @override
  String get geoPlanTitle => 'Baixar as bases geo?';

  @override
  String get geoPlanTitleUpdate => 'Atualizar as bases geo?';

  @override
  String geoPlanFiles(String files) {
    return 'Arquivos: $files';
  }

  @override
  String geoPlanSize(String size) {
    return 'Tamanho: $size';
  }

  @override
  String get geoPlanTraffic =>
      'Os arquivos vão pela sua conexão. Em um plano de dados móveis isso é um tráfego considerável.';

  @override
  String geoProgressBytes(String done, String total) {
    return '$done de $total';
  }

  @override
  String get geoErrorNetwork =>
      'Não foi possível contatar o servidor de atualização. Verifique a internet e tente novamente.';

  @override
  String get geoErrorServer =>
      'O servidor de atualização recusou o pedido. Provavelmente é temporário — tente mais tarde.';

  @override
  String get geoErrorWrite =>
      'Não foi possível gravar o arquivo: sem permissão na pasta ou sem espaço suficiente.';

  @override
  String get geoErrorCorrupt =>
      'O arquivo baixado não passou na verificação — o download foi danificado. Tente novamente.';

  @override
  String get geoErrorOther => 'Não deu certo. Os detalhes estão abaixo.';

  @override
  String geoFailed(String error) {
    return 'Não foi possível baixar: $error';
  }

  @override
  String get infoGeoAssets =>
      'Os arquivos geoip.dat e geosite.dat são listas de endereços por país e de domínios por categoria (por exemplo «sites russos», «serviços públicos», «VK»). As regras de roteamento definidas pelo painel da assinatura dependem deles.\n\nEles não vêm embutidos no aplicativo: juntos pesam cerca de 30 MB e não são necessários para todos — um servidor comum não precisa deles.\n\nEnquanto os arquivos não estiverem baixados, essas regras são removidas da configuração, e o tráfego que elas enviavam direto passa a ir pela VPN. Isso é seguro, mas mais lento, e sites locais podem negar o acesso por causa do endereço estrangeiro. As regras que você mesmo define para sites e aplicativos funcionam de qualquer forma — elas não dependem desses arquivos.';

  @override
  String get supportBullet2Android =>
      '• Após tocar, o relatório será reunido em um único arquivo e abrirá a janela do sistema “Compartilhar” — escolha o Telegram e ele será enviado como um único anexo. Descreva o problema no campo acima: sem descrição não há o que analisar.';

  @override
  String get supportDoneTextAndroid =>
      'O relatório foi reunido em um único arquivo. Escolha na janela do sistema para onde enviá-lo — no Telegram ele será enviado como anexo, e não como texto.';

  @override
  String get exitsHeader => 'Saídas';

  @override
  String get exitsHint =>
      'Uma regra «Túnel» pode ser direcionada a uma saída específica: um site pela Alemanha, outro pelos EUA. Sem saída, a regra usa o túnel principal, como antes.';

  @override
  String get exitsAdd => 'Adicionar saída';

  @override
  String get exitsEmpty => 'Ainda não há saídas';

  @override
  String get exitsName => 'Nome';

  @override
  String get exitsNameHint => 'Alemanha';

  @override
  String get exitsServers => 'Servidores';

  @override
  String get exitsAutoSelect => 'Seleção automática por latência';

  @override
  String get exitsAutoSelectSub =>
      'O núcleo mantém o tráfego num servidor ativo sozinho. O custo: cada servidor é sondado a cada três minutos, o que acorda o rádio do telemóvel.';

  @override
  String get exitsAutoSelectNeedsTwo =>
      'São necessários pelo menos dois servidores';

  @override
  String get exitsDelete => 'Eliminar saída';

  @override
  String get exitsNoServers =>
      'Sem servidores — importe primeiro uma subscrição';

  @override
  String get exitsSearch => 'Procurar servidor';

  @override
  String get exitsPickAtLeastOne => 'Selecione pelo menos um servidor';

  @override
  String get exitsUnsupportedNote =>
      'Os perfis «Auto» do painel e o hysteria2 não funcionam como saída separada: são geridos pelo outro núcleo. Esses servidores ficam desativados na lista.';

  @override
  String get infoExits =>
      'Uma saída é o destino de uma regra «Túnel».\n\nPor omissão, uma saída é UM único servidor e não custa nada em segundo plano: os protocolos comuns não mantêm ligação permanente. Um grupo de vários servidores com seleção automática só é necessário quando importa a proteção contra a queda de um nó — acrescenta sondagens periódicas e, no telemóvel, despertares do rádio.\n\nA saída só faz sentido na ação «Túnel». «Direto pela Alemanha» é uma contradição: uma regra direta contorna todas as saídas.\n\nUm site e o seu subdomínio podem ir para saídas DIFERENTES — a aplicação coloca a regra mais específica acima, caso contrário o pai absorveria o subdomínio.\n\nIMPORTANTE: com o proxy do sistema no Windows as saídas não funcionam — nesse modo não se constroem regras de encaminhamento. É preciso o modo túnel.';

  @override
  String get ruleServer => 'Via servidor';

  @override
  String get ruleServerCurrent => 'Igual ao principal';

  @override
  String ruleServerCurrentNamed(String server) {
    return 'Igual ao principal ($server)';
  }

  @override
  String get routeMatchByName => 'Correspondência pelo nome do ficheiro';

  @override
  String get routeYourApps => 'Seus aplicativos';

  @override
  String get routeYourSites => 'Seus sites';

  @override
  String get routeAppsAndSites => 'Aplicativos e sites';

  @override
  String get notifCompactTitle => 'Notificação compacta';

  @override
  String get notifCompactSub =>
      'Desativada — assinatura, servidor e velocidade, com botões. Ativada — no título o aplicativo e a assinatura, abaixo o servidor, sem velocidade e sem botões.';

  @override
  String get localProxyAuthTitle => 'Senha do proxy local';

  @override
  String get localProxyAuthInfo =>
      'A porta local do núcleo (127.0.0.1) é um proxy completo para a sua VPN. Sem senha, qualquer programa neste mesmo dispositivo se conecta a ela e recebe o seu túnel inteiro: o IP de saída, a cota da assinatura e o contorno das suas próprias regras de túnel dividido — inclusive dos aplicativos que você marcou como «Bloquear». No Android isso é ainda mais importante: lá qualquer aplicativo instalado enxerga as portas locais.\n\nDesative apenas se você usa esse proxy de propósito com algo que não sabe autenticar.';

  @override
  String get localProxyAuthOff =>
      'Desativada: o proxy local fica aberto a qualquer programa do dispositivo';

  @override
  String get localProxyAuthSystemProxy =>
      'No modo de proxy do sistema não se aplica: o Windows não sabe passar a senha ao proxy local. Vale no modo TUN.';

  @override
  String get localProxyAuthRandom =>
      'Nova senha aleatória a cada conexão — não fica guardada nas configurações';

  @override
  String get localProxyAuthCustom =>
      'Seu próprio usuário e senha (guardados no arquivo de configurações)';

  @override
  String get localProxyCredsTitle => 'Seu usuário e senha';

  @override
  String get localProxyCredsUnset =>
      'Não definidos — é usada uma senha aleatória';

  @override
  String localProxyCredsUser(String user) {
    return 'Usuário: $user';
  }

  @override
  String get localProxyDialogTitle => 'Usuário e senha do proxy local';

  @override
  String get localProxyDialogBody =>
      'Necessários apenas se você mesmo apontar outro programa para o nosso proxy (127.0.0.1). Deixe os campos vazios e a senha será aleatória a cada conexão: ela não fica guardada nas configurações e não chega ao registro nem ao relatório de suporte. A senha definida à mão permanece no arquivo de configurações em texto puro.';

  @override
  String get localProxyFieldUser => 'Usuário';

  @override
  String get localProxyFieldPassword => 'Senha';

  @override
  String get localProxyFieldHint => 'vazio — aleatória';

  @override
  String get lockdownOnTitle => 'Proteção do sistema ativada';

  @override
  String get lockdownOnSub =>
      'O tráfego fica bloqueado mesmo que o aplicativo feche ou seja encerrado pelo sistema. É o modo mais confiável.';

  @override
  String get lockdownHalfTitle => 'Proteção ativada pela metade';

  @override
  String get lockdownHalfSub =>
      'A «VPN sempre ativa» está definida, mas «Bloquear conexões sem VPN» está desligado. Enquanto o aplicativo estiver vivo, o tráfego está protegido; se o sistema o encerrar, ele sairá aberto.';

  @override
  String get lockdownOffTitle => 'Proteção do sistema desativada';

  @override
  String get lockdownOffSub =>
      'Nosso kill switch segura o tráfego enquanto o aplicativo estiver rodando. Se o sistema o encerrar, o tráfego sairá fora da VPN. Ative «VPN sempre ativa» e «Bloquear conexões sem VPN».';

  @override
  String get lockdownUnknownTitle => 'Proteção do sistema: estado desconhecido';

  @override
  String get lockdownUnknownSub =>
      'Só dá para saber o estado a partir do Android 10 e apenas com o túnel ativo. Verifique manualmente: «VPN sempre ativa» e «Bloquear conexões sem VPN».';

  @override
  String get lockdownOpenFailed =>
      'Não foi possível abrir as configurações de VPN do sistema. Encontre-as manualmente: Configurações → Rede e Internet → VPN.';

  @override
  String get blockNoticeTitle => 'Avisar sobre sites bloqueados';

  @override
  String get blockNoticeSub =>
      'Quando um aplicativo ou o navegador tenta acessar um site da lista «Bloquear», aparece embaixo uma notificação com o nome dele. Toque nela e esta tela abre.';

  @override
  String get siteInsecureScheme =>
      'O endereço está como http:// — a conexão não é criptografada e o provedor a vê por inteiro. Remova o «http://» para que o navegador use https.';

  @override
  String get exitServerGone =>
      'O servidor desta regra sumiu da assinatura — o tráfego vai pelo túnel principal';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\nEste servidor não pode subir como saída separada: os perfis «Auto» do painel e parte dos protocolos só o Xray entende, e quem distribui as saídas é o sing-box. O tráfego da regra vai pelo túnel principal.';
  }

  @override
  String get noticeRulesAction => 'Regras';

  @override
  String get geoVerdictMissingTitle => 'Bases geo não baixadas';

  @override
  String get geoVerdictMissingSub =>
      'As regras da assinatura por país e categoria estão desligadas agora — esse tráfego vai pela VPN, e não direto.';

  @override
  String get geoVerdictUnusableTitle => 'O núcleo não abriu as bases geo';

  @override
  String get geoVerdictUnusableSub =>
      'Os arquivos estão no lugar, mas o núcleo não os leu. Baixar as bases de novo costuma resolver.';

  @override
  String get geoOfferMissingSub =>
      'Sem elas, as regras da assinatura por país e categoria não vão funcionar — esse tráfego vai pela VPN, e não direto.';

  @override
  String get geoOfferDismiss => 'Não oferecer novamente';

  @override
  String get pingPendingTooltip =>
      'Latência TCP até o servidor. A verificação do canal ainda está em andamento — ainda não se sabe se o servidor funciona.';

  @override
  String get pingUnverifiedTooltip =>
      'Latência TCP até o servidor. Nenhuma verificação pelo túnel foi feita — só se conhece a acessibilidade.';

  @override
  String pingMeasuredAt(String time) {
    return 'Medido: $time';
  }

  @override
  String get pingChecking => 'verificando';

  @override
  String autoTimer(String elapsed, String remaining) {
    return 'Decorrido $elapsed · faltam cerca de $remaining';
  }

  @override
  String autoTimerNoEstimate(String elapsed) {
    return 'Decorrido $elapsed';
  }

  @override
  String autoSpeedRanking(String name) {
    return 'Medindo a velocidade: $name';
  }

  @override
  String get autoWarnNoRealIp =>
      '«Nunca usar o IP real» está ativado — todo o tráfego passa pela VPN.';

  @override
  String get autoWarnAllVpn =>
      'O modo «Tudo pela VPN» está selecionado — suas regras não estão em vigor agora.';

  @override
  String get autoWarnPanelOverride =>
      '«Minhas regras têm prioridade sobre as do painel» está ativado.';

  @override
  String get autoWarnProbesDirect =>
      'Isso não afeta a verificação em si: as sondagens contornam a VPN em qualquer configuração. Mas no modo TUN elas passam pelo processo do núcleo — se o núcleo travou, todos os resultados serão falsos negativos.';

  @override
  String get autoWarnTurnOff => 'Desativar';

  @override
  String get toastCollapse => 'Recolher';

  @override
  String get toastExpand => 'Expandir';

  @override
  String get toastOpenAutoConfig => 'Abrir a configuração automática';

  @override
  String get splitAppAlreadyAdded =>
      'Este aplicativo já está na lista de regras';

  @override
  String logsFileLine(String name, String size, int lines) {
    return '$name — $size, $lines linhas';
  }

  @override
  String logsReportsLine(int count, String size) {
    return 'Relatórios de suporte: $count, $size';
  }

  @override
  String get logsRetentionTitle => 'Manter registros e relatórios';

  @override
  String get logsRetentionDay => '1 dia';

  @override
  String get logsRetentionTwoWeeks => '2 semanas';

  @override
  String get logsRetentionMonth => '1 mês';

  @override
  String get logsRetentionNever => 'Nunca excluir';

  @override
  String get logsRetentionInfo =>
      'Os registros e os relatórios de suporte são excluídos quando ficam mais antigos que o prazo escolhido. A verificação ocorre ao iniciar o aplicativo. «Nunca» deixa tudo no disco — então acompanhe o tamanho você mesmo: um relatório inclui os registros por completo e cresce junto com eles.';

  @override
  String get logsCleanNow => 'Excluir os antigos agora';

  @override
  String logsCleaned(int count, String size) {
    return 'Arquivos excluídos: $count, liberados $size';
  }

  @override
  String get logsNothingToClean => 'Não há nada para excluir';

  @override
  String get speedTooltip => 'Velocidade de download por este servidor';

  @override
  String get speedFromAutoConfig =>
      'Velocidade medida pela configuração automática';

  @override
  String get speedBlockedTooltip =>
      'A velocidade não é medida: o servidor não passou na verificação do canal (a requisição não chegou por ele)';

  @override
  String get srvTileMeasureSpeed => 'Medir a velocidade';

  @override
  String get speedRunTooltip => 'Medir a velocidade dos servidores';

  @override
  String get speedConfirmTitle => 'Medir a velocidade?';

  @override
  String speedConfirmBody(int count, String size, String total) {
    return 'Serão testados $count servidores. Cada um baixa uma amostra de $size — cerca de $total do tráfego da sua assinatura.';
  }

  @override
  String speedConfirmSkipped(int count) {
    return 'Os já medidos são ignorados: $count.';
  }

  @override
  String get speedConfirmRun => 'Medir';

  @override
  String get speedNoTargets =>
      'Não há o que medir: a velocidade só é verificada em servidores que passaram na verificação do canal. Teste a lista primeiro.';

  @override
  String get speedNotVerified =>
      'O servidor não passou na verificação do canal — não medimos a velocidade por ele';

  @override
  String speedProgress(int done, int total) {
    return 'Velocidade: $done de $total';
  }

  @override
  String get updateOnStartTitle => 'Atualizar a assinatura ao iniciar';

  @override
  String get updateOnStartSub =>
      'Buscar uma lista de servidores nova sempre, não apenas pelo temporizador';

  @override
  String get apiSectionSub =>
      'HTTP em 127.0.0.1 — controle o cliente a partir de scripts';

  @override
  String get momentJustNow => 'agora mesmo';

  @override
  String momentMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count minutos',
      one: 'há $count minuto',
    );
    return '$_temp0';
  }

  @override
  String momentHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count horas',
      one: 'há $count hora',
    );
    return '$_temp0';
  }

  @override
  String get serviceChecksMenuTitle => 'Verificar ao conectar';

  @override
  String get serviceChecksMenuOff => 'Não verificar ao conectar';

  @override
  String get serviceChecksMenuTooltip => 'Quais serviços verificar';

  @override
  String get serviceChecksLegendOff => 'Verificação de serviços desativada';

  @override
  String get srvInfoAutoNever =>
      'A configuração automática ainda não verificou este servidor — execute-a para ver quais serviços funcionam através dele.';

  @override
  String get srvInfoAutoHint =>
      'Dados da última execução da configuração automática. Aqui nada é medido novamente.';

  @override
  String srvInfoAutoGeoNote(Object services) {
    return '$services: abre através deste servidor, mas não está disponível no país de saída. O servidor está bom — apenas estes serviços não funcionam; para eles é preciso uma saída em outro país.';
  }

  @override
  String get settingsSectionChecks => 'Verificação de serviços';

  @override
  String get settingsSectionAutotune => 'Configuração automática';

  @override
  String get settingsSpeedRankTitle =>
      'Considerar a velocidade na seleção automática';

  @override
  String get settingsSpeedRankSub =>
      'Os candidatos que passam na verificação de serviços também são medidos por download: fica em primeiro quem for realmente mais rápido. Consome tráfego da sua assinatura.';

  @override
  String get settingsSpeedTopNLabel => 'Servidores medidos por velocidade';

  @override
  String get settingsSpeedTopNSub =>
      'Mais uma medição da sua própria linha: sem ela não há com o que comparar — 60 Mbit/s é excelente numa linha de 60 e ruim numa de 300.';

  @override
  String settingsSpeedTrafficNote(Object mb) {
    return '≈$mb MB de tráfego da assinatura por execução';
  }

  @override
  String get settingsSpeedWarnTitle =>
      'A medição de velocidade gasta tráfego da assinatura';

  @override
  String settingsSpeedWarnBody(Object mb) {
    return 'Cada execução da configuração automática baixa cerca de $mb MB pela sua assinatura: uma sonda por servidor medido mais uma sonda da sua própria linha. Esses megabytes saem do seu limite.';
  }

  @override
  String get settingsSpeedWarnEnable => 'Ativar mesmo assim';

  @override
  String get settingsConcurrencyTitle => 'Verificações em paralelo';

  @override
  String get settingsConcurrencySub =>
      '1 é o comportamento anterior: os candidatos são verificados estritamente um a um, e é para aqui que se volta se os resultados ficarem estranhos. Mais é mais rápido, mas cada candidato sobe o seu próprio núcleo: a máquina fica mais carregada e as medições de latência passam a influenciar-se umas às outras.';

  @override
  String get settingsConnectChecksTitle => 'Verificar serviços ao conectar';

  @override
  String get settingsConnectChecksSubOn =>
      'Uma execução quando o túnel sobe: os chips sob o botão mostram logo o que abre e o que não abre.';

  @override
  String get settingsConnectChecksSubOff =>
      'Os chips ficam cinzentos até você tocá-los.';

  @override
  String get settingsConnectCheckServices => 'O que verificar ao conectar';

  @override
  String get settingsConnectCheckServicesSub =>
      'Um conjunto propositadamente separado do da configuração automática: aquela procura um servidor que funcione e pode demorar, enquanto estes chips respondem à pergunta «funciona agora mesmo?».';

  @override
  String get settingsConnectChecksEmpty =>
      'Nenhum serviço selecionado — não haverá nada para verificar.';

  @override
  String get settingsSectionSeamless => 'Continuidade';

  @override
  String get settingsSeamlessNote =>
      'Nenhuma destas opções mantém as ligações abertas: outro servidor significa outro IP externo e o outro lado vê um endereço diferente — uma chamada ou um download cai de qualquer forma. Trata-se apenas de a rede da máquina não piscar.';

  @override
  String get settingsSeamlessServerTitle =>
      'Não recriar o túnel ao trocar de servidor';

  @override
  String get settingsSeamlessServerSub =>
      'Só o núcleo de proxy reinicia: o adaptador e as rotas ficam no lugar, a rede da máquina não pisca. O preço: os endereços de todos os servidores da assinatura são escritos de antemão fora do túnel.';

  @override
  String get settingsSeamlessNetworkTitle =>
      'Não derrubar o canal ao mudar de rede';

  @override
  String get settingsSeamlessNetworkSub =>
      'Wi-Fi → móvel: primeiro verificamos se o tráfego ainda está vivo e só reiniciamos o núcleo se tiver morrido. O QUIC (hysteria2) sobrevive sozinho a uma mudança de endereço. O preço: se o canal realmente morreu, a recuperação começa alguns segundos mais tarde.';

  @override
  String get settingsSeamlessKeepTunTitle =>
      'Manter o adaptador ativo entre as tentativas';

  @override
  String get settingsSeamlessKeepTunSub =>
      'A rota padrão não fica a saltar enquanto decorre a recuperação. ⚠️ Isto NÃO é um kill switch: o tráfego fora da VPN não é bloqueado — mantém-se apenas o adaptador.';

  @override
  String get autoSpeedTrafficTitle =>
      'O teste de velocidade vai consumir tráfego';

  @override
  String autoSpeedTrafficBody(int servers, int mb) {
    return 'Será medida a velocidade dos $servers melhores servidores e da sua própria ligação — cerca de $mb MB do tráfego da sua subscrição.\n\nPode desativar o teste nas definições.';
  }

  @override
  String get autoSpeedTrafficGo => 'Iniciar';

  @override
  String get splitDeadPath =>
      'O ficheiro neste caminho já não existe — a regra nunca é aplicada';

  @override
  String get splitDeadPathFix =>
      'Toque para corresponder pelo nome do ficheiro';

  @override
  String get srvTileCopyKey => 'Copiar chave';

  @override
  String serviceChecksBypassDirect(Object rule) {
    return 'Fora da VPN: a regra de túnel dividido “$rule” envia este domínio diretamente — o serviço usará o seu endereço real.';
  }

  @override
  String serviceChecksBypassBlock(Object rule) {
    return 'Bloqueado: a regra de túnel dividido “$rule” proíbe este domínio — o serviço não abrirá nem com nem sem VPN.';
  }

  @override
  String get subBarOpenSite => 'Site';

  @override
  String get subBarOpenSiteHint => 'Abrir a página da assinatura no navegador';

  @override
  String subSwitcherRefreshingOne(Object name) {
    return 'Atualizando \"$name\"…';
  }

  @override
  String subSwitcherRefreshedOne(Object name) {
    return '\"$name\" atualizada';
  }

  @override
  String subSwitcherRefreshFailedOne(Object name) {
    return 'Não foi possível atualizar \"$name\"';
  }

  @override
  String subBarDeleteConfirmNamed(Object name) {
    return 'Excluir a assinatura \"$name\"?';
  }

  @override
  String get exitServerUnsupportedInfo =>
      'Este servidor não pode subir como saída separada: os perfis «Auto» do painel e parte dos protocolos só o Xray entende, e quem distribui as saídas é o sing-box. O tráfego da regra vai pelo túnel principal.';

  @override
  String get pingBusyServiceChecks =>
      'Ping indisponível: verificação de serviços em andamento';

  @override
  String get serviceChecksChannelNotReady =>
      'O túnel ainda não está pronto — as verificações não foram executadas';

  @override
  String get serviceChecksRetryCheck => 'Repetir verificação';

  @override
  String get serviceGroupMessengers => 'Mensageiros';

  @override
  String get serviceGroupAi => 'IA';

  @override
  String get serviceGroupMedia => 'Vídeo e música';

  @override
  String get serviceGroupSocial => 'Redes sociais';

  @override
  String get serviceGroupOther => 'Outros';

  @override
  String get apiTokenHidden => 'oculto — toque em «mostrar»';

  @override
  String get apiTokenShow => 'Mostrar o token';

  @override
  String get apiTokenHide => 'Ocultar o token';

  @override
  String get apiCheatSheetTitle => 'Guia rápido: endereço, portas, endpoints';

  @override
  String get apiCheatSheetBase => 'Endereço base';

  @override
  String get apiCheatSheetExitPorts => 'Portas de saída';

  @override
  String apiCheatSheetPortDirect(Object port) {
    return '$port — «Direto»: fora da VPN, IP real';
  }

  @override
  String apiCheatSheetPortServer(int port, String name) {
    return '$port — $name';
  }

  @override
  String get apiCheatSheetNoExitServers =>
      'nenhum servidor marcado — não haverá portas de servidor';

  @override
  String apiCheatSheetPortsSystemProxy(Object control) {
    return 'não são abertas: a captura é «Proxy do sistema». Só funciona a porta de controlo $control';
  }

  @override
  String get apiCheatSheetTokenOff =>
      'o token está vazio — o canal não sobe e nenhuma porta escuta';

  @override
  String get apiCheatSheetPortsWhenConnected =>
      'As portas de saída só escutam com a ligação ativa.';

  @override
  String get apiCheatSheetEndpoints => 'Endpoints';

  @override
  String get apiEpStatus =>
      'Estado do motor, servidor escolhido, modo de captura e se há ping em curso';

  @override
  String get apiEpServers =>
      'Lista de servidores com os últimos resultados de ping';

  @override
  String get apiEpExits =>
      'Distribuição das portas de saída e a entrada «Direto»';

  @override
  String get apiEpTraffic =>
      'Contadores de tráfego de toda a execução da aplicação';

  @override
  String get apiEpSubscription =>
      'Nome, validade e tráfego restante da assinatura';

  @override
  String get apiEpConnect =>
      'Ligar por chave do servidor, por nome ou «Auto»; com o canal ativo, troca de servidor';

  @override
  String get apiEpDisconnect => 'Desligar; repetir a chamada é seguro';

  @override
  String get apiEpPing =>
      'Iniciar o ping de todos os servidores; os resultados vêm de /v1/servers';

  @override
  String get apiCopyCurlExample => 'Copiar um exemplo de curl';

  @override
  String get noRealIpSubRulesOnly =>
      'Reescreve apenas as suas regras «Direto»: elas passam pelo túnel (sites RU também). Não altera a rota padrão; a rede local continua direta.';

  @override
  String get noRealIpOnlySelectedNote =>
      'No modo «Apenas os selecionados», tudo o que não está selecionado continua a sair com o seu IP real — esta opção não muda isso.';

  @override
  String get infoNoRealIp =>
      'Aplica-se APENAS às regras «Direto» explícitas (aplicações e sites) e às regras diretas da configuração do painel: elas passam a ir pelo túnel. Uma regra com «Permitir IP real» marcada continua direta.\n\nO que NÃO faz: não altera a rota padrão. No modo «Apenas os selecionados» a rota padrão continua direta, por isso todo o tráfego não selecionado sai com o seu endereço real, independentemente desta opção. Se tudo tiver de estar coberto, use «Tudo através da VPN».\n\nA rede local fica sempre direta.';

  @override
  String get killSwitchSubProxyNoAdmin =>
      'Isto não é um bloqueio real: no modo «Proxy do sistema» não são pedidos direitos de administrador e tudo o que é feito é deixar o proxy configurado. Os programas que o ignoram e todo o UDP saem diretamente. Só o TUN retém tudo.';

  @override
  String get killSwitchOfferTun =>
      'Um bloqueio completo durante uma quebra só existe no modo TUN.';

  @override
  String get splitOnlySelectedWarnTitle =>
      'Tudo o que não está selecionado sai com o seu IP real';

  @override
  String get splitOnlySelectedWarnBody =>
      'Só entra no túnel aquilo que tem a ação «Túnel». O restante tráfego — incluindo programas de que não faz ideia — sai diretamente, com o seu endereço real. Se todo o dispositivo tiver de ficar oculto, escolha «Tudo através da VPN».';

  @override
  String get splitOnlySelectedNoRealIp =>
      'A opção «Não sair com o IP real» não muda isto: reescreve apenas as regras «Direto», não a rota padrão.';

  @override
  String get splitKillSwitchIsPerApp =>
      'O kill switch retém o tráfego por programa, não por domínio: enquanto o núcleo se restabelece não há quem analise os nomes dos sites — as regras de sites não se aplicam durante esse tempo.';

  @override
  String updateNotesTitle(Object version) {
    return 'Novidades na $version';
  }

  @override
  String get updateNotesEmpty => 'Nenhuma nota de versão recebida.';

  @override
  String get updateNotesNeverShow => 'Não mostrar novamente';
}
