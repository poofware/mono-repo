// frontend/apps/worker-app/lib/features/auth/presentation/pages/vehicle_setup_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/features/account/data/models/models.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/features/account/presentation/widgets/profile_form_fields.dart';

class VehicleSetupPage extends ConsumerStatefulWidget {
  const VehicleSetupPage({super.key});
  @override
  ConsumerState<VehicleSetupPage> createState() => _VehicleSetupPageState();
}

class _VehicleSetupPageState extends ConsumerState<VehicleSetupPage> {
  bool _isLoading = false;
  int _vehicleYear = 0;
  String _vehicleMake = '';
  String _vehicleModel = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final signUpState = ref.read(signUpProvider);
        setState(() {
          _vehicleYear = signUpState.vehicleYear;
          _vehicleMake = signUpState.vehicleMake;
          _vehicleModel = signUpState.vehicleModel;
        });
      }
    });
  }

  bool get _canContinue =>
      !_isLoading &&
      _vehicleYear > 0 &&
      _vehicleMake.isNotEmpty &&
      _vehicleModel.isNotEmpty;

  Future<void> _onContinue() async {
    if (!_canContinue) return;
    setState(() => _isLoading = true);

    final onboarding = ref.read(signUpProvider);
    final isTestMode = PoofWorkerFlavorConfig.instance.testMode;

    try {
      if (!isTestMode) {
        final repo = ref.read(workerAccountRepositoryProvider);
        final req = SubmitPersonalInfoRequest(
          streetAddress: onboarding.streetAddress,
          aptSuite: onboarding.aptSuite.isEmpty ? null : onboarding.aptSuite,
          city: onboarding.city,
          state: onboarding.stateName,
          zipCode: onboarding.zipCode,
          vehicleYear: _vehicleYear,
          vehicleMake: _vehicleMake,
          vehicleModel: _vehicleModel,
        );
        await repo.submitPersonalInfo(req);
      }
      if (mounted) context.pushNamed(AppRouteNames.stripeIdvPage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
            e is ApiException
                ? userFacingMessage(context, e)
                : AppLocalizations.of(context).loginUnexpectedError(e.toString()),
          )),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final signUpState = ref.watch(signUpProvider);

    return Scaffold(
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
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => context.pop(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Center(
                          child: Icon(Icons.directions_car_outlined,
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
                          app.vehicleSetupPageTitle,
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
                            app.vehicleSetupPageSubtitle,
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
                        VehicleFormField(
                          initialYear: signUpState.vehicleYear,
                          initialMake: signUpState.vehicleMake,
                          initialModel: signUpState.vehicleModel,
                          isEditing: true, // Always editing on this page
                          onChanged: (year, make, model) {
                            setState(() {
                              _vehicleYear = year;
                              _vehicleMake = make;
                              _vehicleModel = model;
                            });
                             ref.read(signUpProvider.notifier).setVehicleInfo(
                                  vehicleYear: year,
                                  vehicleMake: make,
                                  vehicleModel: model,
                                );
                          },
                        ),
                      ]
                          .animate(interval: 80.ms)
                          .fadeIn(duration: 500.ms, delay: 500.ms)
                          .slideY(begin: 0.1)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: WelcomeButton(
                  text: app.vehicleSetupPageContinueButton,
                  isLoading: _isLoading,
                  onPressed: _canContinue ? _onContinue : null,
                ).animate().fadeIn(delay: 600.ms, duration: 400.ms).slideY(begin: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

