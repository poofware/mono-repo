// lib/features/account/presentation/pages/checkr_outcome_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_flutter_auth/src/utils/device_id_manager.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/providers/app_providers.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'dart:convert';
import '../../providers/providers.dart';

class CheckrOutcomePage extends ConsumerStatefulWidget {
  const CheckrOutcomePage({super.key});

  @override
  ConsumerState<CheckrOutcomePage> createState() => _CheckrOutcomePageState();
}

class _CheckrOutcomePageState extends ConsumerState<CheckrOutcomePage> {
  late Future<String?> _accessTokenFuture;
  // NEW: State to hold platform and deviceId
  String? _platform;
  String? _deviceId;
  bool _webViewAuthFailed = false;

  @override
  void initState() {
    super.initState();
    _fetchFreshAccessToken();
    // NEW: Get device info once.
    _loadDeviceInfo();
  }

  // NEW: Helper to load device info
  Future<void> _loadDeviceInfo() async {
    final platform = getCurrentPlatform().name;
    final deviceId = await DeviceIdManager.getDeviceId();
    if (mounted) {
      setState(() {
        _platform = platform;
        _deviceId = deviceId;
      });
    }
  }

  void _fetchFreshAccessToken() {
    setState(() {
      _accessTokenFuture = _refreshAndGetToken();
    });
  }

  Future<String?> _refreshAndGetToken() async {
    try {
      await ref.read(authControllerProvider).initSession(GoRouter.of(context));
      final tokens = await ref.read(secureTokenStorageProvider).getTokens();
      return tokens?.accessToken;
    } catch (e) {
      return Future.error(e);
    }
  }

  String _buildHtml({
    required String candidateId,
    required String accessToken,
    required String platform,
    required String deviceId,
  }) {
    final env = PoofWorkerFlavorConfig.instance.name == 'PROD'
        ? 'production'
        : 'staging';

    final sessionTokenPath =
        '${PoofWorkerFlavorConfig.instance.apiServiceURL}/account/worker/checkr/session-token';

    // UPDATED: The sessionTokenRequestHeaders now includes X-Platform and X-Device-ID.
    return '''
      <!doctype html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <script src="https://cdn.jsdelivr.net/npm/@checkr/web-sdk/dist/web-sdk.umd.js"></script>
        <style>
          body, #root { margin: 0; padding: 0; background-color: #f7f7f7; }
        </style>
      </head>
      <body>
        <div id="root"></div>
        <script>
          (async () => {
            const accessToken = '$accessToken';
            try {
              new Checkr.Embeds.ReportsOverview({
                env: '$env',
                sessionTokenPath: '$sessionTokenPath',
                sessionTokenRequestHeaders: () => ({
                  'Authorization': `Bearer \${accessToken}`,
                  'X-Platform': '$platform',
                  'X-Device-ID': '$deviceId'
                }),
                candidateId: '$candidateId',
                expandScreenings: true,
                enableLogging: true,
              }).render('#root');

              // --- NEW: Watch for error banners ---
              const root = document.querySelector('div[id^="zoid-reports-overview-"]');
              if (root) {
                const observer = new MutationObserver(() => {
                  const errNode = root.querySelector('.form-errors, .checkr-embeds-error, [role="alert"].error');
                  if (errNode) {
                    if (window.CheckrWebBridge) {
                      window.CheckrWebBridge.postMessage(JSON.stringify({ type: 'HAS_ERRORS', text: errNode.textContent.trim() }));
                    }
                    observer.disconnect();
                  }
                });
                observer.observe(root, { childList: true, subtree: true });
              }
            } catch (e) {
               console.error('Failed to load Checkr Embed:', e);
               document.getElementById('root').innerText = 'Error loading embed: ' + e.message;
            }
          })();
        </script>
      </body>
      </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final worker = ref.watch(workerStateNotifierProvider).worker;

    Widget body;

    if (_webViewAuthFailed) {
      body = _buildAuthFailedState(appLocalizations);
    } else if (worker == null || _platform == null || _deviceId == null) {
      // Show loader until device info is also ready
      body = const Center(child: CircularProgressIndicator());
    } else if (worker.checkrCandidateId == null ||
        worker.checkrCandidateId!.isEmpty) {
      body = _buildErrorState(
          "Worker does not have a Checkr Candidate ID.", ref, appLocalizations);
    } else {
      body = FutureBuilder<String?>(
        future: _accessTokenFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error, ref, appLocalizations);
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildErrorState(
                "Authentication token not found.", ref, appLocalizations);
          }

          final accessToken = snapshot.data!;
          // UPDATED: Pass platform and deviceId to buildHtml
          final html = _buildHtml(
            candidateId: worker.checkrCandidateId!,
            accessToken: accessToken,
            platform: _platform!,
            deviceId: _deviceId!,
          );

          final controller = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..addJavaScriptChannel(
              'CheckrWebBridge',
              onMessageReceived: (message) {
                try {
                  final data = jsonDecode(message.message) as Map<String, dynamic>;
                  if (data['type'] == 'HAS_ERRORS') {
                    if (mounted) {
                      final logger = ref.read(appLoggerProvider);
                      // FIX: Correct string interpolation
                      logger.w("WebView reported error: \${data['text']}");
                      setState(() {
                        _webViewAuthFailed = true;
                      });
                    }
                  }
                } catch (e) {
                  // Ignore non-JSON messages
                }
              },
            )
            ..loadHtmlString(
              html,
              baseUrl: PoofWorkerFlavorConfig.instance.baseUrl,
            );

          return WebViewWidget(controller: controller);
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: body),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: WelcomeButton(
                  text:
                      appLocalizations.checkrOutcomePageContinueDashboardButton,
                  onPressed: () => context.goNamed(AppRouteNames.mainTab),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthFailedState(AppLocalizations appLocalizations) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sentiment_dissatisfied_outlined,
                size: 64, color: Colors.orange.shade700),
            const SizedBox(height: 24),
            Text(
              "Session Expired",
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "Your secure session timed out. Please retry to refresh your connection.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _webViewAuthFailed = false;
                  _fetchFreshAccessToken();
                });
              },
              child: Text(appLocalizations.earningsPageRetryButton),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
      Object? error, WidgetRef ref, AppLocalizations appLocalizations) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(userFacingMessageFromObject(context, error!)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _fetchFreshAccessToken();
                });
              },
              child: Text(appLocalizations.earningsPageRetryButton),
            )
          ],
        ),
      ),
    );
  }
}
