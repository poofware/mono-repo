// lib/features/account/presentation/pages/my_profile_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/features/account/data/models/checkr.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_worker/features/account/data/models/worker.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/features/auth/presentation/pages/phone_verification_info_page.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/core/config/flavors.dart';

import 'checkr_outcome_page.dart';
import 'saving_overlay.dart';

class MyProfilePage extends ConsumerStatefulWidget {
  const MyProfilePage({super.key});

  @override
  ConsumerState<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends ConsumerState<MyProfilePage> {
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _yearController;
  late final TextEditingController _makeController;
  late final TextEditingController _modelController;
  late final TextEditingController _addressController;

  bool _hasInitializedFields = false;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _yearController = TextEditingController();
    _makeController = TextEditingController();
    _modelController = TextEditingController();
    _addressController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _yearController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // A helper function to present the CheckrOutcomePage as a modal sheet.
  Future<void> _showCheckrOutcomePage() async {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Checkr Outcome', // Accessibility label for the barrier.
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const CheckrOutcomePage(),
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    );
  }

  // 0. Dummy data used exclusively in test-mode
  Worker get _dummyWorker => Worker(
        id: 'dummy-worker-id',
        email: 'jane.doe@example.com',
        phoneNumber: '+1 555-555-1234',
        firstName: 'Jane',
        lastName: 'Doe',
        streetAddress: '123 Mockingbird Ln, Springfield, IL 62704',
        aptSuite: 'Apt 4B',
        city: 'Springfield',
        state: 'IL',
        zipCode: '62704',
        vehicleYear: 2020,
        vehicleMake: 'Tesla',
        vehicleModel: 'Model Y',
        accountStatus: AccountStatusType.active,
        setupProgress: SetupProgressType.done,
        checkrReportOutcome: CheckrReportOutcome.approved,
      );

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isTestMode = PoofWorkerFlavorConfig.instance.testMode;
    final Worker? worker =
        isTestMode ? _dummyWorker : ref.watch(workerStateNotifierProvider).worker;

    if (!isTestMode && worker == null) {
      return _LoadingScaffold(appLocalizations: appLocalizations);
    }

    if (!_hasInitializedFields && worker != null) {
      _populateControllers(worker);
      _hasInitializedFields = true;
    }

    final fullName =
        '${worker?.firstName ?? ''} ${worker?.lastName ?? ''}'.trim();

    // Dynamically build the list of account management tiles
    final accountManagementTiles = <Widget>[
      // Conditionally add the status check tile
      if (worker?.accountStatus == AccountStatusType.backgroundCheckPending)
        _StatefulLinkTile(
          icon: Icons.hourglass_top_outlined,
          title: appLocalizations.myProfilePageCheckStatusButton,
          subtitle: appLocalizations.myProfilePageCheckStatusSubtitle,
          onTap: _showCheckrOutcomePage,
        ),
      // The permanent tiles
      _StatefulLinkTile(
        icon: Icons.credit_card_outlined,
        title: appLocalizations.myProfilePageManagePaymentsButton,
        subtitle: appLocalizations.myProfilePageManagePaymentsSubtitle,
        onTap: _handleManagePayouts,
      ),
      _StatefulLinkTile(
        icon: Icons.policy_outlined,
        title: appLocalizations.myProfilePageManageBackgroundCheckButton,
        subtitle: appLocalizations.myProfilePageManageBackgroundCheckSubtitle,
        onTap: () => _launchUrl('https://candidate.checkr.com/'),
      ),
    ];

