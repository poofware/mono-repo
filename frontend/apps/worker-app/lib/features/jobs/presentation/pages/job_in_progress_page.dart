// frontend/apps/worker-app/lib/features/jobs/presentation/pages/job_in_progress_page.dart

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_map_page.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/slide_button_widget.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/features/jobs/state/jobs_state.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class JobInProgressPage extends ConsumerStatefulWidget {
  final JobInstance job;
  final JobMapPage preWarmedMap;
  const JobInProgressPage({
    super.key,
    required this.job,
    required this.preWarmedMap,
  });
  @override
  ConsumerState<JobInProgressPage> createState() => _JobInProgressPageState();
}

class _JobInProgressPageState extends ConsumerState<JobInProgressPage> {
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;

  bool _isTakingPhoto = false;
  final Set<String> _verifyingUnitIds = {};

  static const int _bagLimit = 8;

  @override
  void initState() {
    super.initState();
    if (widget.job.checkInAt != null) {
      _elapsedTime = DateTime.now().toUtc().difference(
        widget.job.checkInAt!.toUtc(),
      );
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedTime += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _contactSupport() {
    final l10n = AppLocalizations.of(context);
    const supportEmail = 'team@thepoofapp.com';
    const supportPhone = '2564683659';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    l10n.workerDrawerHelpSupport,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: Text(
                    l10n.howToCompleteAJobTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  leading: const Icon(Icons.checklist_rtl_outlined),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        l10n.howToCompleteAJobBody.replaceAll('**', ''),
                        style: TextStyle(
                          height: 1.6,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.sms_outlined),
                  title: Text(l10n.contactSupportText),
                  onTap: () {
                    launchUrl(Uri.parse('sms:$supportPhone'));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(l10n.contactSupportEmail),
                  onTap: () {
                    final subject = Uri.encodeComponent(
                      l10n.emailSubjectGeneralHelp,
                    );
                    launchUrl(
                      Uri.parse('mailto:$supportEmail?subject=$subject'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleCancel() async {
    final appLocalizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.cancelJobInProgressTitle),
        content: Text(appLocalizations.cancelJobInProgressBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appLocalizations.cancelJobBackButton),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appLocalizations.cancelJobConfirmButton),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    if (mounted) {
      final navigator = Navigator.of(context);
      final router = GoRouter.of(context);

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _CancelingDialogWidget(),
      );

      final wasSuccess = await ref
          .read(jobsNotifierProvider.notifier)
          .cancelJob(widget.job.instanceId);

      if (mounted) {
        navigator.pop(); // close the loading dialog
        if (wasSuccess) {
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            router.goNamed(AppRouteNames.mainTab);
          }
        }
      }
    }
  }

  void _openFullMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobMapPage(job: widget.job, buildAsScaffold: true),
      ),
    );
  }

  Future<void> _takePhoto(
    UnitVerification unit, {
    bool missingTrashCan = false,
  }) async {
    // START of MODIFICATION
    final job = ref.read(jobsNotifierProvider).inProgressJob ?? widget.job;
    final bagsCollected = job.buildings
        .expand((b) => b.units)
        .where(
          (u) =>
              u.status == UnitVerificationStatus.verified && !u.missingTrashCan,
        )
        .length;

    if (bagsCollected >= _bagLimit && !missingTrashCan) {
      _showBagLimitDialog();
      return;
    }
    // END of MODIFICATION

    if (_isTakingPhoto) return;
    setState(() {
      _isTakingPhoto = true;
    });

    final picker = ImagePicker();
    try {
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        imageQuality: 80,
      );

      if (!mounted || photo == null) {
        setState(() {
          _isTakingPhoto = false;
        });
        return;
      }

      final l10n = AppLocalizations.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.jobInProgressPhotoConfirmDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(File(photo.path), fit: BoxFit.contain),
              const SizedBox(height: 16),
              Text(l10n.jobInProgressPhotoConfirmDialogContent),
              const SizedBox(height: 8),
              Text(
                l10n.jobInProgressPhotoInstructions,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.jobInProgressPhotoConfirmDialogRetake),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.jobInProgressPhotoConfirmDialogConfirm),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await ensureLocationGranted();
        setState(() {
          _verifyingUnitIds.add(unit.unitId);
        });
        unawaited(
          ref
              .read(jobsNotifierProvider.notifier)
              .verifyUnitPhoto(
                unit.unitId,
                photo,
                missingTrashCan: missingTrashCan,
              )
              .whenComplete(() {
                if (mounted) {
                  setState(() {
                    _verifyingUnitIds.remove(unit.unitId);
                  });
                }
              }),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
        });
      }
    }
  }

  void _showBagLimitDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.info_outline, size: 48),
        title: Text(l10n.bagLimitDialogTitle),
        content: Text(l10n.bagLimitDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.okButtonLabel),
          ),
        ],
      ),
    );
  }

  void _showBagsCollectedHelp() {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.bagsCollectedHelpTitle),
        content: Text(l10n.bagsCollectedHelpBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.okButtonLabel),
          ),
        ],
      ),
    );
  }

  void _showFailureReason(UnitVerification unit) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.jobInProgressFailureReasonTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unit.failureReasons.isEmpty)
              Text(l10n.jobInProgressFailureReasonUnknown)
            else
              ...unit.failureReasons.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Icon(_failureReasonIcon(r), size: 20, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_failureReasonLabel(r, l10n))),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.okButtonLabel),
          ),
        ],
      ),
    );
  }

  void _showPermanentFailureDialog(UnitVerification unit) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.block, color: Colors.red, size: 48),
        title: Text(
          l10n.jobInProgressUnitPermanentlyFailedTitle(unit.unitNumber),
        ),
        content: Text(l10n.jobInProgressUnitPermanentlyFailedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.okButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _dumpBags() async {
    final success = await ref.read(jobsNotifierProvider.notifier).dumpBags();
    if (success && mounted) {
      final job = ref.read(jobsNotifierProvider).inProgressJob;
      if (job == null) {
        if (mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.goNamed(AppRouteNames.mainTab);
          }
        }
      }
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  IconData _failureReasonIcon(String code) {
    switch (code) {
      case 'TRASH_CAN_NOT_VISIBLE':
        return Icons.delete_outline;
      case 'TRASH_BAG_VISIBLE':
        return Icons.delete;
      case 'DOOR_NUMBER_MISMATCH':
        return Icons.numbers;
      case 'DOOR_NUMBER_MISSING':
        return Icons.help_outline;
      case 'DOOR_NOT_FULLY_VISIBLE':
        return Icons.door_front_door;
      default:
        return Icons.error_outline;
    }
  }

  String _failureReasonLabel(String code, AppLocalizations l10n) {
    switch (code) {
      case 'TRASH_CAN_NOT_VISIBLE':
        return l10n.failureReasonTrashCanNotVisible;
      case 'TRASH_BAG_VISIBLE':
        return l10n.failureReasonTrashBagVisible;
      case 'DOOR_NUMBER_MISMATCH':
        return l10n.failureReasonDoorMismatch;
      case 'DOOR_NUMBER_MISSING':
        return l10n.failureReasonDoorMissing;
      case 'DOOR_NOT_FULLY_VISIBLE':
        return l10n.failureReasonDoorNotFullyVisible;
      default:
        return l10n.jobInProgressFailureReasonUnknown;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  UI BUILDER WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(JobInstance job, AppLocalizations l10n) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: l10n.jobInProgressContactSupport,
              onPressed: _contactSupport,
            ),
            Expanded(
              child: Text(
                job.property.propertyName,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.jobInProgressCancelButton,
              onPressed: _handleCancel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPreview() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 4,
        shadowColor: Colors.black.withAlpha(51),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            SizedBox(height: 180, child: widget.preWarmedMap),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _openFullMap,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap:
                    _openFullMap, // Add tap handler specifically for the button
                child: Container(
                  padding: const EdgeInsets.all(
                    4,
                  ), // Increased padding for a better tap target
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.open_in_full,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBar(int bagsCollected, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _showBagsCollectedHelp,
              child: _buildStatItem(
                Icons.shopping_bag_outlined,
                l10n.jobInProgressBagsCollectedLabel,
                '$bagsCollected / $_bagLimit',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatItem(
              Icons.timer_outlined,
              l10n.jobInProgressTimeElapsed,
              _formatDuration(_elapsedTime),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsPanel(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(
            color: AppColors.poofColor.withAlpha(204),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline, color: AppColors.poofColor),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.jobInProgressPhotoInstructions)),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingTile(Building b, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final unprocessedUnits = b.units
        .where(
          (u) =>
              u.status != UnitVerificationStatus.dumped &&
              !(u.status == UnitVerificationStatus.failed &&
                  u.permanentFailure),
        )
        .toList();

    if (unprocessedUnits.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withAlpha(31),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: theme.copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            backgroundColor: theme.cardColor,
            collapsedBackgroundColor: theme.cardColor,
            title: Text(
              b.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: unprocessedUnits
                .map((u) => _buildUnitListItem(u, l10n))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildUnitListItem(UnitVerification u, AppLocalizations l10n) {
    IconData icon;
    Color color;
    String label;
    switch (u.status) {
      case UnitVerificationStatus.verified:
        icon = Icons.check_circle;
        color = Colors.green;
        label = l10n.jobInProgressUnitStatusVerified;
        break;
      case UnitVerificationStatus.dumped:
        icon = Icons.delete;
        color = Colors.orange;
        label = l10n.jobInProgressUnitStatusDumped;
        break;
      case UnitVerificationStatus.failed:
        icon = u.permanentFailure ? Icons.block : Icons.error;
        color = Colors.red;
        label = u.permanentFailure
            ? l10n.jobInProgressUnitStatusFailedPermanent
            : l10n.jobInProgressUnitStatusFailed;
        break;
      default:
        icon = Icons.hourglass_bottom;
        color = Colors.grey;
        label = l10n.jobInProgressUnitStatusPending;
    }

    final waiting = _verifyingUnitIds.contains(u.unitId);
    final canTakePhoto =
        u.status == UnitVerificationStatus.pending ||
        (u.status == UnitVerificationStatus.failed && !u.permanentFailure);

    Widget trailing;
    if (canTakePhoto) {
      final cameraBtn = waiting
          ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () => _takePhoto(u),
            );
      final menuBtn = PopupMenuButton<String>(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.jobInProgressMoreOptionsTooltip,
        onSelected: (val) {
          if (val == 'missing') {
            _takePhoto(u, missingTrashCan: true);
          } else if (val == 'reason') {
            _showFailureReason(u);
          }
        },
        itemBuilder: (context) => [
          if (u.status == UnitVerificationStatus.failed)
            PopupMenuItem(
              value: 'reason',
              child: Text(l10n.jobInProgressFailureReasonTitle),
            ),
          PopupMenuItem(
            value: 'missing',
            child: Text(l10n.jobInProgressReportMissingTrashCan),
          ),
        ],
      );
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [cameraBtn, menuBtn],
      );
    } else {
      if (u.status == UnitVerificationStatus.failed) {
        trailing = PopupMenuButton<String>(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          icon: const Icon(Icons.more_vert),
          tooltip: l10n.jobInProgressMoreOptionsTooltip,
          onSelected: (val) {
            if (val == 'reason') _showFailureReason(u);
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'reason',
              child: Text(l10n.jobInProgressFailureReasonTitle),
            ),
          ],
        );
      } else {
        trailing = Icon(icon, color: color);
      }
    }

    final tile = ListTile(
      leading: Icon(icon, color: color),
      title: Row(
        children: [
          Text('Unit ${u.unitNumber}'),
          const SizedBox(width: 8),
          _buildStatusChip(color, label),
        ],
      ),
      trailing: trailing,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: tile,
    );
  }

  Widget _buildStatusChip(Color c, String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withAlpha(38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        t,
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildBottomActionBar(
    String text,
    IconData icon,
    bool enabled,
    Future<void> Function()? onSubmit,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 36.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: SlideAction(
          text: text,
          outerColor: enabled ? AppColors.poofColor : Colors.grey.shade400,
          innerColor: Colors.white,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          sliderButtonIcon: Icon(
            icon,
            color: enabled ? AppColors.poofColor : Colors.grey,
          ),
          sliderRotate: false,
          enabled: enabled,
          onSubmit: onSubmit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(jobsNotifierProvider);
    final job = state.inProgressJob ?? widget.job;

    // Listen for units that become permanently failed and show a dialog.
    ref.listen<JobsState>(jobsNotifierProvider, (previous, next) {
      final prevJob = previous?.inProgressJob;
      final nextJob = next.inProgressJob;

      if (prevJob != null && nextJob != null) {
        final prevUnits = prevJob.buildings.expand((b) => b.units);
        final nextUnits = nextJob.buildings.expand((b) => b.units);

        for (final nextUnit in nextUnits) {
          final prevUnit = prevUnits.firstWhereOrNull(
            (u) => u.unitId == nextUnit.unitId,
          );
          if (prevUnit != null) {
            final wasPermanentFailure = prevUnit.permanentFailure;
            final isPermanentFailure = nextUnit.permanentFailure;

            if (!wasPermanentFailure && isPermanentFailure) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _showPermanentFailureDialog(nextUnit);
                }
              });
            }
          }
        }
      }
    });

    final allUnits = job.buildings.expand((b) => b.units);
    final verifiedCount = allUnits
        .where(
          (u) =>
              u.status == UnitVerificationStatus.verified && !u.missingTrashCan,
        )
        .length;
    final dumpedCount = allUnits
        .where((u) => u.status == UnitVerificationStatus.dumped)
        .length;
    final permFailedCount = allUnits.where((u) => u.permanentFailure).length;
    final totalUnits = allUnits.length;

    final pendingAndTempFailedCount = allUnits
        .where(
          (u) =>
              u.status == UnitVerificationStatus.pending ||
              (u.status == UnitVerificationStatus.failed &&
                  !u.permanentFailure),
        )
        .length;

    final allUnitsAccountedFor = (dumpedCount + permFailedCount) >= totalUnits;
    final hasBagsToDump = verifiedCount > 0;

    String slideText;
    IconData slideIcon;
    bool slideEnabled;
    Future<void> Function()? slideAction;

    if (allUnitsAccountedFor && !hasBagsToDump) {
      slideText = l10n.jobInProgressCompleteJobAction;
      slideIcon = Icons.check;
      slideEnabled = true;
      slideAction = _dumpBags;
    } else if (pendingAndTempFailedCount == 0 && hasBagsToDump) {
      slideText = l10n.jobInProgressCompleteJobAction;
      slideIcon = Icons.check;
      slideEnabled = true;
      slideAction = _dumpBags;
    } else {
      slideText = l10n.jobInProgressDumpBagsAction;
      slideIcon = Icons.delete;
      slideEnabled = hasBagsToDump;
      slideAction = hasBagsToDump ? _dumpBags : null;
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        body: Column(
          children: [
            _buildHeader(job, l10n),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  _buildMapPreview(),
                  _buildStatsBar(verifiedCount, l10n),
                  _buildInstructionsPanel(l10n),
                  ...job.buildings.map((b) => _buildBuildingTile(b, l10n)),
                ],
              ),
            ),
            _buildBottomActionBar(
              slideText,
              slideIcon,
              slideEnabled,
              slideAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelingDialogWidget extends StatelessWidget {
  const _CancelingDialogWidget();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.cancelJobCancellingMessage,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}

/// Counts the number of units that have been successfully verified AND do not have
/// the missing trash can flag set.
int bagCount(JobInstance job) {
  return job.buildings
      .expand((b) => b.units)
      .where(
        (u) =>
            u.status == UnitVerificationStatus.verified && !u.missingTrashCan,
      )
      .length;
}
