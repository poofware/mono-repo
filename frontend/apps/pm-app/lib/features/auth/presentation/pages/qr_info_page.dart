// meta-service/pm-app/lib/features/auth/presentation/pages/qr_info_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';

/// A page that instructs the user to download an authenticator app,
/// providing QR codes that link to the App Store and Google Play Store.
class QrInfoPage extends StatelessWidget {
  const QrInfoPage({super.key});

  // Links to Google Authenticator on both stores.
  final String _appStoreUrl =
      'https://apps.apple.com/us/app/google-authenticator/id388497605';
  final String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2';

  /// Generates a URL for a QR code image from the provided data string.
  String _getQrCodeUrl(String data) {
    return 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$data';
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
              'Download Authenticator App',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'To secure your account, you need an authenticator app. Scan one of the QR codes below to download an app like Google Authenticator, or find one of your choice in your device\'s app store.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQrCode(
                  context: context,
                  label: 'App Store',
                  url: _appStoreUrl,
                ),
                _buildQrCode(
                  context: context,
                  label: 'Google Play',
                  url: _playStoreUrl,
                ),
              ],
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Got the App? Go Back',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a widget to display a QR code image with a label underneath.
  Widget _buildQrCode({
    required BuildContext context,
    required String label,
    required String url,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Flexible(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300)),
            child: Image.network(
              _getQrCodeUrl(url),
              width: 120,
              height: 120,
              errorBuilder: (ctx, err, st) => const Icon(
                Icons.qr_code_scanner_rounded,
                size: 120,
                color: Colors.grey,
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const SizedBox(
                  width: 120,
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(label, style: textTheme.titleMedium),
        ],
      ),
    );
  }
}