import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/utils/location_consent_manager.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';

class LocationDisclosurePage extends ConsumerWidget {
  const LocationDisclosurePage({super.key});

  Future<void> _requestLocationPermission(BuildContext context) async {
    // Keep looping here until we actually have permission. Only pop() when
    // permission is granted. For "Don't ask again"/deniedForever, route the
    // user to app settings; for location services OFF, route to OS location
    // settings. We do not leave this page until permission is granted.
    await LocationConsentManager.markAndroidDisclosureComplete();
    try {
      // Ensure device location services are ON.
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) {
        await Geolocator.openLocationSettings();
        return; // Stay on page; user can tap Continue again.
      }

      // Check current permission state.
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      // If still only whileInUse, that's acceptable for foreground features.
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;

      if (granted) {
        if (context.mounted) Navigator.of(context).pop();
        return;
      }

      // Permanently denied → send to app settings.
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return; // Stay; user can try again after adjusting settings.
      }
      // Any other non-granted case: stay on page (no-op), user can try again.
    } catch (_) {
      // Swallow and keep user on page; they can try again.
    }
  }

  Widget _buildBulletPoint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.1),
                          theme.colorScheme.primary.withValues(alpha: 0.2),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/vectors/POOF_SYMBOL_COLOR.svg',
                        height: 90,
                        width: 90,
                      ),
                    ),
                  )
                      .animate()
                      .scale(
                        begin: Offset.zero,
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                        duration: 600.ms,
                      )
                      .fadeIn(duration: 600.ms),
                  const SizedBox(height: 36),
                  Text(
                    l10n.locationDisclosureTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
                  const SizedBox(height: 12),
                  Text(
                    l10n.locationDisclosureIntro,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildBulletPoint(
                          context,
                          l10n.locationDisclosureBullet1,
                        ),
                        _buildBulletPoint(
                          context,
                          l10n.locationDisclosureBullet2,
                        ),
                        _buildBulletPoint(
                          context,
                          l10n.locationDisclosureBullet3,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.privacy_tip_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.locationDisclosurePrivacy,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                  const SizedBox(height: 32),
                  WelcomeButton(
                    text: l10n.locationDisclosureContinue,
                    onPressed: () => _requestLocationPermission(context),
                  ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
