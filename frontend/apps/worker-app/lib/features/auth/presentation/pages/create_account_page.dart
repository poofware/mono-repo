// worker-app/lib/features/auth/presentation/pages/create_account_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/features/auth/presentation/pages/phone_verification_info_page.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

import '../widgets/phone_number_field.dart';

class CreateAccountPage extends ConsumerStatefulWidget {
  const CreateAccountPage({super.key});

  @override
  ConsumerState<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends ConsumerState<CreateAccountPage> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;

  String _combinedPhone = '';
  String _initialDialCode = '+1';
  String _initialLocalNumber = '';
  bool _isLoading = false;
  bool _isFormValid = false;
  bool _isPhoneValid = false;
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    // Initialize empty controllers first. They will be populated in build().
    _firstNameController = TextEditingController()
      ..addListener(_updateFormValidity);
    _lastNameController = TextEditingController()
      ..addListener(_updateFormValidity);
    _emailController = TextEditingController()
      ..addListener(_updateFormValidity);
  }

  void _initializeFieldsFromState() {
    final signUpState = ref.read(signUpProvider);
    _firstNameController.text = signUpState.firstName;
    _lastNameController.text = signUpState.lastName;
    _emailController.text = signUpState.email;
    _combinedPhone = signUpState.phoneNumber;

    // Simple parser for phone number parts
    if (signUpState.phoneNumber.startsWith('+44')) {
      _initialDialCode = '+44';
      _initialLocalNumber = signUpState.phoneNumber.substring(3);
    } else if (signUpState.phoneNumber.startsWith('+1')) {
      _initialDialCode = '+1';
      _initialLocalNumber = signUpState.phoneNumber.substring(2);
    } else {
      _initialLocalNumber = signUpState.phoneNumber;
    }
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_updateFormValidity);
    _lastNameController.removeListener(_updateFormValidity);
    _emailController.removeListener(_updateFormValidity);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _updateFormValidity() {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();

    final isValid =
        firstName.isNotEmpty &&
        lastName.isNotEmpty &&
        email.isNotEmpty &&
        _isPhoneValid;

    if (isValid != _isFormValid) {
      setState(() {
        _isFormValid = isValid;
      });
    }
  }

  Future<void> _onCreateAccount() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _combinedPhone.trim();

    // Capture context before async gaps
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;
    final appLocalizations = AppLocalizations.of(capturedContext);

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty) {
      showAppSnackBar(
        context,
        Text(appLocalizations.createAccountAllFieldsRequired),
      );
      return;
    }

    final config = PoofWorkerFlavorConfig.instance;
    setState(() => _isLoading = true);

    final workerAuthRepo = ref.read(workerAuthRepositoryProvider);
    final signUpNotifier = ref.read(signUpProvider.notifier);

    try {
      if (!config.testMode) {
        await workerAuthRepo.checkPhoneValid(phone);
        await workerAuthRepo.checkEmailValid(email);
      }

      signUpNotifier.setBasicInfo(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phoneNumber: phone,
      );

      // No callback needed; we'll proceed after the verification flow returns.

      // Await the push and reset loading state when it returns.
      // This robustly handles the user pressing the back button.
      router.pushNamed<bool>(
        AppRouteNames.phoneVerificationInfoPage,
        extra: PhoneVerificationInfoArgs(
          phoneNumber: phone,
          goToTotpAfterSuccess: true,
        ),
      );
      if (mounted) setState(() => _isLoading = false);
      return;
    } on ApiException catch (e) {
      if (!capturedContext.mounted) return;
      showAppSnackBar(
        capturedContext,
        Text(userFacingMessage(capturedContext, e)),
      );
    } catch (e) {
      if (!capturedContext.mounted) return;
      showAppSnackBar(
        capturedContext,
        Text(appLocalizations.loginUnexpectedError(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasInitialized) {
      _initializeFieldsFromState();
      _hasInitialized = true;
    }

    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const fieldGap = SizedBox(height: AppConstants.kDefaultVerticalSpacing);

    // This is the new custom InputDecoration
    InputDecoration customInputDecoration({required String labelText}) {
      return InputDecoration(
        labelText: labelText,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.poofColor, width: 2),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppConstants.kDefaultPadding,
          child: Column(
            children: [
              // This column takes up all available space and pins the button to the bottom
              Expanded(
                // The scroll view contains all the form elements
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // back button
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.goNamed(AppRouteNames.home);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Icon
                      const Center(
                            child: Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 64,
                              color: AppColors.poofColor,
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 400.ms)
                          .scale(
                            begin: const Offset(0.8, 0.8),
                            end: const Offset(1, 1),
                            curve: Curves.easeOutBack,
                          ),
                      const SizedBox(height: 24),
                      // Title
                      Text(
                            appLocalizations.createAccountTitle,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 300.ms)
                          .slideX(
                            begin: -0.1,
                            duration: 400.ms,
                            curve: Curves.easeOutCubic,
                          ),
                      // Subtitle
                      Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              appLocalizations.createAccountSubtitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 400.ms)
                          .slideX(
                            begin: -0.1,
                            duration: 400.ms,
                            curve: Curves.easeOutCubic,
                          ),
                      const SizedBox(height: 32),
                      // First Name and Last Name in a Row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _firstNameController,
                              autofocus: false,
                              decoration: customInputDecoration(
                                labelText: appLocalizations
                                    .createAccountFirstNameLabel,
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: AppConstants.kDefaultVerticalSpacing,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _lastNameController,
                              decoration: customInputDecoration(
                                labelText:
                                    appLocalizations.createAccountLastNameLabel,
                              ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                      fieldGap,
                      // Email
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: customInputDecoration(
                          labelText: appLocalizations.createAccountEmailLabel,
                        ),
                      ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
                      fieldGap,
                      // Phone Number
                      PhoneNumberField(
                        onChanged: (fullNumber, isValid) {
                          _combinedPhone = fullNumber;
                          if (isValid != _isPhoneValid) {
                            setState(() {
                              _isPhoneValid = isValid;
                              _updateFormValidity();
                            });
                          }
                        },
                        labelText: appLocalizations.createAccountPhoneLabel,
                        initialDialCode: _initialDialCode,
                        initialLocalNumber: _initialLocalNumber,
                      ).animate().fadeIn(delay: 700.ms, duration: 500.ms),
                    ],
                  ),
                ),
              ),
              // This button is pinned to the bottom
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: WelcomeButton(
                  text: appLocalizations.createAccountNextButton,
                  isLoading: _isLoading,
                  onPressed: _isFormValid ? _onCreateAccount : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
