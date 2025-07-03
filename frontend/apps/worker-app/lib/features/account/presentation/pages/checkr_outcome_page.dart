// lib/features/account/presentation/pages/checkr_outcome_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import '../../data/models/checkr.dart';
import '../../providers/providers.dart';

class CheckrOutcomePage extends ConsumerStatefulWidget {
  const CheckrOutcomePage({super.key});

  @override
  ConsumerState<CheckrOutcomePage> createState() => _CheckrOutcomePageState();
}

class _CheckrOutcomePageState extends ConsumerState<CheckrOutcomePage> {
  bool _isLoading = true;
  CheckrReportOutcome? _outcome;
  String _email = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchOutcomeAndEmail();
    });
  }

  Future<void> _fetchOutcomeAndEmail() async {
    if (!mounted) return;

    final repo = ref.read(workerAccountRepositoryProvider);
    final cfg = PoofWorkerFlavorConfig.instance;

    try {
      CheckrReportOutcome fetchedOutcome;
      if (!cfg.testMode) {
        final resp = await repo.getCheckrOutcome();
        fetchedOutcome = resp.outcome;
      } else {
        // Use a test-mode default for UI previews
        fetchedOutcome = CheckrReportOutcome.reviewCharges;
      }

      final worker = ref.read(workerStateNotifierProvider).worker;
      if (mounted) {
        setState(() {
          _outcome = fetchedOutcome;
          _email = worker?.email ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  void _onContinue() {
    // Navigate to the next appropriate step based on worker status
    // For now, this just goes to the main dashboard.
    context.goNamed('MainTab');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
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
            )
          ],
        ),
      ),
    );
  }

  Widget _buildContentState() {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Determine UI elements based on outcome
    IconData icon;
    Color iconColor;
    String statusText;
    String subtitle;
    bool showPortalButton = true;

    switch (_outcome) {
      case CheckrReportOutcome.approved:
        icon = Icons.gpp_good_outlined;
        iconColor = Colors.green;
        statusText = appLocalizations.checkrStatusApproved;
        subtitle = appLocalizations.checkrOutcomePageSubtitleApproved;
        showPortalButton = false; // No need to see portal if approved
        break;
      case CheckrReportOutcome.canceled:
      case CheckrReportOutcome.disqualified:
        icon = Icons.gpp_bad_outlined;
        iconColor = Colors.red;
        statusText = appLocalizations.checkrStatusCanceled;
        subtitle = appLocalizations.checkrOutcomePageSubtitleCanceled;
        break;
      default: // Pending, review, etc.
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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Icon(icon, size: 64, color: iconColor),
                  )
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
                    style: theme.textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
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
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 400.ms)
                      .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                  const SizedBox(height: 32),
                  Container(
                    padding: AppConstants.kDefaultPadding,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              appLocalizations.checkrOutcomePageCurrentStatusLabel,
                              style: theme.textTheme.titleMedium,
                            ),
                            _StatusChip(text: statusText, color: iconColor),
                          ],
                        ),
                        const Divider(height: 24),
                        Text(
                          appLocalizations.checkrOutcomePageEmailNotification(
                              _email.isEmpty
                                  ? appLocalizations.checkrOutcomePageYourEmailFallback
                                  : _email),
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          appLocalizations.checkrOutcomePageQuestions,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Column(
              children: [
                if (showPortalButton) ...[
                  _OpenPortalButton(
                    text: appLocalizations.checkrOutcomePageOpenPortalButton,
                  ),
                  const SizedBox(height: 12),
                ],
                WelcomeButton(
                  text: appLocalizations.checkrOutcomePageContinueDashboardButton,
                  onPressed: _onContinue,
                ),
              ],
            ),
          ),
        ],
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
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _OpenPortalButton extends StatefulWidget {
  final String text;
  const _OpenPortalButton({required this.text});

  @override
  State<_OpenPortalButton> createState() => _OpenPortalButtonState();
}

class _OpenPortalButtonState extends State<_OpenPortalButton> {
  bool _isOpening = false;

  Future<void> _handleOpenPortal() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final BuildContext capturedContext = context;

    try {
      final success = await tryLaunchUrl('https://candidate.checkr.com/');
      if (!success && capturedContext.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(capturedContext).urlLauncherCannotLaunch),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isOpening ? null : _handleOpenPortal,
        icon: _isOpening
            ? const SizedBox.shrink()
            : const Icon(Icons.open_in_new),
        label: _isOpening
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.primary,
                ),
              )
            : Text(widget.text),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.outline),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

