// worker-app/lib/features/earnings/presentation/pages/earnings_page.dart

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/features/account/providers/providers.dart';

import '../../data/models/earnings_models.dart';
import '../../providers/providers.dart';
import '../widgets/earnings_bar_chart.dart';
import '../widgets/wallet_card.dart';

class EarningsPage extends ConsumerStatefulWidget {
  const EarningsPage({super.key});

  @override
  ConsumerState<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends ConsumerState<EarningsPage>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    await ref
        .read(earningsNotifierProvider.notifier)
        .fetchEarningsSummary(force: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final earningsState = ref.watch(earningsNotifierProvider);
    final appLocalizations = AppLocalizations.of(context);
    final summary = earningsState.summary;

    // --- Safe calculations ---
    final currentWeekTotal = summary?.currentWeek?.weeklyTotal ?? 0.0;
    final pendingPastWeeksTotal = summary?.pastWeeks
            .where((week) =>
                week.payoutStatus == PayoutStatus.pending ||
                week.payoutStatus == PayoutStatus.failed)
            .fold(0.0, (sum, week) => sum + week.weeklyTotal) ??
        0.0;

    final currentBalance = currentWeekTotal + pendingPastWeeksTotal;
    final displayedWeeks = summary?.pastWeeks ?? [];
    final failedPayout = summary?.pastWeeks.firstWhereOrNull(
      (w) => w.payoutStatus == PayoutStatus.failed && w.requiresUserAction,
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // --- Header ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
                  child: Text(
                    appLocalizations.earningsPageTitle,
                    style: const TextStyle(
                      fontSize: AppConstants.largeTitle,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    appLocalizations.earningsPageSubtitle,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color.fromARGB(255, 76, 76, 76),
                    ),
                  ),
                ),
              ),

              // --- Payout Failure Notice ---
              if (failedPayout != null)
                SliverToBoxAdapter(
                  child: _PayoutFailedNotice(
                    week: failedPayout,
                    appLocalizations: appLocalizations,
                  )
                      .animate()
                      .slideY(
                        begin: -0.5,
                        end: 0,
                        duration: 400.ms,
                        curve: Curves.easeOutCubic,
                      )
                      .fadeIn(),
                ),

              // --- Wallet Card ---
              SliverToBoxAdapter(
                child: WalletCard(
                  balance: currentBalance,
                  nextPayoutDate: summary?.nextPayoutDate,
                ),
              ),

              // --- This Week's Summary Chart ---
              SliverToBoxAdapter(
                child: EarningsBarChart(
                  week: summary?.currentWeek,
                  title: appLocalizations.earningsPageThisWeekTitle,
                ),
              ),

              // --- Earnings History List ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    appLocalizations.earningsPageWeeklyEarningsLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              if (earningsState.isLoading && displayedWeeks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (displayedWeeks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48.0),
                      child: Text(
                        appLocalizations.earningsPageNoData,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList.separated(
                    itemCount: displayedWeeks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final week = displayedWeeks[index];
                      return _buildPastWeekTile(
                          context, week, appLocalizations);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPastWeekTile(BuildContext context, WeeklyEarnings week,
      AppLocalizations appLocalizations) {
    final startStr = DateFormat('MMM d').format(week.weekStartDate);
    final endStr = DateFormat('MMM d').format(week.weekEndDate);

    return GestureDetector(
      onTap: () => context.pushNamed(AppRouteNames.weekEarningsDetailPage, extra: week),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              offset: Offset(0, 4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$startStr ${appLocalizations.weeklyEarningsPageTitleSuffix} $endStr',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                _buildPayoutStatusChip(week.payoutStatus, appLocalizations),
              ],
            ),
            const Spacer(),
            Text(
              '\$${week.weeklyTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPayoutStatusChip(
      PayoutStatus status, AppLocalizations appLocalizations) {
    Color color;
    String text;
    Widget? trailingIcon;
    String? tooltipMessage;

    switch (status) {
      case PayoutStatus.paid:
        color = Colors.green;
        text = appLocalizations.payoutStatusPaid;
        trailingIcon = Icon(Icons.info_outline, size: 14, color: color);
        tooltipMessage = appLocalizations.payoutStatusPaidTooltip;
        break;
      case PayoutStatus.pending:
        color = Colors.orange;
        text = appLocalizations.payoutStatusPending;
        break;
      case PayoutStatus.processing:
        color = Colors.blue;
        text = appLocalizations.payoutStatusProcessing;
        break;
      case PayoutStatus.failed:
        color = Colors.red;
        text = appLocalizations.payoutStatusFailed;
        break;
      default:
        color = Colors.grey;
        text = appLocalizations.payoutStatusUnknown;
    }

    final chipContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            trailingIcon,
          ],
        ],
      ),
    );

