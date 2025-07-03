import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show ApiException, TOTPSecretResponse;
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart' show SixDigitField;

import '../../state/pm_sign_up_state.dart';
import '../../data/models/models.dart';

/// A page that displays (and fetches) a TOTP QR code from the server
/// if not in test mode, or a placeholder in test mode.
/// Then the user enters their 6-digit code to finalize the TOTP setup.
///
/// On success, we do the final "register" call with pmAuthRepository
/// (since we have all sign-up data in pmSignUpState).
/// If success => go /main.
class TotpSetupPage extends ConsumerStatefulWidget {
  const TotpSetupPage({super.key});

  @override
  ConsumerState<TotpSetupPage> createState() => _TotpSetupPageState();
}

class _TotpSetupPageState extends ConsumerState<TotpSetupPage> {
  bool _isLoading = false;
  bool _fetchedSecret = false;
  String _totpCode = '';
  String _qrUrl = ''; // from server, or fake
  final bool _showQr = true;

  @override
  void initState() {
    super.initState();
    // Attempt to fetch or generate TOTP secret if needed
    Future.microtask(_fetchTotpSecretIfNeeded);
  }

  Future<void> _fetchTotpSecretIfNeeded() async {
    final logger = ref.read(appLoggerProvider);
    final config = PoofPMFlavorConfig.instance;
    final signUpNotifier = ref.read(pmSignUpStateNotifierProvider.notifier);
    final pmSignUpState = ref.read(pmSignUpStateNotifierProvider);
    final pmAuthRepo = ref.read(pmAuthRepositoryProvider);

    // If we already have a TOTP secret stored, skip
    if (pmSignUpState.totpSecret.isNotEmpty) {
      setState(() {
        _fetchedSecret = true;
        _qrUrl = 'https://chart.googleapis.com/chart?chs=200x200&cht=qr&chl=otpauth://totp/PMApp:${pmSignUpState.email}'; 
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (!config.testMode) {
        final TOTPSecretResponse resp = await pmAuthRepo.generateTOTPSecret();
        // Save the secret to sign-up state
        signUpNotifier.setTotpSecret(resp.secret);

        setState(() {
          _fetchedSecret = true;
        });
      } else {
        logger.d('[TEST MODE] Using fake TOTP secret/QR.');
        signUpNotifier.setTotpSecret('FAKE_TOTP_SECRET');
        await Future.delayed(const Duration(milliseconds: 600));
        setState(() {
          _fetchedSecret = true;
          _qrUrl = 'https://chart.googleapis.com/chart?chs=200x200&cht=qr&chl=otpauth://totp/PMApp:demo';
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      logger.e('TotpSetupPage: generateTOTPSecret failed: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate TOTP secret: ${e.message}')),
      );
    } catch (e, st) {
      if (!mounted) return;
      logger.e('TotpSetupPage unexpected: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyFakeSecret() async {
    // In real usage, you'd hide it behind a more secure approach.
    // For demonstration, we do a clipboard write:
    await Clipboard.setData(const ClipboardData(text: 'FAKE_TOTP_SECRET'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fake secret copied to clipboard!')),
    );
  }

  Future<void> _onVerifyCode() async {
    if (_totpCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 6-digit code.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final pmAuthRepo = ref.read(pmAuthRepositoryProvider);
    final signUp = ref.read(pmSignUpStateNotifierProvider);
    final logger = ref.read(appLoggerProvider);
    final config = PoofPMFlavorConfig.instance;

    try {
      // Build the final PmRegisterRequest from pmSignUpState
      final req = _buildRegisterRequest(signUp, _totpCode);

      if (!config.testMode) {
        await pmAuthRepo.doRegister(req);
      } else {
        logger.d('[TEST MODE] Skipping real doRegister(...)');
        await Future.delayed(const Duration(milliseconds: 800));
      }

      if (!mounted) return;
      // If success => go to /main
      context.go('/main');

    } on ApiException catch (e) {
      logger.e('TotpSetupPage: Registration failed: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('TotpSetupPage: Unexpected error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Helper that merges all sign-up data into a [PmRegisterRequest].
  PmRegisterRequest _buildRegisterRequest(PmSignUpState st, String totpCode) {
    return PmRegisterRequest(
      firstName:     st.firstName,
      lastName:      st.lastName,
      email:         st.email,
      phoneNumber:   st.phoneNumber.isEmpty ? null : st.phoneNumber,
      businessName:  st.companyName,
      businessAddress: st.companyStreet,
      city:          st.companyCity,
      state:         st.companyState,
      zipCode:       st.companyZip,
      totpSecret:    st.totpSecret,
      totpToken:     totpCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppConstants.kDefaultPadding,
          child: _isLoading && !_fetchedSecret
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(height: AppConstants.kLargeVerticalSpacing),

                    const Text(
                      'Set Up Two-Factor Authentication',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

                    const Text(
                      'Scan this QR code in your authenticator app, or copy your secret if needed. Then enter the 6-digit code from the app below.',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: AppConstants.kLargeVerticalSpacing),

                    if (_fetchedSecret && _showQr) ...[
                      Center(
                        child: Image.network(
                          _qrUrl,
                          width: 200,
                          height: 200,
                          errorBuilder: (ctx, obj, stack) => const Icon(
                            Icons.qr_code,
                            size: 200,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppConstants.kDefaultVerticalSpacing),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _copyFakeSecret,
                          icon: const Icon(Icons.copy),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(160, 40),
                          ),
                          label: const Text('Copy Secret'),
                        ),
                      ),
                      const SizedBox(height: AppConstants.kLargeVerticalSpacing),
                    ],

                    const Text(
                      'After adding the TOTP key to your app, please enter the 6-digit code below to confirm:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

                    SixDigitField(
                      autofocus: true,
                      onChanged: (val) => setState(() => _totpCode = val),
                    ),
                    const Spacer(),

                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _onVerifyCode,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                            ),
                            child: const Text('Verify & Finish'),
                          ),
                  ],
                ),
        ),
      ),
    );
  }
}

