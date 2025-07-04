import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';

import '../../providers/pm_auth_providers.dart';

/// Collects the company's address info:
/// - street
/// - city
/// - state
/// - zip code
/// Then navigates to the email-verification step.
class CompanyAddressPage extends ConsumerStatefulWidget {
  const CompanyAddressPage({super.key});

  @override
  ConsumerState<CompanyAddressPage> createState() => _CompanyAddressPageState();
}

class _CompanyAddressPageState extends ConsumerState<CompanyAddressPage> {
  final _streetCtl = TextEditingController();
  final _cityCtl = TextEditingController();
  final _stateCtl = TextEditingController();
  final _zipCtl = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _streetCtl.dispose();
    _cityCtl.dispose();
    _stateCtl.dispose();
    _zipCtl.dispose();
    super.dispose();
  }

  Future<void> _onNext() async {
    final street = _streetCtl.text.trim();
    final city = _cityCtl.text.trim();
    final stateName = _stateCtl.text.trim();
    final zip = _zipCtl.text.trim();

    if (street.isEmpty || city.isEmpty || stateName.isEmpty || zip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out the required fields.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Save partial address info to sign-up state
      ref.read(pmSignUpStateNotifierProvider.notifier).setCompanyAddress(
            street: street,
            city: city,
            stateName: stateName,
            zip: zip,
          );
      if (!mounted) return;
      context.push('/email_verification_info');
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

    return AuthPageWrapper(
      showBackButton: true,
      // MODIFICATION: Replaced boilerplate Container with AuthFormCard.
      child: AuthFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Company Address',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Step 2 of 4: Business Location',
              style: textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _streetCtl,
              decoration:
                  inputDecoration.copyWith(labelText: 'Street Address *'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cityCtl,
              decoration: inputDecoration.copyWith(labelText: 'City *'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _stateCtl,
              decoration: inputDecoration.copyWith(labelText: 'State *'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _zipCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: inputDecoration.copyWith(labelText: 'Zip Code *'),
            ),
            const SizedBox(height: 32),
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