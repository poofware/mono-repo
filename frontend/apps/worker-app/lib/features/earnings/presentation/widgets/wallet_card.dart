// worker-app/lib/features/earnings/presentation/widgets/wallet_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

class WalletCard extends StatelessWidget {
  final double balance;
  final DateTime? nextPayoutDate;

  const WalletCard({
    super.key,
    required this.balance,
    this.nextPayoutDate,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final formattedDate = nextPayoutDate != null
        ? DateFormat('EEEE, MMM d').format(nextPayoutDate!)
        : '--';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.poofColor.withValues(alpha: 0.9),
              AppColors.poofColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.poofColor.withValues(alpha: 0.3),
              offset: const Offset(0, 8),
              blurRadius: 20,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizations.walletCardAvailableBalance,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${balance.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text(
                  appLocalizations.walletCardNextPayout(formattedDate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
