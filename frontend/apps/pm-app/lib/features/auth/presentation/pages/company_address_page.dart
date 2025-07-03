import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/theme/app_constants.dart';
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
  final _cityCtl   = TextEditingController();
  final _stateCtl  = TextEditingController();
  final _zipCtl    = TextEditingController();

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
    final city   = _cityCtl.text.trim();
    final stateName = _stateCtl.text.trim();
    final zip    = _zipCtl.text.trim();

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
        city:   city,
        stateName: stateName,
        zip:    zip,
      );
      if (!mounted) return;
      context.push('/email_verification_info');
    } finally {
      setState(() => _isLoading = false);
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
                'Company Address',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.kLargeVerticalSpacing),

              TextField(
                controller: _streetCtl,
                decoration: const InputDecoration(
                  labelText: 'Street Address *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              TextField(
                controller: _cityCtl,
                decoration: const InputDecoration(
                  labelText: 'City *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              TextField(
                controller: _stateCtl,
                decoration: const InputDecoration(
                  labelText: 'State *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              TextField(
                controller: _zipCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: const InputDecoration(
                  labelText: 'Zip Code *',
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

