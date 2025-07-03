import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_pm/core/providers/app_logger_provider.dart';

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
  final _lastNameCtl  = TextEditingController();
  final _emailCtl     = TextEditingController();
  final _phoneCtl     = TextEditingController(); // optional
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
    final firstName   = _firstNameCtl.text.trim();
    final lastName    = _lastNameCtl.text.trim();
    final email       = _emailCtl.text.trim();
    final phone       = _phoneCtl.text.trim(); // optional
    final companyName = _companyNameCtl.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || companyName.isEmpty) {
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
        lastName:  lastName,
        email:     email,
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppConstants.kDefaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              const Text(
                'Create Account',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.kLargeVerticalSpacing),

              // First name
              TextField(
                controller: _firstNameCtl,
                decoration: const InputDecoration(
                  labelText: 'First Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              // Last name
              TextField(
                controller: _lastNameCtl,
                decoration: const InputDecoration(
                  labelText: 'Last Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              // Email
              TextField(
                controller: _emailCtl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              // Phone (optional)
              TextField(
                controller: _phoneCtl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              // Company name
              TextField(
                controller: _companyNameCtl,
                decoration: const InputDecoration(
                  labelText: 'Company Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const Spacer(),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _onNext,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Next'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

