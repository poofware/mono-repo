// meta-service/pm-app/lib/features/auth/presentation/pages/totp_setup_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show ApiException, TOTPSecretResponse;
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart' show SixDigitField;
import 'package:qr_flutter/qr_flutter.dart'; // Import the qr_flutter package

import '../../data/models/models.dart';
import '../../state/pm_sign_up_state.dart';

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

  // MODIFIED: State variable to hold the otpauth:// URL for the QR code.
  String? _otpAuthUrl;

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

    // If we already have a TOTP secret stored, generate URL locally
    if (pmSignUpState.totpSecret.isNotEmpty) {
      final secret = pmSignUpState.totpSecret;
      final email = pmSignUpState.email;
      const issuer = 'PMApp';
      final otpAuthUrl =
          'otpauth://totp/$issuer:${Uri.encodeComponent(email)}?secret=$secret&issuer=$issuer';
      setState(() {
        _fetchedSecret = true;
        _otpAuthUrl = otpAuthUrl;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (!config.testMode) {
        final email = pmSignUpState.email;
        final TOTPSecretResponse resp = await pmAuthRepo.generateTOTPSecret();
        // Save the secret to sign-up state
        signUpNotifier.setTotpSecret(resp.secret);

        // MODIFIED: Construct the otpauth:// URL to be used by QrImageView
        const issuer = 'PMApp';
        final otpAuthUrl =
            'otpauth://totp/$issuer:${Uri.encodeComponent(email)}?secret=${resp.secret}&issuer=$issuer';

        setState(() {
          _fetchedSecret = true;
          _otpAuthUrl = otpAuthUrl;
        });
      } else {
        logger.d('[TEST MODE] Using fake TOTP secret/QR.');
        const fakeSecret = 'FAKE_TOTP_SECRET';
        signUpNotifier.setTotpSecret(fakeSecret);
        await Future.delayed(const Duration(milliseconds: 600));

        // MODIFIED: Construct the otpauth:// URL for test mode
        const email = 'demo'; // As in original code
        const issuer = 'PMApp';
        final otpAuthUrl =
            'otpauth://totp/$issuer:$email?secret=$fakeSecret&issuer=$issuer';
        setState(() {
          _fetchedSecret = true;
          _otpAuthUrl = otpAuthUrl;
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
    final secret = ref.read(pmSignUpStateNotifierProvider).totpSecret;
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Secret copied to clipboard!')),
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

      // NEW: Clear the sign-up state now that registration is complete.
      ref.read(pmSignUpStateNotifierProvider.notifier).clearAll();

      if (!mounted) return;

      // NEW: Show a success dialog instead of navigating directly.
      await _showSuccessDialog();
    } on ApiException catch (e) {
      logger.e('TotpSetupPage: Registration failed: ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('TotpSetupPage: Unexpected error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shows a confirmation dialog after successful registration.
  Future<void> _showSuccessDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button to close
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Account Created!'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Your account has been created successfully.'),
                SizedBox(height: 8),
                Text('Please proceed to log in.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Proceed to Login'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
                context.go('/'); // Navigate to the login page
              },
            ),
          ],
        );
      },
    );
  }

  /// Helper that merges all sign-up data into a [PmRegisterRequest].
  PmRegisterRequest _buildRegisterRequest(PmSignUpState st, String totpCode) {
    return PmRegisterRequest(
      firstName: st.firstName,
      lastName: st.lastName,
      email: st.email,
      phoneNumber: st.phoneNumber.isEmpty ? null : st.phoneNumber,
      businessName: st.companyName,
      businessAddress: st.companyStreet,
      city: st.companyCity,
      state: st.companyState,
      zipCode: st.companyZip,
      totpSecret: st.totpSecret,
      totpToken: totpCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return AuthPageWrapper(
      showBackButton: true,
      // MODIFICATION: Replaced boilerplate Container with AuthFormCard.
      child: AuthFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set Up Two-Factor',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Step 4 of 4: Account Security',
              style: textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (_isLoading && !_fetchedSecret)
              const Center(child: CircularProgressIndicator())
            else
              _buildTotpContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTotpContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scan the QR code with your authenticator app (e.g., Google Authenticator, Authy).',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push('/qr_info'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              foregroundColor: colorScheme.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.normal),
            ),
            child: const Text("Don't have an authenticator app?"),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          // MODIFIED: Use QrImageView to render the QR code from the otpauth:// URL.
          child: (_otpAuthUrl != null && _otpAuthUrl!.isNotEmpty)
              ? QrImageView(
                  data: _otpAuthUrl!,
                  version: QrVersions.auto,
                  size: 180.0,
                  backgroundColor: Colors.white,
                  errorStateBuilder: (ctx, err) => const Center(
                    child: Icon(Icons.error, size: 180),
                  ),
                )
              : const Icon(Icons.qr_code_scanner_rounded, size: 180),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: _copyFakeSecret,
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Or copy secret manually'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Enter the 6-digit code from your app below to finish setup.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SixDigitField(
          autofocus: true,
          onChanged: (val) => setState(() => _totpCode = val),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _isLoading ? null : _onVerifyCode,
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
              : const Text('Verify & Finish',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}