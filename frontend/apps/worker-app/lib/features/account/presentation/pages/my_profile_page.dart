import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

import 'checkr_outcome_page.dart';
import 'saving_overlay.dart';
import '../widgets/profile_form_fields.dart';

class MyProfilePage extends ConsumerStatefulWidget {
  const MyProfilePage({super.key});

  @override
  ConsumerState<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends ConsumerState<MyProfilePage> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _tenantTokenController;

  AddressResolved? _addressState;
  String _aptSuite = '';
  int _vehicleYear = 0;
  String _vehicleMake = '';
  String _vehicleModel = '';

  Worker? _originalWorker;

  bool _hasInitializedFields = false;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isFormValid = true;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _tenantTokenController = TextEditingController();
    _firstNameController.addListener(_validateForm);
    _lastNameController.addListener(_validateForm);
    _emailController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);
    _tenantTokenController.addListener(_validateForm);
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_validateForm);
    _lastNameController.removeListener(_validateForm);
    _emailController.removeListener(_validateForm);
    _phoneController.removeListener(_validateForm);
    _tenantTokenController.removeListener(_validateForm);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _tenantTokenController.dispose();
    super.dispose();
  }

  void _validateForm() {
    final areRequiredFieldsFilled =
        _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        _emailController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _addressState != null &&
        _vehicleYear > 0 &&
        _vehicleMake.isNotEmpty &&
        _vehicleModel.isNotEmpty;

    bool hasChanges = false;
    final w = _originalWorker;
    if (w != null) {
      final tokenText = _tenantTokenController.text.trim();
      hasChanges =
          _firstNameController.text.trim() != w.firstName ||
          _lastNameController.text.trim() != w.lastName ||
          _emailController.text.trim() != w.email ||
          _phoneController.text.trim() != w.phoneNumber ||
          (_addressState != null &&
              (_addressState!.street != w.streetAddress ||
                  _addressState!.city != w.city ||
                  _addressState!.state != w.state ||
                  _addressState!.postalCode != w.zipCode)) ||
          _aptSuite != (w.aptSuite ?? '') ||
          _vehicleYear != w.vehicleYear ||
          _vehicleMake != w.vehicleMake ||
          _vehicleModel != w.vehicleModel ||
          tokenText != (w.tenantToken ?? '');
    }

    final shouldEnableSave = areRequiredFieldsFilled && hasChanges;

    if (shouldEnableSave != _isFormValid) {
      setState(() {
        _isFormValid = shouldEnableSave;
      });
    }
  }

  Future<void> _showCheckrOutcomePage() async {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Checkr Outcome',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const CheckrOutcomePage(),
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  Worker get _dummyWorker => Worker(
    id: 'dummy-worker-id',
    email: 'jane.doe@example.com',
    phoneNumber: '+1 555-555-1234',
    firstName: 'Jane',
    lastName: 'Doe',
    streetAddress: '123 Mockingbird Ln',
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
    onWaitlist: false,
    waitlistReason: WaitlistReason.none,
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isTestMode = PoofWorkerFlavorConfig.instance.testMode;
    final Worker? worker = isTestMode
        ? _dummyWorker
        : ref.watch(workerStateNotifierProvider).worker;

    if (!isTestMode && worker == null) {
      return _LoadingScaffold(appLocalizations: t);
    }

    if (!_hasInitializedFields && worker != null) {
      _populateControllers(worker);
      _hasInitializedFields = true;
    }

    final fullName = '${worker?.firstName ?? ''} ${worker?.lastName ?? ''}'
        .trim();

    final accountManagementTiles = <Widget>[
      if (worker?.accountStatus == AccountStatusType.backgroundCheckPending)
        _StatefulLinkTile(
          icon: Icons.hourglass_top_outlined,
          title: t.myProfilePageCheckStatusButton,
          subtitle: t.myProfilePageCheckStatusSubtitle,
          onTap: _showCheckrOutcomePage,
        ),
      _StatefulLinkTile(
        icon: Icons.credit_card_outlined,
        title: t.myProfilePageManagePaymentsButton,
        subtitle: t.myProfilePageManagePaymentsSubtitle,
        onTap: _handleManagePayouts,
      ),
      _StatefulLinkTile(
        icon: Icons.policy_outlined,
        title: t.myProfilePageManageBackgroundCheckButton,
        subtitle: t.myProfilePageManageBackgroundCheckSubtitle,
        onTap: () => _launchUrl('https://candidate.checkr.com/'),
      ),
    ];

    final profileScaffold = Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
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
                      t.myProfilePageTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _isEditing
                            ? TextButton(
                                onPressed: () => _cancelEdit(worker!),
                                child: Text(t.myProfilePageCancelButton),
                              )
                            : TextButton(
                                onPressed: () =>
                                    setState(() => _isEditing = true),
                                child: Text(t.myProfilePageEditButton),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildProfileHeader(theme, worker!, fullName, t),
                      _buildSection(
                        title: t.myProfilePageContactSection,
                        children: [
                          _buildEditableProfileField(
                            controller: _firstNameController,
                            label: t.myProfilePageFirstNameLabel,
                            icon: Icons.person_outline,
                            isEditing: _isEditing,
                          ),
                          _buildEditableProfileField(
                            controller: _lastNameController,
                            label: t.myProfilePageLastNameLabel,
                            icon: Icons.person_outline,
                            isEditing: _isEditing,
                          ),
                          _buildEditableProfileField(
                            controller: _emailController,
                            label: t.myProfilePageEmailLabel,
                            icon: Icons.email_outlined,
                            isEditing: _isEditing,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          _buildEditableProfileField(
                            controller: _phoneController,
                            label: t.myProfilePagePhoneLabel,
                            icon: Icons.phone_outlined,
                            isEditing: _isEditing,
                            keyboardType: TextInputType.phone,
                          ),
                          AddressFormField(
                            initialStreet: worker.streetAddress,
                            initialAptSuite: worker.aptSuite ?? '',
                            initialCity: worker.city,
                            initialState: worker.state,
                            initialZip: worker.zipCode,
                            isEditing: _isEditing,
                            onChanged: (resolved, apt) {
                              setState(() {
                                _addressState = resolved;
                                _aptSuite = apt;
                                _validateForm();
                              });
                            },
                          ),
                        ],
                      ),
                      _buildSection(
                        title: t.myProfilePageVehicleSection,
                        children: [
                          VehicleFormField(
                            initialYear: worker.vehicleYear,
                            initialMake: worker.vehicleMake,
                            initialModel: worker.vehicleModel,
                            isEditing: _isEditing,
                            onChanged: (year, make, model) {
                              setState(() {
                                _vehicleYear = year;
                                _vehicleMake = make;
                                _vehicleModel = model;
                                _validateForm();
                              });
                            },
                          ),
                        ],
                      ),
                      _buildSection(
                        title: t.myProfilePageResidentProgramTitle,
                        children: [_buildTenantTokenSectionContent(worker, t)],
                      ),
                      _buildSection(
                        title: t.myProfilePageAccountManagementSection,
                        children: accountManagementTiles,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isEditing)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: WelcomeButton(
                    text: _isSaving
                        ? t.myProfilePageSavingButton
                        : t.myProfilePageSaveChangesButton,
                    isLoading: _isSaving,
                    showSpinner: false,
                    onPressed: _isFormValid ? () => _saveProfile(worker) : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [profileScaffold, if (_isSaving) const SavingOverlay()],
    );
  }

  Widget _buildTenantTokenSectionContent(Worker worker, AppLocalizations t) {
    final theme = Theme.of(context);

    if (_tenantTokenController.text.isEmpty &&
        (worker.tenantToken?.isNotEmpty ?? false)) {
      _tenantTokenController.text = worker.tenantToken!;
    }

    final token = _tenantTokenController.text;
    final hasToken = token.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 8,
          ),
          minLeadingWidth: 32,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
            child: const Icon(Icons.key_outlined, size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  t.myProfilePageTokenLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (hasToken && !_isEditing) _buildStatusChip(theme, 'Connected'),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _isEditing
                ? TextField(
                    controller: _tenantTokenController,
                    keyboardType: TextInputType.text,
                    decoration:
                        _customInputDecoration(
                          labelText: t.myProfilePageTokenLabel,
                        ).copyWith(
                          // No prefix icon here to avoid duplicating the leading icon
                          hintText: 'abc123…',
                          suffixIcon: IconButton(
                            tooltip: 'Paste',
                            icon: const Icon(Icons.paste_rounded),
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                'text/plain',
                              );
                              final value = data?.text ?? '';
                              if (value.isNotEmpty) {
                                setState(
                                  () => _tenantTokenController.text = value,
                                );
                              }
                            },
                          ),
                        ),
                  )
                : hasToken
                ? SelectableText(
                    token,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  )
                : Text(
                    t.myProfilePageResidentProgramDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          trailing: !_isEditing && hasToken
              ? IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: token));
                    if (mounted) {
                      showAppSnackBar(context, const Text('Token copied'));
                    }
                  },
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildStatusChip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(
    ThemeData theme,
    Worker worker,
    String fullName,
    AppLocalizations t,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Fix: need at least two colors in gradient
              gradient: LinearGradient(
                colors: [
                  AppColors.poofColor.withAlpha(128),
                  AppColors.poofColor, // second color added
                ],
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
            fullName.isEmpty ? t.myProfilePageYourNameFallback : fullName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8, left: 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        layoutBuilder: (currentChild, previousChildren) =>
            currentChild ?? const SizedBox.shrink(),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: isEditing
            ? TextField(
                key: ValueKey('${label}_edit'),
                controller: controller,
                keyboardType: keyboardType,
                decoration: _customInputDecoration(labelText: label),
              )
            : ProfileReadOnlyField(
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

  void _populateControllers(Worker w) {
    _originalWorker = w;
    _firstNameController.text = w.firstName;
    _lastNameController.text = w.lastName;
    _emailController.text = w.email;
    _phoneController.text = w.phoneNumber;
    _addressState = AddressResolved(
      street: w.streetAddress,
      city: w.city,
      state: w.state,
      postalCode: w.zipCode,
    );
    _aptSuite = w.aptSuite ?? '';
    _vehicleYear = w.vehicleYear;
    _vehicleMake = w.vehicleMake;
    _vehicleModel = w.vehicleModel;
    _tenantTokenController.text = w.tenantToken ?? '';
    _validateForm();
  }

  void _cancelEdit(Worker worker) {
    _populateControllers(worker);
    setState(() {
      _isEditing = false;
      _isFormValid = true;
    });
  }

  Future<void> _launchUrl(String url) async {
    final success = await tryLaunchUrl(url);
    if (!mounted) return;
    if (!success) {
      final t = AppLocalizations.of(context);
      showAppSnackBar(context, Text(t.urlLauncherCannotLaunch));
    }
  }

  Future<void> _handleManagePayouts() async {
    final BuildContext capturedContext = context;

    try {
      final repo = ref.read(workerAccountRepositoryProvider);
      final loginLinkUrl = await repo.getStripeExpressLoginLink();
      final success = await tryLaunchUrl(loginLinkUrl);
      if (!success && capturedContext.mounted) {
        showAppSnackBar(
          capturedContext,
          Text(AppLocalizations.of(capturedContext).urlLauncherCannotLaunch),
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
    if (_firstNameController.text.trim() != worker.firstName) {
      patchFields['first_name'] = _firstNameController.text.trim();
    }
    if (_lastNameController.text.trim() != worker.lastName) {
      patchFields['last_name'] = _lastNameController.text.trim();
    }
    if (_emailController.text.trim() != worker.email) {
      patchFields['email'] = _emailController.text.trim();
    }
    if (_phoneController.text.trim() != worker.phoneNumber) {
      patchFields['phone_number'] = _phoneController.text.trim();
    }

    if (_addressState != null) {
      if (_addressState!.street != worker.streetAddress) {
        patchFields['street_address'] = _addressState!.street;
      }
      if (_addressState!.city != worker.city) {
        patchFields['city'] = _addressState!.city;
      }
      if (_addressState!.state != worker.state) {
        patchFields['state'] = _addressState!.state;
      }
      if (_addressState!.postalCode != worker.zipCode) {
        patchFields['zip_code'] = _addressState!.postalCode;
      }
    }

    if (_aptSuite != (worker.aptSuite ?? '')) {
      patchFields['apt_suite'] = _aptSuite;
    }

    if (_vehicleYear != worker.vehicleYear) {
      patchFields['vehicle_year'] = _vehicleYear;
    }
    if (_vehicleMake != worker.vehicleMake) {
      patchFields['vehicle_make'] = _vehicleMake;
    }
    if (_vehicleModel != worker.vehicleModel) {
      patchFields['vehicle_model'] = _vehicleModel;
    }
    if (_tenantTokenController.text.trim() != (worker.tenantToken ?? '')) {
      patchFields['tenant_token'] = _tenantTokenController.text.trim();
    }

    final isTestMode = PoofWorkerFlavorConfig.instance.testMode;
    if (isTestMode) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isEditing = false;
        });
      }
      return;
    }

    if (patchFields.isEmpty) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      return;
    }

    final workerAuthRepo = ref.read(workerAuthRepositoryProvider);
    try {
      if (patchFields.containsKey('phone_number')) {
        await workerAuthRepo.checkPhoneValid(patchFields['phone_number']);
      }
      if (patchFields.containsKey('email')) {
        await workerAuthRepo.checkEmailValid(patchFields['email']);
      }
      if (!capturedContext.mounted) return;
      await _attemptPatch(patchFields, capturedContext);
    } on Exception catch (e) {
      if (!capturedContext.mounted) return;
      _showError(capturedContext, e);
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _attemptPatch(
    Map<String, dynamic> changedFields,
    BuildContext context,
  ) async {
    final repo = ref.read(workerAccountRepositoryProvider);

    final patchRequest = WorkerPatchRequest(
      firstName: changedFields['first_name'],
      lastName: changedFields['last_name'],
      email: changedFields['email'],
      phoneNumber: changedFields['phone_number'],
      streetAddress: changedFields['street_address'],
      aptSuite: changedFields['apt_suite'],
      city: changedFields['city'],
      state: changedFields['state'],
      zipCode: changedFields['zip_code'],
      vehicleYear: changedFields['vehicle_year'],
      vehicleMake: changedFields['vehicle_make'],
      vehicleModel: changedFields['vehicle_model'],
      tenantToken: changedFields['tenant_token'],
    );

    try {
      await repo.patchWorker(patchRequest);
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        Text(AppLocalizations.of(context).myProfilePageProfileUpdatedSnackbar),
      );
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
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
      extra: PhoneVerificationInfoArgs(
        phoneNumber: phone,
        onSuccess: null,
        goToTotpAfterSuccess: false,
      ),
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
    showAppSnackBar(context, Text(message));
  }

  String _initialsFromWorker(Worker w) {
    final f = w.firstName.isNotEmpty ? w.firstName[0] : '';
    final l = w.lastName.isNotEmpty ? w.lastName[0] : '';
    final initials = (f + l).toUpperCase().trim();
    return initials.isEmpty ? 'U' : initials;
  }
}

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
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        widget.subtitle,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : const Icon(Icons.chevron_right),
      onTap: _isLoading ? null : _handleTap,
    );
  }
}