    if (tooltipMessage != null) {
      return Tooltip(
        message: tooltipMessage,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 3),
        preferBelow: false,
        padding: const EdgeInsets.all(8),
        textStyle: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: chipContent,
      );
    }

    return chipContent;
  }
}

class _PayoutFailedNotice extends ConsumerStatefulWidget {
  final WeeklyEarnings week;
  final AppLocalizations appLocalizations;

  const _PayoutFailedNotice({
    required this.week,
    required this.appLocalizations,
  });

  @override
  ConsumerState<_PayoutFailedNotice> createState() =>
      _PayoutFailedNoticeState();
}

class _PayoutFailedNoticeState extends ConsumerState<_PayoutFailedNotice> {
  bool _isContactingSupport = false;
  bool _isFixingOnStripe = false;

  String _getTranslatedReason(String? reasonCode) {
    switch (reasonCode) {
      case 'account_closed':
        return widget.appLocalizations.payoutFailureReason_account_closed;
      case 'bank_account_restricted':
        return widget
            .appLocalizations.payoutFailureReason_bank_account_restricted;
      case 'invalid_account_number':
        return widget
            .appLocalizations.payoutFailureReason_invalid_account_number;
      case 'payouts_not_allowed':
        return widget.appLocalizations.payoutFailureReason_payouts_not_allowed;
      case 'worker_missing_stripe_connect_id':
        return widget.appLocalizations
            .payoutFailureReason_worker_missing_stripe_connect_id;
      case 'stripe_account_payouts_disabled':
        return widget.appLocalizations
            .payoutFailureReason_stripe_account_payouts_disabled;
      case 'account_restricted':
        return widget.appLocalizations.payoutFailureReason_account_restricted;
      case 'no_account':
        return widget.appLocalizations.payoutFailureReason_no_account;
      case 'debit_not_authorized':
        return widget.appLocalizations.payoutFailureReason_debit_not_authorized;
      case 'invalid_currency':
        return widget.appLocalizations.payoutFailureReason_invalid_currency;
      case 'account_frozen':
        return widget.appLocalizations.payoutFailureReason_account_frozen;
      case 'bank_ownership_changed':
        return widget
            .appLocalizations.payoutFailureReason_bank_ownership_changed;
      case 'declined':
        return widget.appLocalizations.payoutFailureReason_declined;
      case 'incorrect_account_holder_name':
        return widget
            .appLocalizations.payoutFailureReason_incorrect_account_holder_name;
      case 'incorrect_account_holder_tax_id':
        return widget.appLocalizations
            .payoutFailureReason_incorrect_account_holder_tax_id;
      default:
        return widget.appLocalizations.payoutFailureReason_unknown;
    }
  }

  Future<void> _handleFixOnStripe() async {
    if (_isFixingOnStripe) return;
    setState(() => _isFixingOnStripe = true);

    final BuildContext capturedContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final repo = ref.read(workerAccountRepositoryProvider);
      final loginLinkUrl = await repo.getStripeExpressLoginLink();
      final success = await tryLaunchUrl(loginLinkUrl);
      if (!success && capturedContext.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text(widget.appLocalizations.urlLauncherCannotLaunch)),
        );
      }
    } catch (e) {
      if (capturedContext.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text(userFacingMessageFromObject(capturedContext, e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFixingOnStripe = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasonText = _getTranslatedReason(widget.week.failureReason);
    final weekDate = DateFormat.yMMMd().format(widget.week.weekStartDate);
    final noticeBody =
        widget.appLocalizations.payoutFailureNoticeBody(weekDate, reasonText);
    const supportEmail = 'team@thepoofapp.com';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.red.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.appLocalizations.payoutFailureNoticeTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              noticeBody,
              style: TextStyle(fontSize: 15, color: Colors.red.shade800),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: (_isContactingSupport || _isFixingOnStripe)
                      ? null
                      : () async {
                          if (_isContactingSupport) return;
                          setState(() => _isContactingSupport = true);
                          final scaffoldMessenger =
                              ScaffoldMessenger.of(context);
                          final BuildContext capturedContext = context;
                          final localizations =
                              AppLocalizations.of(capturedContext);

                          try {
                            final success =
                                await tryLaunchUrl('mailto:$supportEmail');
                            if (!success && capturedContext.mounted) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                    content: Text(
                                        localizations.urlLauncherCannotLaunch)),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isContactingSupport = false);
                            }
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isContactingSupport
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget
                          .appLocalizations.payoutFailureContactSupportButton),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_isFixingOnStripe || _isContactingSupport)
                      ? null
                      : _handleFixOnStripe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isFixingOnStripe
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(widget
                          .appLocalizations.payoutFailureFixOnStripeButton),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

