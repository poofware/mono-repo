import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;

/// A sign-up screen that collects first name, last name,
/// required email, optional phone, and company name.
/// After completion, pushes /company_address.
class CreateAccountPage extends ConsumerStatefulWidget {
  const CreateAccountPage({super.key});

  @override
  ConsumerState<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends ConsumerState<CreateAccountPage> {
  final _firstNameCtl = TextEditingController();
  final _lastNameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _phoneCtl = TextEditingController(); // optional
  final _companyNameCtl = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameCtl.dispose();
    _lastNameCtl.dispose();
    _emailCtl.dispose();
    _phoneCtl.dispose();
    _companyNameCtl.dispose();
    super.dispose();
  }

  Future<void> _onNext() async {
    final firstName = _firstNameCtl.text.trim();
    final lastName = _lastNameCtl.text.trim();
    final email = _emailCtl.text.trim();
    final phone = _phoneCtl.text.trim(); // optional
    final companyName = _companyNameCtl.text.trim();

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        companyName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final pmAuthRepo = ref.read(pmAuthRepositoryProvider);
    final signUpNotifier = ref.read(pmSignUpStateNotifierProvider.notifier);
    final config = PoofPMFlavorConfig.instance;
    final logger = ref.read(appLoggerProvider);

    try {
      // 1) If not test mode, check email validity
      if (!config.testMode) {
        await pmAuthRepo.checkEmailValid(email);
      } else {
        logger.d('[TEST MODE] Skipping real checkEmailValid');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 2) Save partial data in sign-up state
      signUpNotifier.setBasicInfo(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phoneNumber: phone,
        companyName: companyName,
      );

      // 3) Go to next step -> /company_address
      if (!mounted) return;
      context.push('/company_address');
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot proceed: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('CreateAccountPage: Unexpected error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final inputDecoration = InputDecoration(
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

    final cardFooter = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Already have an account? ", style: textTheme.bodyMedium),
        GestureDetector(
          onTap: () => context.go('/'),
          child: Text(
            'Sign in',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );

    return AuthPageWrapper(
      showBackButton: true,
      // MODIFICATION: Replaced boilerplate Container with AuthFormCard.
      child: AuthFormCard(
        footer: cardFooter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create your account',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Step 1 of 4: Basic Information',
              style: textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            // First name
            TextField(
              controller: _firstNameCtl,
              decoration: inputDecoration.copyWith(labelText: 'First Name *'),
            ),
            const SizedBox(height: 16),

            // Last name
            TextField(
              controller: _lastNameCtl,
              decoration: inputDecoration.copyWith(labelText: 'Last Name *'),
            ),
            const SizedBox(height: 16),

            // Email
            TextField(
              controller: _emailCtl,
              keyboardType: TextInputType.emailAddress,
              decoration: inputDecoration.copyWith(labelText: 'Email *'),
            ),
            const SizedBox(height: 16),

            // Phone (optional)
            TextField(
              controller: _phoneCtl,
              keyboardType: TextInputType.phone,
              decoration:
                  inputDecoration.copyWith(labelText: 'Phone (optional)'),
            ),
            const SizedBox(height: 16),

            // Company name
            TextField(
              controller: _companyNameCtl,
              decoration:
                  inputDecoration.copyWith(labelText: 'Company Name *'),
            ),
            const SizedBox(height: 32),

            // Next Button
            ElevatedButton(
              onPressed: _isLoading ? null : _onNext,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white))
                  : const Text('Next',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}