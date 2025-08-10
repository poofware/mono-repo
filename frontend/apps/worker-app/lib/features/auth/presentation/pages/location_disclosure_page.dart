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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/vectors/POOF_SYMBOL_COLOR.svg',
                        height: 100,
                        width: 100,
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
                  const SizedBox(height: 32),
                  Text(
                    l10n.locationDisclosureTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.locationDisclosureBody,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  WelcomeButton(
                    text: l10n.locationDisclosureContinue,
                    onPressed: () => _requestLocationPermission(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
