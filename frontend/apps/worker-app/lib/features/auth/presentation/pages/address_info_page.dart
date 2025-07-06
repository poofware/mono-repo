// frontend/apps/worker-app/lib/features/auth/presentation/pages/address_info_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/features/account/presentation/widgets/profile_form_fields.dart';

class AddressInfoPage extends ConsumerStatefulWidget {
  const AddressInfoPage({super.key});

  @override
  ConsumerState<AddressInfoPage> createState() => _AddressInfoPageState();
}

class _AddressInfoPageState extends ConsumerState<AddressInfoPage> {
  bool _isLoading = false;
  AddressResolved? _resolvedAddress;
  String _aptSuite = '';

  bool get _canContinue => !_isLoading && _resolvedAddress != null;

  Future<void> _onContinue() async {
    if (!_canContinue) return;
    setState(() => _isLoading = true);

    ref.read(signUpProvider.notifier).setAddressInfo(
          streetAddress: _resolvedAddress!.street,
          aptSuite: _aptSuite,
          city: _resolvedAddress!.city,
          stateName: _resolvedAddress!.state,
          zipCode: _resolvedAddress!.postalCode,
        );

    await context.pushNamed(AppRouteNames.vehicleSetupPage);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final signUpState = ref.watch(signUpProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
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
                        const Center(
                          child: Icon(Icons.location_on_outlined,
                              size: 64, color: AppColors.poofColor),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 400.ms)
                            .scale(
                                begin: const Offset(0.8, 0.8),
                                end: const Offset(1, 1),
                                curve: Curves.easeOutBack),
                        const SizedBox(height: 24),
                        Text(
                          app.addressInfoPageTitle,
                          style: theme.textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        )
                            .animate()
                            .fadeIn(delay: 300.ms)
                            .slideX(
                                begin: -0.1,
                                duration: 400.ms,
                                curve: Curves.easeOutCubic),
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            app.addressInfoPageSubtitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 400.ms)
                            .slideX(
                                begin: -0.1,
                                duration: 400.ms,
                                curve: Curves.easeOutCubic),
                        const SizedBox(height: 32),
                        AddressFormField(
                          initialStreet: signUpState.streetAddress,
                          initialAptSuite: signUpState.aptSuite,
                          initialCity: signUpState.city,
                          initialState: signUpState.stateName,
                          initialZip: signUpState.zipCode,
                          isEditing: true, // Always in editing mode here
                          onChanged: (resolved, apt) {
                            setState(() {
                              _resolvedAddress = resolved;
                              _aptSuite = apt;
                            });
                          },
                        ),
                      ]
                          .animate(interval: 80.ms)
                          .fadeIn(duration: 500.ms, delay: 500.ms)
                          .slideY(begin: 0.1),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: WelcomeButton(
                    text: app.addressInfoPageContinueButton,
                    isLoading: _isLoading,
                    onPressed: _canContinue ? _onContinue : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

