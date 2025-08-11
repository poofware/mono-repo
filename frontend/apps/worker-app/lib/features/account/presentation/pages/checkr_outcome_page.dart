// lib/features/account/presentation/pages/checkr_outcome_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/providers/app_providers.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';
import 'package:poof_worker/core/utils/location_permissions.dart' as locperm;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../data/models/checkr.dart';
import '../../providers/providers.dart';

class CheckrOutcomePage extends ConsumerStatefulWidget {
  const CheckrOutcomePage({super.key});

  @override
  ConsumerState<CheckrOutcomePage> createState() => _CheckrOutcomePageState();
}

class _CheckrOutcomePageState extends ConsumerState<CheckrOutcomePage> {
  // ----- Outcome-page state -----
  bool _isLoading = true;
  CheckrReportOutcome? _outcome;
  String _email = '';
  Object? _error;

  // ----- Web-view preload state -----
  late Future<String?> _accessTokenFuture;
  String? _platform;
  String? _deviceId;
  String? _keyId;
  late final WebViewController _webViewController;
  bool _webViewReady = false;
  bool _webViewAuthFailed = false;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Make the data fetches sequential to avoid race conditions and simplify logic.
      await _fetchOutcomeAndEmail();
      _prepareWebView(); // start preload after initial fetch.
    });
  }

  // ---------------------------------------------------------------------------
  // OUTCOME FETCH LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _fetchOutcomeAndEmail() async {
    if (!mounted) return;

    final repo = ref.read(workerAccountRepositoryProvider);
    final cfg = PoofWorkerFlavorConfig.instance;

    try {
      // --- START OF MODIFICATION ---

      if (!cfg.testMode) {
        final worker = await repo.getCheckrOutcome();
        if (mounted) {
          setState(() {
            _outcome = worker.checkrReportOutcome;
            _email = worker.email;
            _isLoading = false;
          });
        }
      } else {
        // TEST MODE: Revert to the original, simple logic.
        // We only need to set a dummy outcome for the main page UI.
        final worker = ref.read(workerStateNotifierProvider).worker;
        if (mounted) {
          setState(() {
            _outcome = CheckrReportOutcome.reviewCharges; // Dummy outcome
            _email = worker?.email ?? 'test@example.com';
            _isLoading = false;
          });
        }
      }

      // --- END OF MODIFICATION ---
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // WEB-VIEW PRELOAD LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _prepareWebView() async {
    final platformEnum = getCurrentPlatform();
    final deviceId = await DeviceIdManager.getDeviceId();
    final keyId = await getCachedKeyId(
      isAndroid: platformEnum == FlutterPlatform.android,
    );
    if (!mounted) return;

    setState(() {
      _platform = platformEnum.name;
      _deviceId = deviceId;
      _keyId = keyId;
      _accessTokenFuture = _refreshAndGetToken();
    });

    try {
      final accessToken = await _accessTokenFuture;
      final worker = ref.read(workerStateNotifierProvider).worker;
      if (!mounted) return;

      if (accessToken != null &&
          worker != null &&
          worker.checkrCandidateId != null &&
          worker.checkrCandidateId!.isNotEmpty) {
        _webViewController = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..addJavaScriptChannel(
            'CheckrWebBridge',
            onMessageReceived: (msg) {
              try {
                final data = jsonDecode(msg.message) as Map<String, dynamic>;
                if (data['type'] == 'HAS_ERRORS') {
                  ref
                      .read(appLoggerProvider)
                      .w("WebView reported error: ${data['text']}");
                  if (mounted) {
                    setState(() => _webViewAuthFailed = true);
                  }
                }
              } catch (_) {}
            },
          )
          ..loadHtmlString(
            _buildHtml(
              candidateId: worker.checkrCandidateId!,
              accessToken: accessToken,
              platform: _platform!,
              deviceId: _deviceId!,
              keyId: _keyId ?? '',
            ),
            baseUrl: PoofWorkerFlavorConfig.instance.baseUrl,
          );

        if (_webViewController.platform is WebKitWebViewController) {
          // Enable WKWebView specific features if available
          final ios = _webViewController.platform as WebKitWebViewController;
          ios.setInspectable(true);
        }

        if (mounted) setState(() => _webViewReady = true);
      }
    } catch (_) {
      // silently fail; UI will offer retry
    }
  }

  Future<String?> _refreshAndGetToken() async {
    // FIX: The `_fetchOutcomeAndEmail` call in initState already ensures tokens
    // are refreshed if they were expired. We can just read them from storage now.
    // This avoids the harmful, double-loading `initSession` call.
    final tokens = await ref.read(secureTokenStorageProvider).getTokens();
    return tokens?.accessToken;
  }

  String _buildHtml({
    required String candidateId,
    required String accessToken,
    required String platform,
    required String deviceId,
    required String keyId,
  }) {
    final env = PoofWorkerFlavorConfig.instance.name == 'PROD'
        ? 'production'
        : 'staging';
    final sessionTokenPath =
        '${PoofWorkerFlavorConfig.instance.apiServiceURL}/v1/account/worker/checkr/session-token';

    return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <script src="https://cdn.jsdelivr.net/npm/@checkr/web-sdk/dist/web-sdk.umd.js"></script>
  <style>body,#root{margin:0;padding:0;background:#f7f7f7}</style>
</head>
<body>
  <div id="root"></div>
  <script>
    (async ()=>{
      const accessToken = '$accessToken';
      try{
        new Checkr.Embeds.ReportsOverview({
          env: '$env',
          sessionTokenPath: '$sessionTokenPath',
          sessionTokenRequestHeaders: () => ({
            'Authorization': `Bearer $accessToken`,
            'X-Platform'   : '$platform',
            'X-Device-ID'  : '$deviceId',
            'X-Key-Id'     : '$keyId',
            'ngrok-skip-browser-warning': 'true',
          }),
          candidateId: '$candidateId',
          styles: {
            '.bgc-candidate-link':  { display: 'none' },
            '.bgc-dashboard-link': { display: 'none' },
            '.reports-overview .btn.btn-secondary': {'display': 'none !important'},
          },
          expandScreenings: true,
          enableLogging:   true,

          // New official failure hook
          onLoadError: err => {
            // Shape is { message, statusCode, data, … }
            window.CheckrWebBridge?.postMessage(
              JSON.stringify({ type: 'HAS_ERRORS', text: err?.message || 'Unknown error' })
            );
          }
        }).render('#root');
      }catch(e){
        document.getElementById('root').innerText='Error loading embed: '+e.message;
      }
    })();
  </script>
</body>
</html>
''';
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------
  void _onContinue() async {
    // Require permission on both platforms; if missing, show disclosure and
    // keep the user in this flow until granted.
    final hasPerm = await locperm.hasLocationPermission();
    if (!hasPerm) {
      if (mounted) context.goNamed(AppRouteNames.locationDisclosurePage);
      return;
    }
    if (mounted) context.goNamed(AppRouteNames.mainTab);
  }

  Future<void> _showDetailsSheet() async {
    final appLocalizations = AppLocalizations.of(context);

    if (!_webViewReady || _webViewAuthFailed) {
      await _prepareWebView();
    }
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.50,
        child: _webViewAuthFailed
            ? _buildAuthFailedState(appLocalizations)
            : _webViewReady
            ? Column(
                children: [
                  // Give the webview flexible space
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: WebViewWidget(controller: _webViewController),
                    ),
                  ),
                  // Add a button at the bottom
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      MediaQuery.of(sheetContext).padding.bottom + 12,
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final success = await tryLaunchUrl(
                          'https://candidate.checkr.com/',
                        );
                        if (!success && mounted) {
                          showAppSnackBar(
                            context,
                            Text(appLocalizations.urlLauncherCannotLaunch),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(
                        appLocalizations.checkrOutcomePageOpenPortalButton,
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) {},
      child: Scaffold(
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorState()
              : _buildContentState(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI HELPERS
  // ---------------------------------------------------------------------------
  Widget _buildErrorState() {
    final appLocalizations = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(userFacingMessageFromObject(context, _error!)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchOutcomeAndEmail,
              child: Text(appLocalizations.earningsPageRetryButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentState() {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isApproved = _outcome == CheckrReportOutcome.approved;

    IconData icon;
    Color iconColor;
    String statusText;
    String subtitle;

    switch (_outcome) {
      case CheckrReportOutcome.approved:
        icon = Icons.gpp_good_outlined;
        iconColor = Colors.green;
        statusText = appLocalizations.checkrStatusApproved;
        subtitle = appLocalizations.checkrOutcomePageSubtitleApproved;
        break;
      case CheckrReportOutcome.canceled:
      case CheckrReportOutcome.disqualified:
        icon = Icons.gpp_bad_outlined;
        iconColor = Colors.red;
        statusText = appLocalizations.checkrStatusCanceled;
        subtitle = appLocalizations.checkrOutcomePageSubtitleCanceled;
        break;
      default:
        icon = Icons.hourglass_top_outlined;
        iconColor = Colors.orange;
        statusText = appLocalizations.checkrStatusPending;
        subtitle = appLocalizations.checkrOutcomePageSubtitlePending;
    }

    if (PoofWorkerFlavorConfig.instance.testMode) {
      statusText = appLocalizations.checkrStatusPendingTestMode;
    }

    return Padding(
      padding: AppConstants.kDefaultPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // scrollable content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Center(child: Icon(icon, size: 64, color: iconColor))
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 400.ms)
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                      ),
                  const SizedBox(height: 24),
                  Text(
                        appLocalizations.checkrOutcomePageTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 300.ms)
                      .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                  Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 400.ms)
                      .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                  const SizedBox(height: 32),
                  Container(
                    padding: AppConstants.kDefaultPadding,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              appLocalizations
                                  .checkrOutcomePageCurrentStatusLabel,
                              style: theme.textTheme.titleMedium,
                            ),
                            _StatusChip(text: statusText, color: iconColor),
                          ],
                        ),
                        const Divider(height: 24),
                        Text(
                          appLocalizations.checkrOutcomePageEmailNotification(
                            _email.isEmpty
                                ? appLocalizations
                                      .checkrOutcomePageYourEmailFallback
                                : _email,
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodyMedium,
                            children: [
                              TextSpan(
                                text: appLocalizations
                                    .checkrOutcomePageQuestions1,
                              ),
                              TextSpan(
                                text:
                                    appLocalizations.checkrOutcomePageContactUs,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => tryLaunchUrl(
                                    'mailto:team@thepoofapp.com?subject=${Uri.encodeComponent(appLocalizations.emailSubjectGeneralHelp)}',
                                  ),
                              ),
                              TextSpan(
                                text: appLocalizations
                                    .checkrOutcomePageQuestions2,
                              ),
                            ],
                          ),
                        ),
                        if (!isApproved) ...[
                          const SizedBox(height: 12),
                          Text(
                            appLocalizations
                                .checkrOutcomePageLimitedFunctionalityWarning,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
                ],
              ),
            ),
          ),

          // bottom buttons
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showDetailsSheet,
                      icon: const Icon(Icons.info_outline),
                      label: Text(
                        appLocalizations.acceptedJobsBottomSheetViewDetails,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        side: BorderSide(color: theme.colorScheme.outline),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                WelcomeButton(
                  text: appLocalizations.checkrOutcomePageContinueAppButton,
                  onPressed: _onContinue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AUTH-FAILED RETRY CONTENT
  // ---------------------------------------------------------------------------
  Widget _buildAuthFailedState(AppLocalizations appLocalizations) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sentiment_dissatisfied_outlined,
              size: 64,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 24),
            Text(
              'Session Expired',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your secure session timed out. Please retry to refresh your connection.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _webViewAuthFailed = false;
                });
                _prepareWebView();
              },
              child: Text(appLocalizations.earningsPageRetryButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
