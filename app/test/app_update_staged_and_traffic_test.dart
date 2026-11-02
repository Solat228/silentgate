import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/update_installer_fake.dart';
import 'package:silentgate/core/update/update_manifest.dart';
import 'package:silentgate/core/update/update_signature.dart';
import 'package:silentgate/state/app_update_controller.dart';

void main() {
  final seed = List<int>.generate(32, (i) => (i * 29 + 7) & 0xff);
  final publicKey =
      base64.encode(ed.public(ed.newKeyFromSeed(Uint8List.fromList(seed))).bytes);

  late Directory tempRoot;
  late Directory stagingDir;
  late AppSettings currentSettings;
  late Map<String, List<int>> networkRoutes;
  late int downloadCalls;

  AppRelease buildRelease(
    String version, {
    bool beta = true,
    String host = 'https://updates.example',
  }) {
    final name = 'SilentGateSetup-$version.exe';
    final body =
        List<int>.generate(2048, (i) => (i * 73 + version.codeUnitAt(0)) & 0xff);
    final manifest = UpdateManifest(
      version: version,
      channel: beta ? UpdateManifest.channelBeta : UpdateManifest.channelStable,
      assets: [
        UpdateAsset(name: name, size: body.length, sha256: Sha256.ofBytes(body)),
      ],
    );
    final manifestBytes = utf8.encode(manifest.toJson());
    networkRoutes['$host/$name'] = body;
    networkRoutes['$host/m-$version.json'] = manifestBytes;
    networkRoutes['$host/m-$version.sig'] =
        utf8.encode(UpdateSignature.sign(manifestBytes, seed));
    return AppRelease(
      version: version,
      notes: 'Beta notes',
      isBeta: beta,
      pageUrl: '$host/releases/$version',
      downloadUrl: '$host/$name',
      assetName: name,
      assetSize: body.length,
      manifestUrl: '$host/m-$version.json',
      signatureUrl: '$host/m-$version.sig',
    );
  }

  AppUpdateController makeController({
    required Future<UpdateCheckResult> Function({required bool beta}) checker,
    Future<UpdateCheckResult> Function({
      required bool beta,
      required UpdateProxy proxy,
    })? proxyChecker,
    Future<AppRelease?> Function({
      required bool beta,
      required String version,
    })? mirror,
    bool Function()? isVpnActive,
    UpdateProxy? Function()? vpnProxyOf,
    Duration? installStuckTimeout,
    String currentVersion = '1.15.2',
  }) {
    final installer = FakeUpdateInstaller(staging: stagingDir);
    return AppUpdateController(
      settings: () => currentSettings,
      updateSettings: (m) async {
        currentSettings = m(currentSettings);
      },
      installer: installer,
      checker: checker,
      proxyChecker: proxyChecker,
      mirror: mirror ?? ({required bool beta, required String version}) async => null,
      fetchBytes: (url, {required int maxBytes, client}) async {
        final b = networkRoutes[url.toString()];
        if (b == null) throw SocketException('blocked: $url');
        return b;
      },
      downloader: (url, target,
          {expectedSize, expectedSha256, onProgress, client, maxBytes = 0}) async {
        downloadCalls++;
        final b = networkRoutes[url.toString()];
        if (b == null) throw SocketException('blocked: $url');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(b, flush: true);
        return target.path;
      },
      isVpnActive: isVpnActive ?? () => false,
      vpnProxyOf: vpnProxyOf,
      publicKeyBase64: publicKey,
      currentVersion: currentVersion,
      installStuckTimeout: installStuckTimeout,
    );
  }

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sg_staged_upd_');
    stagingDir = Directory('${tempRoot.path}${Platform.pathSeparator}updates');
    currentSettings = const AppSettings(
      betaChannel: true,
      appUpdateMode: AppUpdateMode.ask,
    );
    networkRoutes = {};
    downloadCalls = 0;
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Staged update persistence across app restarts', () {
    test('downloaded beta stays UpdatePhase.ready after restart even when GitHub & mirror are offline', () async {
      final betaRelease = buildRelease('1.16.0-beta.1', beta: true);

      // Session 1: user downloads beta update, then closes app without pressing Install.
      final c1 = makeController(
        checker: ({required bool beta}) async =>
            UpdateCheckResult.available(betaRelease),
      );
      await c1.startup();
      expect(c1.phase, UpdatePhase.available);
      await c1.download();
      expect(c1.phase, UpdatePhase.ready);
      expect(downloadCalls, 1);
      c1.dispose();

      // Session 2: app restarts while both GitHub and silentgate.lol are unreachable.
      final c2 = makeController(
        checker: ({required bool beta}) async =>
            const UpdateCheckResult.failed('GitHub blocked'),
      );
      await c2.startup();
      expect(c2.phase, UpdatePhase.ready,
          reason: 'verified staged beta must survive restart and offline check');
      expect(c2.restoredFromStaging, isTrue);
      expect(c2.offer?.version, '1.16.0-beta.1');
      expect(downloadCalls, 1, reason: 'must not re-download verified installer');
      c2.dispose();
    });

    test('corrupted staged binary is rejected on startup and cleaned up', () async {
      final betaRelease = buildRelease('1.16.0-beta.1', beta: true);
      final c1 = makeController(
        checker: ({required bool beta}) async =>
            UpdateCheckResult.available(betaRelease),
      );
      await c1.startup();
      await c1.download();
      final stagedFile = c1.downloadedFile!;
      c1.dispose();

      // Tamper with staged file on disk before restart.
      final bytes = stagedFile.readAsBytesSync();
      bytes[0] ^= 0xff;
      stagedFile.writeAsBytesSync(bytes, flush: true);

      final c2 = makeController(
        checker: ({required bool beta}) async =>
            const UpdateCheckResult.failed('offline'),
      );
      await c2.startup();
      expect(c2.phase, isNot(UpdatePhase.ready));
      expect(c2.restoredFromStaging, isFalse);
      c2.dispose();
    });

    test('recoverFromInstalling unsticks UpdatePhase.installing back to ready', () async {
      final betaRelease = buildRelease('1.16.0-beta.1', beta: true);
      final c = makeController(
        checker: ({required bool beta}) async =>
            UpdateCheckResult.available(betaRelease),
        installStuckTimeout: const Duration(milliseconds: 60),
      );
      await c.startup();
      await c.download();
      await c.install();
      expect(c.phase, UpdatePhase.installing);

      // Watchdog or manual cancel recovers back to ready while staged file exists.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(c.phase, UpdatePhase.ready);
      c.dispose();
    });
  });

  group('Dual source fallback & VPN subscription traffic warning', () {
    test('AppUpdate.check falls back to silentgate.lol when github.com atom opens but release assets are blocked', () async {
      const atomXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>tag:github.com,2008:Repository/1/v99.0.0-beta.2</id>
    <updated>2026-11-02T10:00:00Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/SilentGate/SilentGate/releases/tag/v99.0.0-beta.2"/>
    <title>v99.0.0-beta.2</title>
    <content type="html">&lt;p&gt;Fixes&lt;/p&gt;</content>
  </entry>
</feed>''';
      final body = List<int>.generate(512, (i) => i & 0xff);
      const assetName = 'SilentGateSetup-99.0.0-beta.2.exe';
      final manifest = UpdateManifest(
        version: '99.0.0-beta.2',
        channel: UpdateManifest.channelBeta,
        assets: [
          UpdateAsset(
            name: assetName,
            size: body.length,
            sha256: Sha256.ofBytes(body),
          ),
        ],
      );
      final manifestBytes = utf8.encode(manifest.toJson());
      final sigText = UpdateSignature.sign(manifestBytes, seed);
      final mirrorJson = jsonEncode({
        'version': '99.0.0-beta.2',
        'beta': true,
        'notes': 'Mirror beta notes',
        'url': 'https://silentgate.lol/dl/$assetName',
        'asset': assetName,
        'size': body.length,
        'manifest': 'https://silentgate.lol/dl/update-manifest.json',
        'sig': 'https://silentgate.lol/dl/update-manifest.json.sig',
      });

      final res = await AppUpdate.check(
        beta: true,
        publicKeyBase64: publicKey,
        assetHint: 'setup',
        fetcher: (uri) async {
          if (uri.host == 'api.github.com') {
            throw const SocketException('api.github.com blocked');
          }
          if (uri.host == 'github.com' && uri.path.endsWith('/releases.atom')) {
            return const UpdateHttpResponse(200, atomXml);
          }
          if (uri.host == 'github.com' && uri.path.contains('/releases/download/')) {
            throw const SocketException('objects.githubusercontent.com blocked');
          }
          if (uri.host == 'silentgate.lol' && uri.path.endsWith('.json') &&
              !uri.path.endsWith('update-manifest.json')) {
            return UpdateHttpResponse(200, mirrorJson);
          }
          if (uri.toString() == 'https://silentgate.lol/dl/update-manifest.json') {
            return UpdateHttpResponse(200, utf8.decode(manifestBytes));
          }
          if (uri.toString() == 'https://silentgate.lol/dl/update-manifest.json.sig') {
            return UpdateHttpResponse(200, sigText);
          }
          if (uri.host == 'silentgate.lol') {
            return UpdateHttpResponse(200, mirrorJson);
          }
          throw SocketException('unexpected $uri');
        },
      );

      expect(res.state, UpdateCheckState.available);
      expect(res.release?.version, '99.0.0-beta.2');
      expect(res.release?.canSelfUpdate, isTrue);
      expect(res.release?.downloadUrl,
          'https://silentgate.lol/dl/$assetName');
    });

    test('asks subscription traffic consent in SplitMode.all (auto & manual) and respects skipUpdateVpnTrafficWarning', () async {
      final rel = buildRelease('1.16.0', beta: false);
      currentSettings = const AppSettings(
        betaChannel: false,
        appUpdateMode: AppUpdateMode.auto,
        splitTunnel: SplitTunnelConfig(mode: SplitMode.all),
      );

      final prompts = <bool>[];
      var allowTraffic = false;
      final c = makeController(
        isVpnActive: () => true,
        checker: ({required bool beta}) async => UpdateCheckResult.available(rel),
      );
      c.confirmVpnTraffic = ({required bool isDownload, int? sizeBytes}) async {
        prompts.add(isDownload);
        return allowTraffic;
      };

      // User declines traffic spend during auto startup -> no check/download happens.
      await c.startup();
      expect(prompts, [false]);
      expect(c.phase, UpdatePhase.idle);
      expect(downloadCalls, 0);

      // User approves traffic spend -> check + download succeed, then sets "don't show again".
      prompts.clear();
      allowTraffic = true;
      await c.checkNow();
      expect(prompts, [false, true]);
      expect(downloadCalls, 1);

      await c.setSkipTrafficWarning(true);
      expect(currentSettings.skipUpdateVpnTrafficWarning, isTrue);
      prompts.clear();
      await c.checkNow();
      expect(prompts, isEmpty, reason: 'must not prompt again when skipUpdateVpnTrafficWarning is true');
      c.dispose();
    });

    test('retries check via VPN proxy after direct failure when user consents', () async {
      final rel = buildRelease('1.16.0', beta: false);
      currentSettings = const AppSettings(
        betaChannel: false,
        appUpdateMode: AppUpdateMode.ask,
        splitTunnel: SplitTunnelConfig(mode: SplitMode.onlySelected),
      );

      var proxyUsed = false;
      var consentAsked = 0;
      final c = makeController(
        isVpnActive: () => true,
        vpnProxyOf: () => const UpdateProxy(host: '127.0.0.1', port: 10809),
        checker: ({required bool beta}) async =>
            const UpdateCheckResult.failed('direct blocked'),
        proxyChecker: ({required bool beta, required UpdateProxy proxy}) async {
          proxyUsed = proxy.port == 10809;
          return UpdateCheckResult.available(rel);
        },
      );
      c.confirmVpnTraffic = ({required bool isDownload, int? sizeBytes}) async {
        consentAsked++;
        return true;
      };

      await c.checkNow();
      expect(consentAsked, 1);
      expect(proxyUsed, isTrue);
      expect(c.phase, UpdatePhase.available);
      expect(c.offer?.version, '1.16.0');
      c.dispose();
    });
  });
}
