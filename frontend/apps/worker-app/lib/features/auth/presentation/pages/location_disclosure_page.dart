import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/utils/location_consent_manager.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/routing/router.dart';

class LocationDisclosurePage extends ConsumerStatefulWidget {
  const LocationDisclosurePage({super.key});

  @override
  ConsumerState<LocationDisclosurePage> createState() => _LocationDisclosurePageState();
}

class _LocationDisclosurePageState extends ConsumerState<LocationDisclosurePage> {
  bool _submitting = false;

  Future<void> _requestLocationPermission() async {
    // Keep looping here until we actually have permission. Only pop() when
    // permission is granted. For "Don't ask again"/deniedForever, route the
    // user to app settings; for location services OFF, route to OS location
    // settings. We do not leave this page until permission is granted.
    // Capture context-bound objects before any awaits.
    final localContext = context;
    final router = GoRouter.of(localContext);
    await LocationConsentManager.markAndroidDisclosureComplete();
    try {
      if (mounted) setState(() => _submitting = true);
      // Ensure device location services are ON. If not, show guidance dialog instead of redirecting.
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) {
        if (!mounted) return;
        if (!localContext.mounted) return;
        await _showLocationServicesRequiredDialog(localContext);
        if (mounted) setState(() => _submitting = false);
        return; // Stay on page; user can tap Continue again after changing settings.
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
        if (!mounted) return;
        // Always take the user to main once permission is granted, to avoid
        // landing back on intermediate auth pages like TOTP verify.
        // Post-frame to avoid context use across async gap warnings
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            router.goNamed(AppRouteNames.mainTab);
          }
        });
        return;
      }

      // Permanently denied → show dialog with clear instructions and Settings link.
      if (perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        if (!localContext.mounted) return;
        await _showPermissionRequiredDialog(localContext);
        if (mounted) setState(() => _submitting = false);
        return; // Stay; user can try again after adjusting settings.
      }
      // Any other non-granted case: stay on page (no-op), user can try again.
      if (mounted) setState(() => _submitting = false);
    } catch (_) {
      // Swallow and keep user on page; they can try again.
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showLocationServicesRequiredDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.location_off_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.locationDisclosureTitle)),
            ],
          ),
          content: Text(l10n.locationDisclosureRequired),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.okButtonLabel),
            ),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                await Geolocator.openLocationSettings();
                if (navigator.canPop()) navigator.pop();
              },
              child: Text(l10n.locationDisclosureOpenSettings),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPermissionRequiredDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.my_location_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.locationDisclosureTitle)),
            ],
          ),
          content: Text(l10n.locationDisclosureRequired),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.okButtonLabel),
            ),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                await Geolocator.openAppSettings();
                if (navigator.canPop()) navigator.pop();
              },
              child: Text(l10n.locationDisclosureOpenSettings),
            ),
          ],
        );
      },
    );
  }

  // Settings path descriptions removed per UX update; we now provide a direct
  // Settings button for convenience and compliance.

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: WelcomeButton(
                    text: l10n.locationDisclosureContinue,
                    isLoading: _submitting,
                    onPressed: _requestLocationPermission,
                  ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
