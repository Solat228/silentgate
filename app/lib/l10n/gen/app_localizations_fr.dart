// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonCopy => 'Copier';

  @override
  String get commonCopied => 'Copié';

  @override
  String get commonRefresh => 'Actualiser';

  @override
  String get commonCheck => 'Vérifier';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => 'Terminé';

  @override
  String get commonPathCopied => 'Chemin copié';

  @override
  String get languageTitle => 'Langue de l\'interface';

  @override
  String get languageSubtitle => 'Choisissez la langue de l\'application';

  @override
  String get languageSystem => 'Par défaut du système';

  @override
  String get sectionAppearance => 'Apparence et comportement';

  @override
  String get sectionCapture => 'Capture du trafic';

  @override
  String get sectionReliability => 'Fiabilité de la connexion';

  @override
  String get sectionPing => 'Ping';

  @override
  String get sectionIdentity => 'Identité du panneau';

  @override
  String get sectionNetwork => 'Réseau';

  @override
  String get sectionAbout => 'À propos';

  @override
  String get sectionSupport => 'Assistance';

  @override
  String get appearanceTheme => 'Thème';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get closeToTrayTitle =>
      'Réduire dans la zone de notification à la fermeture';

  @override
  String get closeToTraySubtitle =>
      'Le bouton de fermeture masque la fenêtre dans la zone de notification ; désactivez pour fermer l\'application à la place';

  @override
  String get autoUpdateSubTitle => 'Mise à jour automatique de l\'abonnement';

  @override
  String get autoUpdateSubText =>
      'Actualiser périodiquement la liste des serveurs';

  @override
  String get captureSystemProxy => 'Proxy système';

  @override
  String get captureSystemProxySub =>
      'Fonctionne immédiatement. Aucun droit administrateur.';

  @override
  String get captureTun => 'TUN (tunnel complet)';

  @override
  String get captureTunBadgeUac => 'nécessite l\'UAC';

  @override
  String get captureTunSub =>
      'Tout le trafic, y compris l\'UDP et les applications qui ignorent le proxy. Nécessite des droits administrateur.';

  @override
  String get tunProvider => 'Fournisseur TUN';

  @override
  String get tunRoutingTitle => 'TUN et routage';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'Pile $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'Tunneling fractionné';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n règles ($apps applications, $sites sites)';
  }

  @override
  String get captureTunHint =>
      'Les paramètres TUN, DNS et de tunneling fractionné apparaissent lorsque le mode TUN est sélectionné — en mode proxy système, ils n\'ont aucun effet.';

  @override
  String get dnsShortVpn => 'via VPN';

  @override
  String get dnsShortSystem => 'système';

  @override
  String get dnsShortCustom => 'personnalisé';

  @override
  String get tunUacTitle => 'TUN nécessite des droits administrateur';

  @override
  String get tunUacBody =>
      'Vous pouvez le configurer une seule fois : l\'application créera une tâche du Planificateur de tâches Windows avec les privilèges les plus élevés, après quoi le tunnel démarrera SANS invite UAC.\n\nUne invite administrateur apparaîtra maintenant. L\'application elle-même continue de fonctionner sans droits élevés.';

  @override
  String get tunUacLater => 'Plus tard (demander à chaque fois)';

  @override
  String get tunUacSetup => 'Configurer';

  @override
  String get tunUacDone => 'Terminé : TUN démarrera sans invite UAC';

  @override
  String get tunUacFail =>
      'Impossible de créer la tâche — l\'UAC sera demandé à la connexion';

  @override
  String get autoReconnectTitle => 'Reconnexion automatique';

  @override
  String get autoReconnectSub =>
      'Rétablir la connexion en cas de coupure ou de changement de réseau';

  @override
  String get killSwitchTitle => 'Kill switch';

  @override
  String get alwaysOnTitle => 'Protection système';

  @override
  String get alwaysOnSub =>
      'VPN toujours actif et « bloquer les connexions sans VPN » — actif même app fermée';

  @override
  String get killSwitchSubTun =>
      'Empêcher le trafic de contourner le VPN pendant la reconnexion';

  @override
  String get killSwitchSubProxy =>
      'En mode « Proxy système », il protège uniquement les applications compatibles proxy. Complètement — uniquement en TUN';

  @override
  String get killSwitchSubOff =>
      'Nécessite l\'activation de la reconnexion automatique';

  @override
  String get networkRecoverTitle => 'Récupérer le réseau';

  @override
  String get networkRecoverSub =>
      'Si Internet a disparu après le VPN. Nécessite des droits administrateur';

  @override
  String get networkRecoverConfirmTitle => 'Récupérer le réseau ?';

  @override
  String get networkRecoverConfirmBody =>
      'Réinitialisation de winsock, de la pile IP, du DNS et du proxy système. Des droits administrateur (UAC) sont requis. La réinitialisation de winsock/IP prend effet après un redémarrage.';

  @override
  String get networkRecoverConfirmOk => 'Récupérer';

  @override
  String get interferenceTitle => 'Vérifier les interférences (autres VPN)';

  @override
  String get interferenceDialogTitle => 'Interférences réseau';

  @override
  String get interferenceNoneFound =>
      'Aucun autre VPN ni interférence détecté.';

  @override
  String get interferenceIgnore => 'Ignorer';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'Mis à jour automatiquement avec la version de l\'application. Sont également envoyés : X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'Schémas d\'URL';

  @override
  String get urlSchemesSub =>
      'Importer et contrôler le VPN via des liens (connexion / bascule / mise à jour)';

  @override
  String get panelOwnerTitle => 'Pour le propriétaire du panneau';

  @override
  String get panelOwnerBody =>
      'Les utilisateurs ordinaires n\'en ont pas besoin — vous pouvez l\'ignorer.\n\nPour que l\'application reçoive votre abonnement au bon format JSON (XRAY_JSON), ajoutez ce bloc aux Response Rules de votre panneau Remnawave — il correspond à notre User-Agent :';

  @override
  String get panelOwnerCopy => 'Copier le bloc';

  @override
  String get aboutVersion => 'Version de SilentGate';

  @override
  String get aboutXrayCore => 'Cœur Xray';

  @override
  String get aboutHwid => 'HWID de l\'appareil';

  @override
  String get aboutThirdPartyTitle => 'Composants tiers et licences';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — exécutés en tant que processus séparés';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — intégrés à l’application';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'Journaux';

  @override
  String get logsSub =>
      'Application et TUN (sing-box) : import d\'abonnement, ping, erreurs';

  @override
  String get thirdPartyTitle => 'Composants tiers';

  @override
  String get thirdPartyBody =>
      'SilentGate est distribué avec des exécutables tiers. Ils s\'exécutent en tant que processus SÉPARÉS et ne sont pas intégrés à l\'application.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  Tunnel TUN et cœur proxy pour Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — licence Wintun\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — données de routage, CC-BY-SA-4.0\n\nLes textes complets des licences se trouvent dans le dossier « licenses » à côté de l\'application.';

  @override
  String get supportSectionNote =>
      'Appuyez sur « Contacter l\'assistance » — une fenêtre s\'ouvre où vous générez vous-même un fichier journal (versions, système d\'exploitation, paramètres, app.log + fin de singbox.log ; aucun mot de passe ni jeton d\'abonnement, URL masquée). Ensuite, un bouton pour l\'envoyer à l\'assistance Telegram apparaît.';

  @override
  String get supportButtonTitle => 'Contacter l\'assistance';

  @override
  String get supportButtonSub =>
      'Générer un journal et ouvrir le chat d\'assistance';

  @override
  String get supportDialogTitle => 'Assistance';

  @override
  String get supportDialogTitleDone => 'Le journal est prêt — où l\'envoyer';

  @override
  String get supportWhatWillHappen => 'Ce qui va se passer :';

  @override
  String get supportBullet1 =>
      '• Un fichier rassemblera les versions, le système d\'exploitation, les paramètres et les journaux (app.log + fin de singbox.log). Il ne contient aucun mot de passe ni jeton d\'abonnement, l\'URL d\'abonnement est masquée.';

  @override
  String get supportBullet2 =>
      '• Après l\'appui, D\'ABORD le dossier contenant le fichier s\'ouvre, puis le fichier lui-même. Décrivez le problème en haut, enregistrez-le — et un bouton pour l\'envoyer à l\'assistance apparaît.';

  @override
  String supportError(String error) {
    return 'Échec de la création du rapport : $error';
  }

  @override
  String get supportDoneText =>
      'Le rapport est créé et ouvert (dossier, puis fichier). Décrivez le problème en haut, enregistrez le fichier et envoyez-le à l\'assistance — l\'application aidera à ouvrir Telegram.';

  @override
  String get supportWhoTo => 'Où envoyer :';

  @override
  String get supportContact => 'Contacter l\'assistance';

  @override
  String supportContactNamed(String name) {
    return 'Contacter l\'assistance ($name)';
  }

  @override
  String get supportDevServiceName => 'Développeur du client';

  @override
  String get supportShowOnPc => 'Afficher sur le PC';

  @override
  String get supportCopyPath => 'Copier le chemin';

  @override
  String get supportGenerating => 'Création…';

  @override
  String get supportGenerateButton => 'Générer un journal d\'assistance';

  @override
  String get pingTwoPhaseTitle => 'Vérifier le fonctionnement (via le tunnel)';

  @override
  String get pingTwoPhaseSubOn =>
      'Après le TCP — une requête via le serveur : filtre les serveurs non fonctionnels (Reality, etc.)';

  @override
  String get pingTwoPhaseSubOff =>
      'Seule la méthode unique sélectionnée (ci-dessous) est utilisée';

  @override
  String get pingMethodCheck => 'Méthode de vérification :';

  @override
  String get pingMethodPing => 'Méthode de ping :';

  @override
  String get speedTestProbe => 'Sonde de test de vitesse :';

  @override
  String get speedTestFull => '20 Mo (plus précis)';

  @override
  String get speedTestLight => '5 Mo (économique)';

  @override
  String get testUrlLabel => 'URL de test (via proxy)';

  @override
  String get appUpdateServerUnavailable =>
      'Serveur de mise à jour indisponible';

  @override
  String appUpdateAvailable(String version) {
    return 'Version $version disponible';
  }

  @override
  String get appUpdateLatest => 'Vous disposez de la dernière version';

  @override
  String get appUpdateDownload => 'Télécharger';

  @override
  String get appUpdateCheckTitle => 'Vérifier les mises à jour au démarrage';

  @override
  String get appUpdateManual => 'Téléchargement et installation — manuels';

  @override
  String get appUpdateEndpointLabel => 'Point de terminaison de version';

  @override
  String get urlSchemeSilentgateTitle => 'Liens silentgate://';

  @override
  String get urlSchemeSilentgateSub =>
      'Importer et contrôler le VPN via des liens. Activé par défaut';

  @override
  String get urlSchemeDisableTitle => 'Désactiver les liens silentgate:// ?';

  @override
  String get urlSchemeDisableBody =>
      'L\'import via lien et les schémas de contrôle (connexion / déconnexion / bascule / mise à jour) cesseront de fonctionner. Laissez activé en cas de doute.';

  @override
  String get urlSchemeDisableOk => 'Désactiver';

  @override
  String get urlSchemeServerTitle => 'Ouvrir les liens de serveur';

  @override
  String get urlSchemeServerSub =>
      'Intercepter vless:// et d\'autres liens depuis d\'autres clients';

  @override
  String get urlSchemeServerConfirmTitle =>
      'Intercepter les liens de serveur ?';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nCes liens sont généralement associés à un autre client VPN (Happ, v2rayTun). SilentGate les prendra en charge.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'Intercepter';

  @override
  String get urlSchemeAutoConnect => 'Se connecter après l\'import';

  @override
  String get autoTitle => 'Configuration automatique';

  @override
  String get autoClearResults => 'Effacer les résultats';

  @override
  String autoFoundWorking(Object count) {
    return 'Fonctionnels trouvés : $count';
  }

  @override
  String get autoPinnedTop => ' — épinglés en haut de la liste';

  @override
  String get autoSearchContinues => ' (la recherche continue…)';

  @override
  String get autoCheckServices => 'Vérifier les services';

  @override
  String get autoPinFoundOnTop =>
      'Épingler les serveurs trouvés en haut de la liste';

  @override
  String get autoTryFragment => 'Essayer le contournement (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'Aucun abonnement. Collez une clé unique — nous trouverons des paramètres fonctionnels :';

  @override
  String get autoTuneByKey => 'Configurer par clé';

  @override
  String autoTesting(int index, int total) {
    return 'Test $index/$total : ';
  }

  @override
  String autoVariant(Object label) {
    return 'Variante : $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$ok services sur $total';
  }

  @override
  String get autoConnect => 'Se connecter';

  @override
  String get autoStopSearch => 'Arrêter la recherche';

  @override
  String get autoDoneRefreshPing =>
      'Terminé — actualiser le ping des serveurs trouvés';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return '$count trouvés, épinglés en haut. Actualisation du ping…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'Serveurs à configurer ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'Tous';

  @override
  String get autoDeselectAll => 'Effacer';

  @override
  String get autoTuneSelected => 'Configurer la sélection';

  @override
  String autoTuned(Object label) {
    return 'Configuré : $label';
  }

  @override
  String get infoDialogTitle => 'Info';

  @override
  String get infoCopied => 'Explication copiée';

  @override
  String get commonGotIt => 'Compris';

  @override
  String get enumSplitAll => 'Tout — via VPN';

  @override
  String get enumSplitOnly => 'Seulement la sélection — via VPN';

  @override
  String get enumSplitExcept => 'La sélection — hors VPN';

  @override
  String get enumActionTunnel => 'Tunnel';

  @override
  String get enumActionDirect => 'Direct';

  @override
  String get enumActionBlock => 'Bloquer';

  @override
  String homeUpdateAvailable(Object version) {
    return 'Version $version disponible';
  }

  @override
  String get homeDownload => 'Télécharger';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'Abonnement mis à jour : $summary';
  }

  @override
  String get homeReconnect => 'Reconnecter';

  @override
  String homePingProgress(int done, int total) {
    return 'Ping des serveurs : $done sur $total';
  }

  @override
  String get homeAutoConfigStarting =>
      'Démarrage de la configuration automatique…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'Configuration automatique : $current sur $total — $name';
  }

  @override
  String get homeImport => 'Importer';

  @override
  String get homeSettings => 'Paramètres';

  @override
  String get homeAutoBest => 'Auto (meilleur serveur)';

  @override
  String get homeAutoConfig => 'Configuration automatique';

  @override
  String homeServersCount(Object count) {
    return 'Serveurs ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return '$found trouvés sur $total';
  }

  @override
  String get homePingServers => 'Ping des serveurs';

  @override
  String get homePingFound => 'Ping des trouvés';

  @override
  String get homeNothingFound => 'Aucun résultat';

  @override
  String get homeOnboardingTitle => 'Commencez par importer un abonnement';

  @override
  String get homeOnboardingSubtitle =>
      'Collez un lien Remnawave ou une clé unique';

  @override
  String get homeImportSubscription => 'Importer un abonnement';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'Cette session : ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'Go';

  @override
  String subBarUsage(String used, String total) {
    return '$used sur $total';
  }

  @override
  String get subBarSubscription => 'Abonnement';

  @override
  String get subBarRefreshing => 'Actualisation…';

  @override
  String get subBarRefreshSubscription => 'Actualiser l\'abonnement';

  @override
  String get subBarSupport => 'Assistance';

  @override
  String get subBarRefresh => 'Actualiser';

  @override
  String get subBarAddSubscription => 'Ajouter un abonnement';

  @override
  String get subBarCopyLink => 'Copier le lien';

  @override
  String get subBarDeleteSubscription => 'Supprimer l\'abonnement';

  @override
  String get subBarLinkCopied => 'Lien copié';

  @override
  String get subBarDeleteConfirmTitle => 'Supprimer l\'abonnement ?';

  @override
  String get subBarDeleteConfirmBody =>
      'Les serveurs de cet abonnement seront retirés de la liste.';

  @override
  String subBarDeletePinned(Object count) {
    return 'Supprimer aussi les épinglés ($count) avec leurs modifications';
  }

  @override
  String get subBarDeletePinnedHint =>
      'Sinon, ils restent dans la liste et survivent à la suppression';

  @override
  String get subBarCancel => 'Annuler';

  @override
  String get subBarDelete => 'Supprimer';

  @override
  String get subBarSubscriptionDeleted => 'Abonnement supprimé';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'Abonnement mis à jour : $summary';
  }

  @override
  String get subBarMore => 'Détails';

  @override
  String subBarAdded(Object count) {
    return 'Ajoutés ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'Retirés ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· mise à jour auto ${hours}h';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'Valide : illimité  $auto';
  }

  @override
  String get subBarExpired => 'Abonnement expiré :';

  @override
  String get subBarValidUntil => 'Valide jusqu\'au :';

  @override
  String get infoCaptureMode =>
      'Comment le trafic est intercepté. « Proxy système » définit un proxy local dans le système (aucun droit administrateur ; capture les navigateurs et la plupart des applications). « TUN » est un adaptateur réseau virtuel qui capture TOUT le trafic (y compris l\'UDP et les applications qui ignorent le proxy), mais nécessite des droits administrateur.';

  @override
  String get infoSystemProxy =>
      'Un proxy HTTP local dans les paramètres du système (registre WinINET). Aucun droit administrateur. N\'intercepte pas l\'UDP ni les applications qui ignorent le proxy système.';

  @override
  String get infoTunMode =>
      'Un tunnel complet via l\'adaptateur virtuel wintun + sing-box. Capture tout le trafic, y compris l\'UDP. Demande des droits administrateur (UAC) lors de l\'activation.';

  @override
  String get infoTunProvider =>
      'Le pilote de l\'adaptateur réseau virtuel. Sous Windows, wintun est utilisé (fourni avec le cœur). Aucun autre pilote n\'est requis.';

  @override
  String get infoTunStack =>
      'La pile réseau TUN (sing-box).\n\n« auto » — SÉLECTION AUTOMATIQUE : si le tunnel ne parvient pas à s\'établir, l\'application parcourt elle-même system → gvisor → mixed, puis abaisse le MTU (1400, 1280). La combinaison qui a fonctionné est mémorisée et essayée en premier la fois suivante. La progression de la sélection est affichée dans le statut et dans le journal.\n\nUn choix explicite désactive la sélection automatique : system — la pile du système, la plus rapide, mais plus capricieuse avec les antivirus ; gvisor — espace utilisateur, plus lente, compatibilité maximale ; mixed — TCP via system, UDP via gvisor.';

  @override
  String get infoTunMtu =>
      'La taille maximale des paquets dans l\'adaptateur TUN. La valeur par défaut est 1500 ; abaissez-la (1400, 1280) si vous subissez des déconnexions — une valeur trop petite réduit la vitesse.\n\nAvec la pile « auto », ce n\'est que la valeur de départ : si le tunnel ne parvient pas à s\'établir, l\'application essaiera elle-même des MTU plus petits.';

  @override
  String get infoTunStrictRoute =>
      'Routage strict dans sing-box. Sous Windows, il corrige deux problèmes typiques : les fuites DNS (par défaut, le système envoie les requêtes à tous les adaptateurs à la fois) et les erreurs « réseau inaccessible ». Désactivez-le uniquement s\'il perturbe VirtualBox/Hyper-V.';

  @override
  String get infoTunIpv6 =>
      'Router l\'IPv6 dans le tunnel. Si vous le désactivez alors que votre FAI a activé l\'IPv6, une partie du trafic passera EN DEHORS du VPN (révélant votre véritable adresse) ou se bloquera. Désactivez-le uniquement si vous avez des problèmes de réseau IPv6.';

  @override
  String get infoTunEndpointIndependentNat =>
      'Mode NAT pour l\'UDP. Nécessaire pour les jeux, les chats vocaux et WebRTC — sans lui, les connexions peuvent ne pas s\'établir. Désactivez-le uniquement pour économiser de la mémoire.';

  @override
  String get infoTunBypassLan =>
      'Le réseau local (adresses privées 192.168.*, 10.*, routeur, imprimantes, NAS) contourne le VPN. Vous voulez généralement l\'activer, sinon vous perdez l\'accès aux appareils du réseau.';

  @override
  String get infoTunExcludeCidrs =>
      'Sous-réseaux supplémentaires qui contournent toujours le VPN (format CIDR, par ex. 10.8.0.0/24). Utile pour les réseaux d\'entreprise et les autres VPN.';

  @override
  String get infoTunPrivilege =>
      'TUN nécessite des droits administrateur. Une seule fois, nous créons une tâche dans le Planificateur de tâches Windows avec les privilèges les plus élevés — après quoi le tunnel démarre SANS invite UAC à chaque connexion. La tâche vous appartient et est supprimée avec le bouton ci-dessous ou lors de la désinstallation du programme.';

  @override
  String get infoAppUpdate =>
      'Une fois par démarrage, l\'application demande à votre serveur s\'il existe une version plus récente et affiche une notification avec un bouton « Télécharger ».\n\nL\'application ne télécharge et n\'exécute RIEN d\'elle-même : l\'installateur n\'est pas signé par un certificat, et l\'exécution automatique d\'un exe téléchargé se heurte à SmartScreen et ressemble, pour les antivirus, à un comportement de logiciel malveillant. Vous installez la mise à jour vous-même.\n\nSi le serveur est indisponible, l\'application reste simplement silencieuse et écrit une entrée dans le journal. Le format de réponse et la configuration du serveur sont décrits dans docs/APP_UPDATE.md.';

  @override
  String get infoSpeedTest =>
      'La quantité de données téléchargées lors de la mesure de la vitesse (clic droit sur un serveur → « Infos serveur » → « Mesurer la vitesse »).\n\n20 Mo — le mode principal : sur les liaisons rapides (100+ Mbit/s), une sonde courte n\'a pas le temps de monter en régime et sous-estime le résultat.\n5 Mo — le mode économique : nettement moins coûteux en trafic, pratique pour parcourir de nombreux serveurs.\n\nLa mesure s\'exécute UNIQUEMENT manuellement et consomme le trafic de votre abonnement. La vitesse est mesurée deux fois : directement et via le serveur sélectionné, afin que vous puissiez voir exactement combien est perdu sur le VPN.';

  @override
  String get infoAutoReconnect =>
      'Si le cœur a planté, si le serveur a coupé ou si le réseau a changé (Wi-Fi ↔ câble, sortie de veille, nouvelle IP), l\'application rétablit la connexion d\'elle-même. Les pauses entre les tentatives augmentent : 0,8 s → 3 s → 8 s → 20 s, jusqu\'à 8 tentatives, après quoi une erreur est affichée. Se déconnecter avec le bouton annule toujours la récupération.\n\nUn changement de réseau est détecté par les adresses réelles des autres adaptateurs : votre propre tunnel et les adresses de service (link-local) ne sont pas comptés, un changement n\'est accepté que s\'il s\'est maintenu pendant deux sondages consécutifs, et le signal est ignoré pendant les 15 premières secondes après la connexion. Sans ces protections, l\'établissement du tunnel serait lui-même considéré comme un « changement de réseau » et provoquerait une reconnexion sans fin.';

  @override
  String get infoKillSwitch =>
      'Ne pas laisser le trafic sortir en contournant le VPN pendant le rétablissement de la connexion. La capture n\'est PAS relâchée entre les tentatives : en mode TUN, l\'adaptateur reste actif, en mode « Proxy système », le proxy reste configuré — les applications obtiennent une erreur de connexion au lieu d\'un accès non chiffré à Internet.\n\nHonnêtement, à propos des limites : en mode « Proxy système », cela ne protège que les programmes qui respectent le proxy système (navigateurs et la plupart des applications). Les programmes qui ignorent le proxy, et l\'UDP, passeront directement — l\'étanchéité complète n\'est assurée que par le mode TUN. Nécessite l\'activation de la reconnexion automatique.';

  @override
  String get infoUserAgent =>
      'Comment l\'application s\'identifie auprès du panneau (l\'en-tête User-Agent). Elle envoie toujours « SilentGate/version (Windows) ».\n\nD\'après ce nom, le panneau Remnawave choisit le FORMAT de l\'abonnement. XRAY_JSON est nécessaire — il fournit des configurations de serveur prêtes à l\'emploi ; à partir d\'une liste de liens en base64, certains paramètres ne sont restaurés qu\'approximativement, et la sélection automatique (burstObservatory) fonctionne moins bien.\n\nConfiguré dans le panneau : Templates → Response Rules → une règle avec la condition user-agent CONTAINS SilentGate et le type de réponse XRAY_JSON (placez-la au-dessus de la règle Fallback Base64).\n\nLe champ de remplacement n\'est nécessaire qu\'en tant que solution de contournement temporaire — si le panneau ne connaît pas encore l\'application, vous pouvez vous identifier comme un client qu\'il connaît.';

  @override
  String get infoDnsMode =>
      'Qui résout les domaines en mode TUN. « Via VPN » (recommandé) — les requêtes passent dans le tunnel via TCP, et votre FAI ne voit pas quels sites vous ouvrez. « Système » — comme dans Windows : une fuite DNS est possible, et si le serveur ne transmet pas l\'UDP, Internet peut tomber complètement. « Personnalisé » — le serveur que vous indiquez, via le tunnel.';

  @override
  String get infoDnsCustomServer =>
      'L\'adresse du serveur DNS pour le mode « Personnalisé » (par exemple 9.9.9.9 ou 8.8.8.8). Les requêtes vers celui-ci passent dans le tunnel via TCP.';

  @override
  String get infoDnsHijack =>
      'Intercepter les requêtes DNS (port UDP 53) à l\'intérieur du tunnel. Sans cela, les requêtes échappent aux règles : une fuite est possible, et les règles de domaine du tunneling fractionné fonctionnent avec moins de précision.';

  @override
  String get infoDnsStrategy =>
      'Quelles adresses demander : prefer_ipv4 (recommandé) — IPv4 d\'abord, ipv4_only — IPv4 uniquement (corrige les problèmes d\'IPv6 défectueux), prefer_ipv6/ipv6_only — pour les réseaux IPv6.';

  @override
  String get infoSingboxLogLevel =>
      'Le niveau de détail du journal de sing-box (%APPDATA%\\SilentGate\\singbox.log). warn — mode normal. info/debug — si le tunnel ne fonctionne pas : le journal montrera la cause exacte. debug augmente notablement la taille du fichier.';

  @override
  String get infoSplitMode =>
      'La base — vers où va tout ce qui n\'a pas d\'action définie manuellement, et quelle action est attribuée aux nouvelles entrées. « Tout — via VPN » : par défaut, tout le trafic dans le tunnel. « Seulement la sélection — via VPN » : par défaut en direct, dans le tunnel uniquement ceux marqués « Tunnel ». « La sélection — hors VPN » : l\'inverse, tout dans le tunnel, et ceux marqués « Direct » passent directement.';

  @override
  String get infoSplitApps =>
      'Cliquez sur une application — une fenêtre s\'ouvre où vous choisissez l\'action (Tunnel — via VPN, Direct — hors VPN, Bloquer — pas de réseau) et la méthode de correspondance : par nom d\'exe (fiable) ou par chemin complet. Vous pouvez choisir parmi les applications en cours d\'exécution ou indiquer un .exe.';

  @override
  String get infoSplitDomains =>
      'Domaines (suffixes). Par exemple, youtube.com couvre aussi www.youtube.com. Fonctionne d\'après le nom issu de la connexion TLS (SNI).';

  @override
  String get infoVerifyViaProxy =>
      'Nous vérifions d\'abord le fonctionnement via le proxy (le serveur renvoie effectivement 204), et ce n\'est que si le serveur a répondu que nous mesurons séparément la latence avec la méthode choisie (TCP/ICMP).';

  @override
  String get infoProxyGet =>
      'Une requête GET via le tunnel vers l\'URL de test. Vérifie que le serveur transmet réellement le trafic et renvoie 204. Le test de fonctionnement le plus honnête ; un peu plus lent.';

  @override
  String get infoProxyHead =>
      'Comme GET, mais uniquement les en-têtes — plus rapide et moins de trafic. Certains serveurs/CDN peuvent ne pas prendre en charge HEAD.';

  @override
  String get infoTcp =>
      'Le temps de la poignée de main TCP vers l\'adresse du serveur. Un indicateur de latence rapide et précis, mais qui ne prouve pas que le tunnel fonctionne : un serveur Reality répondra en TCP même si le proxy est bloqué. Recommandé pour la latence.';

  @override
  String get infoIcmp =>
      'Ping système. Souvent inutile pour Reality/CDN : l\'ICMP peut être bloqué, ou il mesure le nœud CDN le plus proche. Réservez-le au diagnostic réseau.';

  @override
  String get infoTestUrl =>
      'L\'URL pour vérifier le fonctionnement via le proxy. Par défaut https://www.gstatic.com/generate_204 — elle renvoie une réponse 204 vide, ce qui est pratique et rapide.';

  @override
  String get infoAutoConfig =>
      'Parcourt les serveurs et les variantes de contournement (fragment, fingerprint) et dresse une liste de ceux où les services sélectionnés fonctionnent. Il ne s\'arrête pas au premier — vous choisissez parmi ceux trouvés. La vérification s\'effectue via le proxy ; le VPN n\'est pas activé pendant ce temps.';

  @override
  String get infoAutoConfigServices =>
      'Quels services doivent fonctionner pour qu\'un serveur soit considéré comme convenable. La vérification résiste aux pages de substitution du FAI (la signature de la réponse est vérifiée, pas seulement un « 200 OK »).';

  @override
  String get infoAutoPinFound =>
      'Les combinaisons fonctionnelles trouvées (serveur + variante de contournement) sont immédiatement épinglées en haut de la liste commune des serveurs, afin que vous puissiez les utiliser sans revenir ici. Désactivez-le si vous ne voulez pas que la configuration automatique modifie l\'ordre de votre liste — les résultats resteront visibles sur cet écran.';

  @override
  String get infoTryFragment =>
      'Essayez la variante avec fragmentation du ClientHello TLS (contournement DPI) si le serveur « brut » ne fonctionne pas. Un peu plus long, mais trouve une combinaison fonctionnelle sur les serveurs bridés.';

  @override
  String get infoAutoStrategy =>
      '« Premier fonctionnel » — parcourir tout et se connecter à n\'importe lequel trouvé (vous choisissez). « Meilleur dans le budget » — rechercher dans une limite de temps et choisir le plus rapide.';

  @override
  String get infoScheme =>
      'Enregistre le protocole silentgate:// dans le système (pour l\'utilisateur actuel, sans droits administrateur). Ensuite, cliquer sur un lien silentgate://import?url=… (import) ou silentgate://connect / toggle (contrôle) dans un navigateur ouvre l\'application et exécute l\'action. Activé par défaut.';

  @override
  String get infoAutoConnectAfterImport =>
      'Se connecter au premier serveur immédiatement après un import réussi d\'abonnement via lien.';

  @override
  String get infoNetworkRecover =>
      'Réinitialise les paramètres réseau si Internet a disparu après un plantage/arrêt du PC avec le VPN activé : winsock, la pile IP, le cache DNS, le proxy système. Nécessite des droits administrateur ; la réinitialisation de winsock et de la pile IP prend effet après un REDÉMARRAGE.';

  @override
  String get infoInterference =>
      'Une vérification des autres VPN et des interférences réseau (adaptateurs TUN étrangers, processus VPN, zapret/GoodbyeDPI) qui peuvent entrer en conflit avec SilentGate. Vous pouvez les fermer ou les ignorer.';

  @override
  String get pingInfoProxyGet =>
      'Une requête GET via le tunnel vers l\'URL de test. Vérifie que le serveur transmet réellement le trafic et renvoie 204. Le test de fonctionnement le plus honnête ; un peu plus lent en raison du téléchargement complet de la réponse. Recommandé pour une vérification de fonctionnement.';

  @override
  String get pingInfoProxyHead =>
      'Comme GET, mais ne demande que les en-têtes — moins de trafic et plus rapide. Vérifie le fonctionnement du tunnel ; certains serveurs/CDN peuvent ne pas prendre en charge HEAD.';

  @override
  String get pingInfoTcp =>
      'Mesure le temps de la poignée de main TCP vers l\'adresse du serveur. Un indicateur rapide et précis de la latence du point de terminaison, mais qui ne prouve pas que le tunnel fonctionne : un serveur Reality répondra en TCP même si le proxy est bloqué. Recommandé pour la latence.';

  @override
  String get pingInfoIcmp =>
      'Ping système (echo request). Souvent inutile pour Reality/CDN : l\'ICMP peut être bloqué, ou il mesure le nœud CDN le plus proche plutôt que le serveur. Réservez-le au diagnostic réseau.';

  @override
  String get pingInfoTwoPhase =>
      'Après la vérification TCP, les serveurs qui ont répondu sont en outre vérifiés par une requête via le tunnel (GET/HEAD vers l\'URL de test). Cela élimine les serveurs qui gardent le port ouvert mais ne relaient pas le trafic. La latence est toujours indiquée par le TCP.';

  @override
  String get pingInfoTunStage =>
      'Un tunnel complet (TUN) est l\'étape suivante. Actuellement, le mode « Proxy système » est utilisé. En mode TUN, tout le trafic (y compris l\'UDP et les applications qui ignorent le proxy) passera par l\'adaptateur virtuel wintun + tun2socks. Nécessite des droits administrateur.';

  @override
  String get pingInfoTunStack =>
      'La pile réseau TUN (sing-box). auto — laisser au cœur le soin de décider (actuellement mixed). system — la pile du système : vitesse maximale, mais plus capricieuse avec les droits/antivirus. gvisor — une pile en espace utilisateur : plus lente, mais la plus compatible. mixed — TCP via system, UDP via gvisor (un compromis). Si TUN ne se connecte pas ou coupe les connexions — essayez gvisor.';

  @override
  String get pingInfoAutoConfig =>
      'Lorsqu\'elle est activée, l\'application parcourt elle-même les serveurs et les variantes de contournement (fragment, fingerprint) et se connecte au premier où les services sélectionnés fonctionnent (vérification via le proxy, sans activer le VPN pendant la recherche).';

  @override
  String get logsTabApp => 'Application';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'Actualiser';

  @override
  String get logsCopy => 'Copier';

  @override
  String get logsClearApp => 'Effacer le journal de l\'application';

  @override
  String get logsCopied => 'Journal copié';

  @override
  String get logsLoading => 'Chargement…';

  @override
  String get logsEmpty => 'Vide pour l\'instant.';

  @override
  String get logsTunEmpty =>
      'Vide — TUN n\'a pas encore été démarré sur ce système.';

  @override
  String get importScrDone => 'Importé';

  @override
  String get importScrWelcome => 'Bienvenue sur SilentGate';

  @override
  String get importScrTitle => 'Importer un abonnement';

  @override
  String get importScrSubscriptionFallback => 'Abonnement';

  @override
  String get importScrHint =>
      'Collez un lien d\'abonnement (Remnawave), un lien profond silentgate://, ou un seul lien vless:// / vmess:// / trojan:// / ss:// / hysteria2://';

  @override
  String get importScrLoading => 'Chargement…';

  @override
  String get importScrPasteImport => 'Importer depuis le presse-papiers';

  @override
  String get importScrImportField => 'Importer depuis le champ';

  @override
  String get serversTitle => 'Serveurs';

  @override
  String serversFound(int found, int total) {
    return 'Serveurs — $found trouvés sur $total';
  }

  @override
  String get serversRefresh => 'Actualiser l\'abonnement';

  @override
  String get serversPinging => 'Ping en cours…';

  @override
  String get serversPingAll => 'Ping de tous';

  @override
  String get serversPingFound => 'Ping des trouvés';

  @override
  String get serversEmpty =>
      'La liste des serveurs est vide. Importez un abonnement.';

  @override
  String get serversNothingFound => 'Aucun résultat';

  @override
  String get toastCopied => 'Copié';

  @override
  String get toastHide => 'Masquer';

  @override
  String get srvInfoTitle => 'Informations sur le serveur';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'Échec du démarrage de la connexion de test : $error';
  }

  @override
  String get srvInfoServerAddressFailed =>
      'Impossible de déterminer l\'adresse du serveur';

  @override
  String get srvInfoSectionExit => 'Où vous sortez';

  @override
  String get srvInfoExitHint =>
      'Déterminé à partir de l\'adresse du serveur — aucun tunnel n\'est démarré pour cela.';

  @override
  String get srvInfoAddressLocation => 'Adresse et emplacement du serveur';

  @override
  String get srvInfoCheckAgain => 'Vérifier à nouveau';

  @override
  String get srvInfoSectionSpeed => 'Vitesse';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'La sonde télécharge $size et utilise le trafic de votre abonnement. La taille peut être modifiée dans les paramètres.';
  }

  @override
  String get srvInfoViaServer => 'Via le serveur';

  @override
  String get srvInfoWithoutVpn => 'Sans VPN';

  @override
  String get srvInfoMeasuring => 'Mesure en cours…';

  @override
  String get srvInfoMeasureSpeed => 'Mesurer la vitesse';

  @override
  String get srvInfoSectionParams => 'Paramètres de connexion';

  @override
  String get srvInfoParamAddress => 'Adresse';

  @override
  String get srvInfoParamProtocol => 'Protocole';

  @override
  String get srvInfoParamTransport => 'Transport';

  @override
  String get srvInfoParamTlsFingerprint => 'Empreinte TLS';

  @override
  String get srvInfoParamType => 'Type';

  @override
  String get srvInfoPanelAutoProfile =>
      'Profil de sélection automatique du panneau';

  @override
  String get srvInfoCouldNotDetermine => 'impossible à déterminer';

  @override
  String get srvInfoCopy => 'Copier';

  @override
  String get editorJsonTitle => 'Config JSON';

  @override
  String get editorCopy => 'Copier';

  @override
  String get editorClose => 'Fermer';

  @override
  String get editorTitle => 'Modifier le serveur';

  @override
  String get editorFieldName => 'Nom';

  @override
  String get editorFieldAddress => 'Adresse';

  @override
  String get editorFieldPort => 'Port';

  @override
  String get editorFieldUuidPassword => 'UUID / mot de passe';

  @override
  String get editorFieldObfs => 'Obfuscation (généralement salamander)';

  @override
  String get editorFieldObfsPassword => 'Mot de passe d\'obfuscation';

  @override
  String get editorFieldPortHopping => 'Saut de port (par ex. 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'Autoriser le certificat auto-signé';

  @override
  String get editorAllowSelfSignedSub =>
      'Nécessaire uniquement si le serveur est configuré ainsi';

  @override
  String get editorTransport => 'Transport';

  @override
  String get editorSecurity => 'Sécurité';

  @override
  String get editorNone => '(aucun)';

  @override
  String get editorCancel => 'Annuler';

  @override
  String get editorSave => 'Enregistrer';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count serveurs$burst';
  }

  @override
  String get jsonCompositionUnknown => 'composition inconnue';

  @override
  String get jsonYourSavedOverride => 'Votre JSON enregistré (remplacement)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'Profil de sélection automatique du panneau : $summary — appliqué intégralement';
  }

  @override
  String get jsonPanelConfig => 'Config du panneau (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'Construit à partir du lien de partage — le panneau n\'a pas envoyé de JSON. Mettez à jour l\'abonnement ; si cela ne suffit pas, vérifiez la règle Response Rules dans le panneau.';

  @override
  String get jsonInvalidJson => 'JSON invalide';

  @override
  String get jsonSaved => 'Enregistré';

  @override
  String get jsonTitle => 'Config JSON';

  @override
  String get jsonFieldEditor => 'Éditeur de champs';

  @override
  String get jsonCopy => 'Copier';

  @override
  String get jsonClose => 'Fermer';

  @override
  String get jsonSave => 'Enregistrer';

  @override
  String get srvTileEdit => 'Modifier';

  @override
  String get srvTileNotice => 'Avis';

  @override
  String get srvTileRefresh => 'Actualiser';

  @override
  String get srvTileSubscriptionUpdated => 'Abonnement mis à jour';

  @override
  String get srvTileCopy => 'Copier';

  @override
  String get srvTileInfo => 'Informations sur le serveur';

  @override
  String get srvTilePing => 'Ping';

  @override
  String get srvTileUnpin => 'Détacher';

  @override
  String get srvTilePin => 'Épingler';

  @override
  String get srvTileJsonConfig => 'Config JSON';

  @override
  String get srvTileSmart => 'Réglage intelligent des paramètres';

  @override
  String get srvTileDelete => 'Supprimer';

  @override
  String get srvTileServerDeleted => 'Serveur supprimé';

  @override
  String get srvTileSaved => 'Enregistré';

  @override
  String get pingNa => 'n/d';

  @override
  String get pingNaTooltip =>
      'Aucune réponse TCP — serveur indisponible (mort)';

  @override
  String get pingTimeout => 'délai dépassé';

  @override
  String get pingTimeoutTooltip =>
      'La sonde TCP ne s\'est pas terminée dans le délai imparti — serveur indisponible';

  @override
  String pingMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get pingNoProxy => 'pas de proxy';

  @override
  String get pingNoProxyTooltip =>
      'Répond en TCP (latence affichée), mais la vérification du tunnel (GET/HEAD) a échoué — le trafic ne passe pas';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip =>
      'Latence TCP vers le serveur. Le serveur fonctionne : il a répondu en TCP et a passé la vérification du tunnel (GET/HEAD)';

  @override
  String get searchHint => 'Rechercher par nom, pays, adresse…';

  @override
  String get searchReset => 'Effacer';

  @override
  String get splitTitle => 'Tunneling fractionné';

  @override
  String get splitTunOnlyBanner =>
      'Fonctionne uniquement en mode TUN. En mode « Proxy système », les applications décident elles-mêmes d\'utiliser ou non le proxy — on ne peut pas les y forcer.';

  @override
  String get splitEnableTun => 'Activer TUN';

  @override
  String get splitModeHeader => 'Mode';

  @override
  String get splitAppsHeader => 'Applications';

  @override
  String get splitAppsHint =>
      'Appuyez sur une application pour définir son action (Tunnel / Direct / Bloquer) et sa méthode de correspondance. La case à gauche active/désactive la règle.';

  @override
  String get splitByName => 'Par nom';

  @override
  String get splitByPath => 'Par chemin';

  @override
  String get splitRuleDisabled => 'Désactivée — la règle n\'est pas appliquée';

  @override
  String get splitRemove => 'Retirer';

  @override
  String get splitFromRunning => 'Depuis les applications en cours';

  @override
  String get splitPickInstalled => 'Choisir une application';

  @override
  String get splitInstalledApps => 'Applications installées';

  @override
  String get splitPickExe => 'Choisir un .exe';

  @override
  String get splitSitesHeader => 'Sites (domaines)';

  @override
  String get splitSitesHint =>
      'Appuyez sur un site pour choisir une action (Tunnel / Direct / Bloquer). Un domaine couvre aussi ses sous-domaines ; les sous-domaines sont regroupés en arborescence. Vous pouvez indiquer un port.';

  @override
  String splitOnlyPort(Object port) {
    return 'port $port uniquement';
  }

  @override
  String get splitProgramsFileType => 'Programmes';

  @override
  String get splitRunningApps => 'Applications en cours d\'exécution';

  @override
  String get splitSearchByName => 'Rechercher par nom';

  @override
  String get splitNothingFound => 'Aucun résultat';

  @override
  String get splitClose => 'Fermer';

  @override
  String get splitPortRange => 'Port 1–65535';

  @override
  String get splitAction => 'Action';

  @override
  String get splitPortOptional => 'Port (facultatif)';

  @override
  String get splitAnyPort => 'tous';

  @override
  String get splitPortHelper =>
      'Vide = n\'importe quel port. Sinon, la règle s\'applique uniquement à ce port';

  @override
  String get splitMatching => 'Correspondance';

  @override
  String get splitByNameSubtitle =>
      'Nom de l\'exe, quel que soit l\'emplacement (fiable)';

  @override
  String get splitByPathSubtitle =>
      'Chemin complet de l\'exe (correspondance exacte)';

  @override
  String get splitDone => 'Terminé';

  @override
  String get splitEnterDomain => 'Saisissez un domaine';

  @override
  String get splitAddSite => 'Ajouter un site';

  @override
  String get splitPort => 'Port';

  @override
  String get splitAdd => 'Ajouter';

  @override
  String get routeBlock => 'Bloquer';

  @override
  String get routeBlocked => 'Bloqué';

  @override
  String get routeYourPc => 'Votre PC';

  @override
  String get routeTunnel => 'Tunnel';

  @override
  String get routeViaVpn => 'Via VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'Internet';

  @override
  String get routeRest => 'Tout le reste';

  @override
  String get routeDirectly => 'Directement';

  @override
  String get routeDirectPlusRest => 'Direct + reste';

  @override
  String get routeDirect => 'Direct';

  @override
  String get routeEmptyList => 'la liste est vide';

  @override
  String get trayShow => 'Afficher';

  @override
  String get trayToggle => 'Connecter / Déconnecter';

  @override
  String get trayQuit => 'Quitter';

  @override
  String get trayMinimizeTitle => 'Réduire dans la zone de notification';

  @override
  String get trayMinimizeBody =>
      'L\'application continuera de fonctionner dans la zone de notification.';

  @override
  String get trayDontAsk => 'Ne plus demander';

  @override
  String get trayMinimizeOk => 'Réduire';

  @override
  String get trayVpnTitle => 'VPN connecté';

  @override
  String get trayVpnBody => 'Déconnecter le VPN et quitter l\'application ?';

  @override
  String get trayStay => 'Rester';

  @override
  String get trayQuitVpn => 'Déconnecter et quitter';

  @override
  String get tunTaskDone => 'Terminé : TUN démarrera sans invite UAC';

  @override
  String get tunTaskFailed =>
      'Échec de la création de la tâche (UAC refusé ou bloqué par une stratégie)';

  @override
  String get tunLogTitle => 'Journal TUN (sing-box)';

  @override
  String get tunLogEmpty =>
      'Le journal est vide — le tunnel n\'a pas encore démarré.';

  @override
  String get tunCopy => 'Copier';

  @override
  String get tunClose => 'Fermer';

  @override
  String get tunTitle => 'TUN et routage';

  @override
  String get tunSectionPrivilege => 'Droits administrateur';

  @override
  String get tunChecking => 'Vérification…';

  @override
  String get tunNoUacConfigured => 'Le démarrage sans UAC est configuré';

  @override
  String get tunUacEachConnect => 'L\'UAC sera demandé à chaque connexion';

  @override
  String get tunTaskSubtitle =>
      'Une tâche du Planificateur de tâches Windows avec les privilèges les plus élevés (créée une seule fois).';

  @override
  String get tunRecreateTask => 'Recréer la tâche';

  @override
  String get tunSetupOneUac => 'Configurer (un seul UAC)';

  @override
  String get tunRemoveTask => 'Supprimer la tâche';

  @override
  String get tunSectionAdapter => 'Adaptateur';

  @override
  String get tunStack => 'Pile TUN';

  @override
  String get tunSectionRouting => 'Routage';

  @override
  String get tunStrictRoute => 'Routage strict (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 dans le tunnel';

  @override
  String get tunEndpointNat =>
      'NAT indépendant du point de terminaison (UDP, jeux)';

  @override
  String get tunLanBypass => 'Le réseau local contourne le VPN';

  @override
  String get tunDnsServer => 'Serveur DNS';

  @override
  String get tunDnsHijack => 'Intercepter le DNS (port 53)';

  @override
  String get tunResolveStrategy => 'Stratégie de résolution';

  @override
  String get tunSectionDiagnostics => 'Diagnostic';

  @override
  String get tunSingboxLogLevel => 'Niveau de journal de sing-box';

  @override
  String get tunShowLog => 'Afficher le journal TUN';

  @override
  String get tunDnsVpn => 'Via VPN (recommandé)';

  @override
  String get tunDnsSystem => 'Système';

  @override
  String get tunDnsCustom => 'Serveur personnalisé';

  @override
  String get tunDnsVpnHint =>
      'Les requêtes passent dans le tunnel via TCP — aucune fuite';

  @override
  String get tunDnsSystemHint => 'Comme Windows : fuite DNS possible';

  @override
  String get tunDnsCustomHint => 'Le serveur indiqué, également via le tunnel';

  @override
  String get tunExcludeSubnets => 'Sous-réseaux contournant le VPN';

  @override
  String get tunAdd => 'Ajouter';

  @override
  String get urlGroupImport => 'Importer';

  @override
  String get urlGroupControl => 'Contrôle';

  @override
  String get urlHintSubUrl => 'URL d\'abonnement';

  @override
  String get urlHintServerLink => 'lien de serveur';

  @override
  String get urlDescImportSub => 'Importer un abonnement';

  @override
  String get urlDescImportServer =>
      'Ajouter un seul serveur (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'Connecter le VPN';

  @override
  String get urlDescDisconnect => 'Déconnecter le VPN';

  @override
  String get urlDescToggle => 'Basculer le VPN';

  @override
  String get urlDescUpdate => 'Actualiser l\'abonnement actif';

  @override
  String get urlSupportedImport =>
      'À l\'import, l\'application comprend : une URL d\'abonnement (http/https), et des serveurs uniques vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — rapport d\'assistance';

  @override
  String get reportDescribeHere =>
      '>>> DÉCRIVEZ LE PROBLÈME ICI (remplissez et enregistrez le fichier) : <<<';

  @override
  String get reportWhatDid => 'Ce que vous avez fait :';

  @override
  String get reportWhatExpected => 'Ce que vous attendiez :';

  @override
  String get reportWhatHappened => 'Ce qui s\'est passé :';

  @override
  String get reportWhenStarted => 'Quand cela a commencé :';

  @override
  String get reportTechNoticeLine1 =>
      'Ci-dessous, des informations techniques. Vérifiez-les avant l\'envoi ;';

  @override
  String get reportTechNoticeLine2 =>
      'il n\'y a ici ni mot de passe ni jeton d\'abonnement, l\'URL d\'abonnement est masquée.';

  @override
  String get noRealIpTitle => 'Ne jamais utiliser ma vraie IP';

  @override
  String get noRealIpSub =>
      'Même avec le VPN actif, tout le trafic « direct » passe par le VPN (sites RU compris). Le réseau local reste direct.';

  @override
  String get flagAuto => 'AUTO';

  @override
  String get autoUpdateIntervalLabel => 'Intervalle de mise à jour, h';

  @override
  String get autoUpdatePreferSub => 'Utiliser l\'intervalle de l\'abonnement';

  @override
  String get pingLegendInfo =>
      'Couleur du badge de ping : vert/jaune/orange — le serveur fonctionne (TCP + vérification via le tunnel). Gris — répond en TCP mais ne relaie pas le trafic (port Reality typique). Rouge « n/a » — aucune réponse, exclu. Le ping est toujours mesuré DIRECTEMENT (hors VPN).';

  @override
  String get pingUntestedHint =>
      'Pas encore testé. Sur mobile, Hysteria2 et les profils « Auto » ne sont mesurés que connecté.';

  @override
  String get panelTunnelMarker => 'Tunnel divisé propre';

  @override
  String panelInfoServers(Object n) {
    return 'Serveurs dans le profil : $n (le meilleur est choisi)';
  }

  @override
  String get panelInfoDirect =>
      'Une partie du trafic (ex. sites locaux) passe en direct, hors VPN';

  @override
  String get panelInfoBlock =>
      'Une partie du trafic est bloquée (pubs/torrents)';

  @override
  String get serviceChecksTitle => 'Vérifier les services';

  @override
  String get serviceChecksInfo =>
      'Six services populaires sont vérifiés automatiquement : d\'abord au démarrage de l\'application, VPN éteint, puis de nouveau juste après la connexion. Les deux points montrent « avant → après », pour voir ce que le VPN a réellement changé. Touchez pour revérifier. Vert : accessible ; orange : blocage régional ; rouge : injoignable.';

  @override
  String get serviceStatusOk => 'Fonctionne';

  @override
  String get serviceStatusGeo => 'S\'ouvre, mais bloqué dans le pays de sortie';

  @override
  String get serviceStatusFail => 'Ne s\'ouvre pas';

  @override
  String get serviceStatusChecking => 'Vérification…';

  @override
  String get serviceStatusTap => 'Touchez pour vérifier';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get homeTunAutotuneProgress => 'Réglage des paramètres TUN…';

  @override
  String get homeTunAutotuneDone => 'Paramètres TUN réglés';

  @override
  String get homeTunAutotuneFailed => 'Impossible de régler les paramètres TUN';

  @override
  String get hy2NoteTitle => 'Serveurs Hysteria2';

  @override
  String get hy2NoteBody =>
      'Les serveurs Hysteria2 n\'arrivent qu\'au format XRAY_JSON — SilentGate demande précisément celui-ci, et sing-box les lance automatiquement. Si Hysteria2 n\'apparaît pas dans la liste : (pour le propriétaire du panneau Remnawave) activez les inbounds hysteria et affectez-les à l\'abonnement. Remarque : avant 2.8.0, Remnawave fournit Hysteria2 UNIQUEMENT en XRAY_JSON — absent de base64/CLASH/SINGBOX, donc la règle Response Rules → XRAY_JSON ci-dessus est obligatoire.';

  @override
  String get enumStatusDisconnected => 'Déconnecté';

  @override
  String get enumStatusConnecting => 'Connexion…';

  @override
  String get enumStatusConnected => 'Connecté';

  @override
  String get enumStatusDisconnecting => 'Déconnexion…';

  @override
  String get enumStatusError => 'Erreur';

  @override
  String get enumVariantPlain => 'standard';

  @override
  String get tagAutoSelect => 'AUTO';

  @override
  String get tagPanel => 'PANNEAU';

  @override
  String get tagPortHopping => 'SAUT DE PORTS';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count serveurs',
      one: '$count serveur',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'aucun changement';

  @override
  String get errInvalidJson => 'JSON non valide';

  @override
  String get errPickServerFirst => 'Sélectionnez d’abord un serveur';

  @override
  String get errImportSubscriptionFirst => 'Importez d’abord un abonnement';

  @override
  String get speedSizeFull => '20 Mo';

  @override
  String get speedSizeLight => '5 Mo';

  @override
  String speedMbPerSec(String value) {
    return '$value Mo/s';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value Ko/s';
  }

  @override
  String portBusyTitle(int port, String by) {
    return 'Le port $port est déjà utilisé par $by.';
  }

  @override
  String get srvTileMenu => 'Actions du serveur';

  @override
  String get supportCopyReport => 'Copier le rapport';

  @override
  String get supportReportCopied =>
      'Rapport copié — collez-le dans le chat du support';

  @override
  String subBarUsedOnly(String used) {
    return 'Utilisé $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'trafic illimité';

  @override
  String get supportDescribeLabel => 'Décrivez le problème';

  @override
  String get supportDescribeHint =>
      'Ce que vous faisiez, ce que vous attendiez, ce qui s’est passé et quand cela a commencé';

  @override
  String get supportDescribeRequired =>
      'Décrivez le problème — sans description le rapport est inutile';

  @override
  String get supportNoScreenshots =>
      'Ne collez pas de captures ici — envoyez-les dans un message séparé sur le chat Telegram.';

  @override
  String get supportDescriptionSection => 'DESCRIPTION DE L’UTILISATEUR';

  @override
  String get splitAllowRealIp => 'Autoriser l’IP réelle pour cette règle';

  @override
  String get splitAllowRealIpOn =>
      'Cochée : c’est une exception, le trafic sortira avec votre adresse réelle';

  @override
  String get splitAllowRealIpOff =>
      'Décochée : la règle passe par le VPN — la protection prime sur tout';

  @override
  String get splitRealIpExposed => 'IP réelle';

  @override
  String get splitRealIpProtected => 'via VPN';

  @override
  String get vpnActiveBadge => 'VPN actif';

  @override
  String get splitCopyDomain => 'Copier l’adresse';

  @override
  String get splitCopyPath => 'Copier le chemin';

  @override
  String get homeServerInfo => 'Infos du serveur';

  @override
  String get serverInfoVerifyInBrowser => 'Vérifier dans le navigateur';

  @override
  String get tunDnsForAll => 'DNS de toutes les apps via le VPN';

  @override
  String get infoDnsForAll =>
      'Uniquement en mode « Seulement sélectionnées ». ⚠️ Appliqué après reconnexion.';

  @override
  String get homeSettingsNeedReconnect =>
      'Paramètre modifié — reconnectez-vous pour appliquer';

  @override
  String blockPageWindowTitle(String app) {
    return 'Bloqué — $app';
  }

  @override
  String get blockPageHeading => 'Site bloqué';

  @override
  String blockPageBody(String host, String app) {
    return '$host est bloqué par une règle de tunnel partagé dans $app.';
  }

  @override
  String get blockPageHint =>
      'Vous pouvez modifier la règle : Paramètres → Tunnel partagé → Sites.';

  @override
  String get blockPageNote =>
      'Cette page provient de l\'application elle-même, ce n\'est pas une erreur réseau. Le site ne s\'ouvre pas parce que vous l\'avez ajouté à la liste de blocage.';

  @override
  String get settingsBlockPage => 'Page d’information de blocage';

  @override
  String get settingsBlockPageSub =>
      'Au lieu d\'une erreur de connexion, une page explique quelle règle a fermé le site. Fonctionne uniquement en http : une page https ne peut pas être remplacée sans installer notre propre certificat racine dans le système, et ce certificat permettrait de lire tout votre trafic chiffré.';

  @override
  String get trayCloseFully => 'Fermer complètement';

  @override
  String errorVpnConflictApp(String app) {
    return '$app semble gêner : son propre tunnel VPN est actif. Deux tunnels simultanés se disputent la route par défaut.';
  }

  @override
  String errorCloseApp(String app) {
    return 'Fermer $app';
  }

  @override
  String toastAppClosed(String app) {
    return '$app fermé';
  }

  @override
  String toastAppCloseFailed(String app) {
    return 'Impossible de fermer $app — fermez-le manuellement';
  }

  @override
  String get tunBlockQuic => 'Bloquer QUIC (HTTP/3)';

  @override
  String get infoBlockQuic =>
      'Les règles de sites portent sur le NOM, et l\'application ne voit ce nom qu\'en TLS ordinaire. Un navigateur passé en HTTP/3 ne montre pas de nom : la règle de domaine ne fait alors rien, silencieusement. Le blocage ramène le navigateur vers une connexion normale où le nom est visible. Les sites continuent de fonctionner : HTTP/3 est facultatif, même si la vidéo peut charger un peu plus lentement.';

  @override
  String get tunBlockEncryptedDns => 'Bloquer le DNS chiffré (DoH/DoT)';

  @override
  String get infoBlockEncryptedDns =>
      'Les navigateurs et Windows peuvent résoudre les adresses via HTTPS, contournant notre interception. Les règles « Direct » et « Bloquer » ne fonctionnent alors plus au niveau DNS. ⚠️ Si un fournisseur de DNS chiffré est imposé dans le navigateur, celui-ci ne reviendra pas au DNS classique : il cessera simplement d\'ouvrir les sites. La liste des fournisseurs connus est par nature incomplète.';

  @override
  String get autoUseSpeed => 'Tenir compte du débit';

  @override
  String get infoAutoUseSpeed =>
      'Après le tri par services et latence, les trois meilleurs candidats sont testés par téléchargement et le plus rapide passe en tête. Le débit est comparé à VOTRE connexion : un serveur qui en restitue déjà presque tout n\'est plus jugé aux mégabits, c\'est la latence qui décide. ⚠️ Consomme du trafic d\'abonnement : 5 Mo pour votre connexion plus 5 Mo par candidat, environ 20 Mo par passage.';

  @override
  String get autoSpeedOwn => 'Mesure de votre propre débit…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'Mesure du débit : $server ($index sur $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent % de votre connexion';
  }

  @override
  String get conflictDialogTitle => 'Autre VPN détecté';

  @override
  String conflictDialogBody(String app) {
    return '$app semble fonctionner avec son propre tunnel actif. Deux tunnels simultanés se disputent la route par défaut : la connexion peut échouer ou s\'établir sans accès au réseau.';
  }

  @override
  String get conflictCloseAndConnect => 'Fermer et connecter';

  @override
  String get conflictConnectAnyway => 'Se connecter quand même';

  @override
  String get serviceChecksLegendBefore => 'Disponibilité vérifiée sans VPN';

  @override
  String get serviceChecksLegendAfter =>
      'À gauche — sans VPN, à droite — via le VPN';

  @override
  String get serviceChecksBefore => 'Sans VPN';

  @override
  String get serviceChecksAfter => 'Via le VPN';

  @override
  String get serviceChecksNoBaseline => 'Non vérifié sans VPN';

  @override
  String autoSpeedValue(String value) {
    return '$value Mbit/s';
  }

  @override
  String get splitShowBlockPage => 'Afficher la page de blocage';

  @override
  String get splitBlockPageNeedsVpn =>
      'La page de blocage ne fonctionne que si le VPN est actif';

  @override
  String get srvInfoNeedsConnection =>
      'Sur cette plateforme, la mesure via le serveur nécessite que le VPN soit actif';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ Ce test ne voit pas le bridage de YouTube : le fournisseur répond normalement mais limite le débit vidéo. Vert signifie « service joignable », pas « la vidéo se lit ».';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<nom du serveur>';

  @override
  String get urlDescConnectServer =>
      'Se connecter à un serveur PRÉCIS. Le nom est celui affiché dans la liste et envoyé par l’abonnement, par ex. « Pologne 1.5 ». Les emoji drapeau et la casse sont facultatifs. Sans correspondance exacte, la recherche prend le relais : pays, adresse ou protocole. Fonctionne aussi avec toggle.';

  @override
  String get splitSelectAllFound => 'Tout sélectionner';

  @override
  String splitAddSelected(int count) {
    return 'Ajouter ($count)';
  }

  @override
  String get splitQuicNote =>
      'Tant qu\'il existe au moins une règle de site, l\'application désactive HTTP/3 (QUIC) pour tout le trafic. Sinon le navigateur passe en HTTP/3, ne laisse pas le nom du site et la règle échoue silencieusement. Les sites continuent de fonctionner : ils reviennent au TLS classique, un peu plus lentement.';

  @override
  String get splitNoRealIpBanner =>
      '« Ne jamais utiliser mon IP réelle » est actif : les règles « Direct » sans la case cochée passent par le VPN';

  @override
  String get settingsNoRealIpAffects =>
      'Concerne les règles « Direct » : sans la case « autoriser l’IP réelle », elles passent par le VPN';

  @override
  String get splitAppOverrideSites => 'Prioritaire sur les règles de sites';

  @override
  String get splitAppOverrideSitesSub =>
      'Tout le trafic de l’application suit cette règle, même si un site indique le contraire';

  @override
  String get settingsMyRulesOverridePanel =>
      'Mes règles priment sur celles du panneau';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'Le panneau fournit son propre routage, en général « les sites locaux évitent le VPN ». Il s’applique après vos règles : un site marqué « Tunnel » peut donc sortir en direct avec votre IP réelle. Activé : tunnel veut dire tunnel. Coût : les sites locaux font un détour et ralentissent.';

  @override
  String get commonOpen => 'Ouvrir';

  @override
  String get tunRouteOnlySubnets =>
      'UNIQUEMENT ces sous-réseaux dans le tunnel';

  @override
  String get infoTunRouteOnlyCidrs =>
      'Le seul moyen, sous Windows, de rendre une partie du trafic réellement indépendante du client VPN.\n\nNormalement, le tunnel s\'empare de la route par défaut et TOUT le trafic de la machine y entre : la marque « Direct » est traitée à l\'intérieur du cœur, qui reçoit le paquet et le renvoie vers l\'extérieur en son propre nom. Ce trafic ne vit que tant que le cœur vit, et se fige en même temps que lui.\n\nSi la liste n\'est pas vide, la route par défaut n\'est pas donnée au tunnel : il ne prend que les sous-réseaux indiqués, et le système envoie tout le reste par l\'adaptateur habituel — le client ne voit pas du tout ce trafic.\n\nLe prix à payer : le partage se fait par adresse, alors que les règles d\'applications et de sites fonctionnent par nom. Un site dont l\'adresse n\'est pas dans la liste reste invisible pour toutes les règles. Laissez vide pour que le tunnel fonctionne comme d\'habitude.';

  @override
  String get tunRouteOnlyWarning =>
      'Le tunnel ne prend que les sous-réseaux indiqués. Les règles d\'applications et de sites n\'agissent QUE dans ces sous-réseaux : ce qui n\'entre pas dans le tunnel n\'est jamais montré au cœur — impossible de bloquer ou de rediriger un tel site.';

  @override
  String get tunAlsoSystemProxy => 'Proxy système en plus du tunnel';

  @override
  String get infoTunAlsoSystemProxy =>
      'Mode mixte : le tunnel et le proxy système fonctionnent en même temps.\n\nLes applications qui respectent le proxy système (navigateurs, Telegram) prennent le chemin court directement vers le port local, sans passer par la pile en espace utilisateur du tunnel, et transmettent au cœur un nom de domaine au lieu d\'une simple adresse — les règles de sites deviennent plus précises pour elles et cessent de dépendre de l\'analyse TLS.\n\nElles ne deviennent PAS pour autant indépendantes du client : elles passent toujours par le même processus.';

  @override
  String get tunMixedModeWarning =>
      'Une connexion arrivée par le proxy système n\'a pas de processus propriétaire — pour le cœur, c\'est une connexion locale. Les règles D\'APPLICATIONS ne s\'appliquent donc pas à ces programmes. Les règles de sites, elles, fonctionnent, et même plus précisément que d\'habitude.';

  @override
  String get tunWatchdog => 'Surveillance du cœur bloqué';

  @override
  String get infoTunWatchdog =>
      'Pendant combien de secondes le cœur du tunnel peut rester silencieux avant d\'être considéré comme bloqué et le tunnel coupé.\n\nSi le cœur plante, Windows fait le ménage lui-même — l\'adaptateur, les routes et les règles du pare-feu sont retirés, le réseau revient. Si le cœur se fige, rien n\'est retiré : l\'adaptateur reste en place et avale tout le trafic de la machine, y compris celui marqué « Direct ». Vu de l\'extérieur, c\'est « il n\'y a plus du tout d\'Internet », et cela ne se rétablit jamais tout seul.\n\nLa surveillance ne s\'arme qu\'après la première réponse réussie du cœur : sinon elle couperait la connexion partout où le port de service n\'a pas pu s\'ouvrir. 0 — ne pas surveiller. Minimum 10 secondes.';

  @override
  String get tunWatchdogOff =>
      'Désactivée : un tunnel bloqué ne sera pas détecté';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'Couper le tunnel si le cœur reste silencieux plus de $seconds s';
  }

  @override
  String get tunDnsForAllWarning =>
      'La résolution des noms de TOUTE la machine passera par le tunnel. Si le tunnel se fige, les noms cessent d\'être résolus même pour les applications qui passent en direct et n\'ont pas besoin du VPN — vu de l\'extérieur, cela ressemble à une perte totale d\'Internet.';

  @override
  String get tunCidrInvalid =>
      'Il faut une adresse avec un préfixe, par ex. 10.8.0.0/24';

  @override
  String get geoTitle => 'Bases géo de routage';

  @override
  String get geoMissing =>
      'Non téléchargées — les règles par pays et catégorie ne s\'appliquent pas';

  @override
  String geoPresent(String size, String date) {
    return '$size, mise à jour : $date';
  }

  @override
  String get geoDownload => 'Télécharger';

  @override
  String get geoUpdate => 'Mettre à jour';

  @override
  String geoDownloading(String file) {
    return 'Téléchargement de $file…';
  }

  @override
  String get geoDone => 'Bases géo mises à jour';

  @override
  String geoFailed(String error) {
    return 'Échec du téléchargement : $error';
  }

  @override
  String get infoGeoAssets =>
      'Les fichiers geoip.dat et geosite.dat sont des listes d\'adresses par pays et de domaines par catégorie (par exemple « sites russes », « services publics », « VK »). Les règles de routage définies par le panneau de votre abonnement s\'appuient sur eux.\n\nIls ne sont pas intégrés à l\'application : à eux deux, ils pèsent environ 30 MB, et tout le monde n\'en a pas besoin — un serveur ordinaire ne les utilise pas du tout.\n\nTant que les fichiers sont absents, ces règles sont retirées de la configuration, et le trafic qu\'elles faisaient passer en direct emprunte le VPN. C\'est sûr, mais plus lent, et les sites locaux peuvent refuser l\'accès depuis une adresse étrangère. Vos règles de sites et d\'applications, elles, fonctionnent dans tous les cas — elles ne dépendent pas de ces fichiers.';

  @override
  String get supportBullet2Android =>
      '• Après l\'appui, le rapport sera rassemblé dans un seul fichier et la fenêtre système « Partager » s\'ouvrira — choisissez Telegram et il partira en une seule pièce jointe. Décrivez le problème dans le champ ci-dessus : sans description, il n\'y a rien à analyser.';

  @override
  String get supportDoneTextAndroid =>
      'Le rapport est rassemblé dans un seul fichier. Choisissez dans la fenêtre système où l\'envoyer — sur Telegram il partira en pièce jointe, et non en texte.';

  @override
  String get exitsHeader => 'Sorties';

  @override
  String get exitsHint =>
      'Une règle « Tunnel » peut être dirigée vers une sortie précise : un site via l’Allemagne, un autre via les États-Unis. Sans sortie, la règle emprunte le tunnel principal, comme avant.';

  @override
  String get exitsAdd => 'Ajouter une sortie';

  @override
  String get exitsEmpty => 'Aucune sortie pour l’instant';

  @override
  String get exitsName => 'Nom';

  @override
  String get exitsNameHint => 'Allemagne';

  @override
  String get exitsServers => 'Serveurs';

  @override
  String get exitsAutoSelect => 'Sélection automatique par latence';

  @override
  String get exitsAutoSelectSub =>
      'Le cœur maintient le trafic sur un serveur actif. Le coût : chaque serveur est sondé toutes les trois minutes, ce qui réveille la radio du téléphone.';

  @override
  String get exitsAutoSelectNeedsTwo =>
      'Au moins deux serveurs sont nécessaires';

  @override
  String get exitsDelete => 'Supprimer la sortie';

  @override
  String get exitsNoServers => 'Aucun serveur — importez d’abord un abonnement';

  @override
  String get exitsSearch => 'Rechercher un serveur';

  @override
  String get exitsPickAtLeastOne => 'Sélectionnez au moins un serveur';

  @override
  String get exitsUnsupportedNote =>
      'Les profils « Auto » du panneau et hysteria2 ne peuvent pas servir de sortie séparée : ils dépendent de l’autre cœur. Ces serveurs sont désactivés dans la liste.';

  @override
  String get infoExits =>
      'Une sortie est la destination d’une règle « Tunnel ».\n\nPar défaut, une sortie est UN seul serveur et ne coûte rien en arrière-plan : les protocoles ordinaires ne maintiennent pas de connexion permanente. Un groupe de plusieurs serveurs avec sélection automatique n’est utile que si la tolérance à la panne d’un nœud importe : elle ajoute des sondages périodiques, et sur téléphone ce sont des réveils radio.\n\nLa sortie n’a de sens qu’avec l’action « Tunnel ». « Direct via l’Allemagne » est une contradiction : une règle directe contourne toutes les sorties.\n\nUn site et son sous-domaine peuvent aller vers des sorties DIFFÉRENTES — l’application place la règle la plus précise au-dessus, sinon le parent absorberait le sous-domaine.\n\nIMPORTANT : avec le proxy système sous Windows, les sorties ne fonctionnent pas — aucune règle de routage n’y est construite. Le mode tunnel est nécessaire.';

  @override
  String get ruleServer => 'Via le serveur';

  @override
  String get ruleServerCurrent => 'Comme le principal';

  @override
  String ruleServerCurrentNamed(String server) {
    return 'Comme le principal ($server)';
  }

  @override
  String get routeMatchByName => 'Correspondance par nom de fichier';

  @override
  String get routeYourApps => 'Vos applications';

  @override
  String get routeYourSites => 'Vos sites';

  @override
  String get routeAppsAndSites => 'Applications et sites';

  @override
  String get notifCompactTitle => 'Notification compacte';

  @override
  String get notifCompactSub =>
      'Désactivé — abonnement, serveur et vitesse, avec les boutons. Activé — l\'application et l\'abonnement dans le titre, le serveur en dessous, sans la vitesse ni les boutons.';

  @override
  String get localProxyAuthTitle => 'Mot de passe du proxy local';

  @override
  String get localProxyAuthInfo =>
      'Le port local du cœur (127.0.0.1) est un vrai proxy vers votre VPN. Sans mot de passe, n\'importe quel programme du même appareil s\'y connecte et récupère tout votre tunnel : l\'IP de sortie, le quota de l\'abonnement et le contournement de vos propres règles de tunneling fractionné — y compris les applications que vous avez mises sur « Bloquer ». Sur Android, c\'est encore plus important : là-bas, toute application installée voit les ports locaux.\n\nNe le désactivez que si vous utilisez sciemment ce proxy avec un programme qui ne gère pas l\'authentification.';

  @override
  String get localProxyAuthOff =>
      'Désactivé : le proxy local est ouvert à tout programme de l\'appareil';

  @override
  String get localProxyAuthSystemProxy =>
      'Sans effet en mode proxy système : Windows ne sait pas transmettre de mot de passe au proxy local. Actif en mode TUN.';

  @override
  String get localProxyAuthRandom =>
      'Un nouveau mot de passe aléatoire à chaque connexion — il n\'est enregistré nulle part';

  @override
  String get localProxyAuthCustom =>
      'Identifiant et mot de passe personnalisés (stockés dans le fichier de paramètres)';

  @override
  String get localProxyCredsTitle =>
      'Identifiant et mot de passe personnalisés';

  @override
  String get localProxyCredsUnset =>
      'Non définis — un mot de passe aléatoire est utilisé';

  @override
  String localProxyCredsUser(String user) {
    return 'Identifiant : $user';
  }

  @override
  String get localProxyDialogTitle =>
      'Identifiant et mot de passe du proxy local';

  @override
  String get localProxyDialogBody =>
      'Nécessaires uniquement si vous indiquez vous-même notre proxy (127.0.0.1) dans un programme tiers. Laissez les champs vides et le mot de passe sera aléatoire à chaque connexion : il n\'est enregistré nulle part et ne se retrouve pas dans les sauvegardes.';

  @override
  String get localProxyFieldUser => 'Identifiant';

  @override
  String get localProxyFieldPassword => 'Mot de passe';

  @override
  String get localProxyFieldHint => 'vide — aléatoire';

  @override
  String get lockdownOnTitle => 'Protection système activée';

  @override
  String get lockdownOnSub =>
      'Le trafic est bloqué même si l\'application se ferme ou si le système la décharge. C\'est le mode le plus fiable.';

  @override
  String get lockdownHalfTitle => 'Protection à moitié activée';

  @override
  String get lockdownHalfSub =>
      'Le VPN permanent est activé, mais « Bloquer les connexions sans VPN » est désactivé. Tant que l\'application vit, le trafic est protégé ; si le système la décharge, il passera en clair.';

  @override
  String get lockdownOffTitle => 'Protection système désactivée';

  @override
  String get lockdownOffSub =>
      'Notre kill switch retient le trafic tant que l\'application tourne. Si le système la décharge, le trafic passera hors VPN. Activez « VPN permanent » et « Bloquer les connexions sans VPN ».';

  @override
  String get lockdownUnknownTitle => 'Protection système : état inconnu';

  @override
  String get lockdownUnknownSub =>
      'L\'état n\'est lisible qu\'à partir d\'Android 10 et seulement quand le tunnel est actif. Vérifiez manuellement : « VPN permanent » et « Bloquer les connexions sans VPN ».';

  @override
  String get lockdownOpenFailed =>
      'Impossible d\'ouvrir les paramètres VPN du système. Trouvez-les manuellement : Paramètres → Réseau et Internet → VPN.';

  @override
  String get blockNoticeTitle => 'Signaler les sites bloqués';

  @override
  String get blockNoticeSub =>
      'Quand une application ou un navigateur essaie d\'atteindre un site de la liste « Bloquer », une notification avec son nom apparaît en bas. Appuyez dessus pour ouvrir cet écran.';

  @override
  String get siteInsecureScheme =>
      'L\'adresse est saisie en http:// — la connexion n\'est pas chiffrée et votre FAI la voit entièrement. Retirez « http:// » pour que le navigateur passe en https.';

  @override
  String get exitServerGone =>
      'Le serveur de cette règle a disparu de l\'abonnement — le trafic emprunte le tunnel principal';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\nCe serveur ne peut pas servir de sortie séparée : les profils « Auto » du panneau et une partie des protocoles ne sont gérés que par Xray, alors que les sorties sont réparties par sing-box. Le trafic de la règle emprunte le tunnel principal.';
  }

  @override
  String get noticeRulesAction => 'Règles';

  @override
  String get geoVerdictMissingTitle => 'Bases géo non téléchargées';

  @override
  String get geoVerdictMissingSub =>
      'Les règles de l\'abonnement par pays et par catégorie sont désactivées — ce trafic passe par le VPN et non en direct.';

  @override
  String get geoVerdictUnusableTitle => 'Le cœur n\'a pas ouvert les bases géo';

  @override
  String get geoVerdictUnusableSub =>
      'Les fichiers sont là, mais le cœur ne les a pas lus. Retélécharger les bases aide généralement.';
}