    final profileScaffold = Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // --- Custom Header ---
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  Text(
                    appLocalizations.myProfilePageTitle,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    width: 80,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _isEditing
                          ? TextButton(
                              onPressed: () => _cancelEdit(worker!),
                              child: Text(
                                  appLocalizations.myProfilePageCancelButton))
                          : TextButton(
                              onPressed: () => setState(() => _isEditing = true),
                              child: Text(
                                  appLocalizations.myProfilePageEditButton)),
                    ),
                  ),
                ],
              ),
            ),
            // --- Scrollable Content Area ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // --- Avatar & Name Header ---
                    _buildProfileHeader(theme, worker!, fullName, appLocalizations),

                    // --- Contact Info Section ---
                    _buildSection(
                      title: appLocalizations.myProfilePageContactSection,
                      children: [
                        _buildEditableProfileField(
                          controller: _emailController,
                          label: appLocalizations.myProfilePageEmailLabel,
                          icon: Icons.email_outlined,
                          isEditing: _isEditing,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        _buildEditableProfileField(
                          controller: _phoneController,
                          label: appLocalizations.myProfilePagePhoneLabel,
                          icon: Icons.phone_outlined,
                          isEditing: _isEditing,
                          keyboardType: TextInputType.phone,
                        ),
                        _buildEditableProfileField(
                          controller: _addressController,
                          label: appLocalizations.myProfilePageAddressLabel,
                          icon: Icons.location_on_outlined,
                          isEditing: _isEditing,
                        ),
                      ],
                    ),

                    // --- Vehicle Info Section ---
                    _buildSection(
                      title: appLocalizations.myProfilePageVehicleSection,
                      children: [
                        _buildEditableProfileField(
                          controller: _yearController,
                          label: appLocalizations.myProfilePageVehicleYearLabel,
                          icon: Icons.calendar_today_outlined,
                          isEditing: _isEditing,
                          keyboardType: TextInputType.number,
                        ),
                        _buildEditableProfileField(
                          controller: _makeController,
                          label: appLocalizations.myProfilePageVehicleMakeLabel,
                          icon: Icons.factory_outlined,
                          isEditing: _isEditing,
                        ),
                        _buildEditableProfileField(
                          controller: _modelController,
                          label: appLocalizations.myProfilePageVehicleModelLabel,
                          icon: Icons.directions_car_outlined,
                          isEditing: _isEditing,
                        ),
                      ],
                    ),

                    // --- Account Management Section ---
                    _buildSection(
                      title:
                          appLocalizations.myProfilePageAccountManagementSection,
                      children: accountManagementTiles,
                    ),
                  ],
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
              ),
            ),

            // --- Sticky Save Button ---
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: WelcomeButton(
                  text: _isSaving
                      ? appLocalizations.myProfilePageSavingButton
                      : appLocalizations.myProfilePageSaveChangesButton,
                  isLoading: _isSaving,
                  showSpinner: false, // Use overlay spinner instead
                  onPressed: () => _saveProfile(worker),
                ),
              ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        profileScaffold,
        if (_isSaving) const SavingOverlay(),
      ],
    );
  }

  // --- NEW WIDGET BUILDERS for modern UI ---

  Widget _buildProfileHeader(ThemeData theme, Worker worker, String fullName, AppLocalizations appLocalizations) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.poofColor.withAlpha(128), AppColors.poofColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.surface,
              child: Text(
                _initialsFromWorker(worker),
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: AppColors.poofColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fullName.isEmpty ? appLocalizations.myProfilePageYourNameFallback : fullName,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8, left: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: List.generate(children.length, (index) {
              return Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
                child: children[index],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildEditableProfileField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isEditing = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    // Wrap the AnimatedSwitcher with AnimatedSize to fix the "jank".
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: isEditing
            ? TextField(
                key: ValueKey('${label}_edit'),
                controller: controller,
                keyboardType: keyboardType,
                decoration: _customInputDecoration(labelText: label),
              )
            : _ProfileReadOnlyField(
                key: ValueKey('${label}_view'),
                icon: icon,
                label: label,
                value: controller.text,
              ),
      ),
    );
  }

  InputDecoration _customInputDecoration({required String labelText}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: labelText,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.poofColor, width: 2),
      ),
    );
  }

  // --- Helper logic (mostly unchanged) ---
  void _populateControllers(Worker w) {
    _emailController.text = w.email;
    _phoneController.text = w.phoneNumber;
    _yearController.text = w.vehicleYear.toString();
    _makeController.text = w.vehicleMake;
    _modelController.text = w.vehicleModel;
    _addressController.text = w.streetAddress;
  }

  void _cancelEdit(Worker worker) {
    _populateControllers(worker);
    setState(() => _isEditing = false);
  }

  Future<void> _launchUrl(String url) async {
    final success = await tryLaunchUrl(url);
    if (!mounted) return;
    if (!success) {
        final appLocalizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appLocalizations.urlLauncherCannotLaunch)),
        );
    }
}

  Future<void> _handleManagePayouts() async {
    // This handler no longer sets the page-level _isSaving flag.
    // The loading state is now handled entirely within _StatefulLinkTile.
    final BuildContext capturedContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final repo = ref.read(workerAccountRepositoryProvider);
      final loginLinkUrl = await repo.getStripeExpressLoginLink();
      final success = await tryLaunchUrl(loginLinkUrl);
      if (!success && capturedContext.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(capturedContext).urlLauncherCannotLaunch)),
        );
      }
    } catch (e) {
      if (capturedContext.mounted) {
        _showError(capturedContext, e as Exception);
      }
    }
  }

  Future<void> _saveProfile(Worker worker) async {
    setState(() => _isSaving = true);

    final BuildContext capturedContext = context;

    final patchFields = <String, dynamic>{};
    final trimmedEmail = _emailController.text.trim();
    final trimmedPhone = _phoneController.text.trim();
    final trimmedAddress = _addressController.text.trim();
    final trimmedMake = _makeController.text.trim();
    final trimmedModel = _modelController.text.trim();
    final trimmedYearStr = _yearController.text.trim();
    final int? parsedYear = int.tryParse(trimmedYearStr.isEmpty ? '0' : trimmedYearStr);

    if (trimmedEmail != worker.email) patchFields['email'] = trimmedEmail;
    if (trimmedPhone != worker.phoneNumber) patchFields['phone_number'] = trimmedPhone;
    if (trimmedAddress != worker.streetAddress) patchFields['street_address'] = trimmedAddress;
    if (parsedYear != null && parsedYear != 0 && parsedYear != worker.vehicleYear) {
      patchFields['vehicle_year'] = parsedYear;
    }
    if (trimmedMake != worker.vehicleMake) patchFields['vehicle_make'] = trimmedMake;
    if (trimmedModel != worker.vehicleModel) patchFields['vehicle_model'] = trimmedModel;

    final isTestMode = PoofWorkerFlavorConfig.instance.testMode;
    if (isTestMode) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() { _isSaving = false; _isEditing = false; });
      return;
    }

    if (patchFields.isEmpty) {
      setState(() { _isSaving = false; _isEditing = false; });
      return;
    }

    final workerAuthRepo = ref.read(workerAuthRepositoryProvider);
    try {
      if (patchFields.containsKey('phone_number')) await workerAuthRepo.checkPhoneValid(trimmedPhone);
      if (patchFields.containsKey('email')) await workerAuthRepo.checkEmailValid(trimmedEmail);
      if (!capturedContext.mounted) return;
      await _attemptPatch(patchFields, capturedContext);
    } on Exception catch (e) {
      if (!capturedContext.mounted) return;
      _showError(capturedContext, e);
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _attemptPatch(Map<String, dynamic> changedFields, BuildContext context) async {
    final repo = ref.read(workerAccountRepositoryProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final appLocalizations = AppLocalizations.of(context);

    final patchRequest = WorkerPatchRequest(
      email: changedFields['email'],
      phoneNumber: changedFields['phone_number'],
      streetAddress: changedFields['street_address'],
      vehicleYear: changedFields['vehicle_year'],
      vehicleMake: changedFields['vehicle_make'],
      vehicleModel: changedFields['vehicle_model'],
    );

    try {
      await repo.patchWorker(patchRequest);
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(appLocalizations.myProfilePageProfileUpdatedSnackbar)));
      if (mounted) setState(() { _isSaving = false; _isEditing = false; });
    } on ApiException catch (e) {
      if (e.errorCode == 'phone_not_verified') {
        final newPhone = changedFields['phone_number'] as String?;
        if (newPhone == null || newPhone.isEmpty) {
          if (context.mounted) _showError(context, e);
          if (mounted) setState(() => _isSaving = false);
          return;
        }
        final success = await _startPhoneVerificationFlowAndWait(newPhone);
        if (success) {
          if (context.mounted) await _attemptPatch(changedFields, context);
        } else {
          if (mounted) setState(() => _isSaving = false);
        }
      } else {
        if (context.mounted) _showError(context, e);
        if (mounted) setState(() => _isSaving = false);
      }
    } catch (err) {
      if (context.mounted) _showError(context, err as Exception);
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _startPhoneVerificationFlowAndWait(String phone) async {
    if (!mounted) return false;
    final result = await context.pushNamed<bool>(
      AppRouteNames.phoneVerificationInfoPage,
      extra: PhoneVerificationInfoArgs(phoneNumber: phone, onSuccess: null),
    );
    return result == true;
  }

  void _showError(BuildContext context, Exception e) {
    if (!mounted) return;
    String message;
    if (e is ApiException) {
      message = userFacingMessage(context, e);
    } else {
      message = AppLocalizations.of(context).loginUnexpectedError(e.toString());
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _initialsFromWorker(Worker w) {
    final f = w.firstName.isNotEmpty ? w.firstName[0] : '';
    final l = w.lastName.isNotEmpty ? w.lastName[0] : '';
    final initials = (f + l).toUpperCase().trim();
    return initials.isEmpty ? 'U' : initials;
  }
}

/// A clean, read-only display for a profile field.
class _ProfileReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ProfileReadOnlyField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Simple loader scaffold used until Worker data arrives (prod only).
class _LoadingScaffold extends StatelessWidget {
  final AppLocalizations appLocalizations;
  const _LoadingScaffold({required this.appLocalizations});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appLocalizations.myProfilePageTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}

/// A stateful, tappable list tile for launching external links.
class _StatefulLinkTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  const _StatefulLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_StatefulLinkTile> createState() => _StatefulLinkTileState();
}

class _StatefulLinkTileState extends State<_StatefulLinkTile> {
  bool _isLoading = false;

  Future<void> _handleTap() async {
    if (!mounted || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      await widget.onTap();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(widget.icon, size: 32, color: theme.colorScheme.primary),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(widget.subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      trailing: _isLoading
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.chevron_right),
      onTap: _isLoading ? null : _handleTap,
    );
  }
}
