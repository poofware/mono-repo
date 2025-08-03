// worker-app/lib/features/jobs/presentation/pages/job_in_progress_page.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_map_page.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/slide_button_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/routing/router.dart';

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
  String? _verifyingUnitId;

  // Keep track of expansion state for better UX
  final Map<String, bool> _expansionState = {};

  static const int _bagLimit = 8;

  // --- CORE LOGIC (Kept intact, modernized dialogs) ---

  void _contactSupport() {
    final l10n = AppLocalizations.of(context);
    const supportEmail = 'team@thepoofapp.com';
    const supportPhone = '2564683659';
    showModalBottomSheet(
      context: context,
      // Modernized bottom sheet appearance
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.contactSupport, // Assuming this key exists
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.sms_outlined, color: AppColors.poofColor),
                title: Text(l10n.contactSupportText),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  launchUrl(Uri.parse('sms:$supportPhone'));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined, color: AppColors.poofColor),
                title: Text(l10n.contactSupportEmail),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final subject = Uri.encodeComponent(
                    l10n.emailSubjectGeneralHelp,
                  );
                  launchUrl(Uri.parse('mailto:$supportEmail?subject=$subject'));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobMapPage(job: widget.job, buildAsScaffold: true),
      ),
    );
  }

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

    // Initialize expansion state: Expand the first building that is NOT complete.
    // Sort buildings first for consistency
    final sortedBuildings = List<Building>.from(widget.job.buildings)
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final building in sortedBuildings) {
        final isComplete = building.units.every((u) =>
            u.status == UnitVerificationStatus.verified ||
            u.status == UnitVerificationStatus.dumped ||
            (u.status == UnitVerificationStatus.failed && u.permanentFailure));

        if (!isComplete) {
            _expansionState[building.buildingId] = true;
            break; // Stop after finding the first incomplete building
        }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _takePhoto(
    UnitVerification unit, {
    bool missingTrashCan = false,
  }) async {
    if (_isTakingPhoto) return;
    setState(() {
      _isTakingPhoto = true;
      _verifyingUnitId = unit.unitId;
    });

    final picker = ImagePicker();
    try {
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (!mounted || photo == null) {
        setState(() {
          _isTakingPhoto = false;
          _verifyingUnitId = null;
        });
        return;
      }

      final l10n = AppLocalizations.of(context);
      // Modernized Dialog UI
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.jobInProgressPhotoConfirmDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(photo.path), fit: BoxFit.contain)
              ),
              const SizedBox(height: 16),
              Text(l10n.jobInProgressPhotoConfirmDialogContent),
              const SizedBox(height: 8),
              Text(
                l10n.jobInProgressPhotoInstructions,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.jobInProgressPhotoConfirmDialogRetake),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.poofColor,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.jobInProgressPhotoConfirmDialogConfirm),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await ensureLocationGranted();
        await ref
            .read(jobsNotifierProvider.notifier)
            .verifyUnitPhoto(
              unit.unitId,
              photo,
              missingTrashCan: missingTrashCan,
            );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _verifyingUnitId = null;
        });
      }
    }
  }

  Future<void> _dumpBags() async {
    final success = await ref.read(jobsNotifierProvider.notifier).dumpBags();
    if (success && mounted) {
      final job = ref.read(jobsNotifierProvider).inProgressJob;
      if (job == null) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.goNamed(AppRouteNames.mainTab);
        }
      }
    }
  }

  Future<void> _handleCancel() async {
    final appLocalizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

    if (confirmed != true) return;

    final wasSuccess = await ref
        .read(jobsNotifierProvider.notifier)
        .cancelJob(widget.job.instanceId);
    if (mounted && wasSuccess) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed(AppRouteNames.mainTab);
      }
    }
  }

  void _showFailureReason(UnitVerification unit) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    children: [
                      Icon(_failureReasonIcon(r), size: 20, color: Colors.redAccent),
                      const SizedBox(width: 12),
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

  // --- HELPER FUNCTIONS ---

  int _permanentFailedCount(JobInstance job) {
    return job.buildings
        .expand((b) => b.units)
        .where(
          (u) =>
              u.status == UnitVerificationStatus.failed && u.permanentFailure,
        )
        .length;
  }

  int _remainingCount(JobInstance job) {
    return job.buildings
        .expand((b) => b.units)
        .where(
          (u) =>
              u.status == UnitVerificationStatus.pending ||
              (u.status == UnitVerificationStatus.failed && !u.permanentFailure),
        )
        .length;
  }

  // Helper to calculate overall progress
  double _calculateOverallProgress(JobInstance job) {
    final totalUnits = job.buildings.expand((b) => b.units).length;
    if (totalUnits == 0) return 0.0;
    final remaining = _remainingCount(job);
    final completedUnits = totalUnits - remaining;
    return completedUnits / totalUnits;
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
      default:
        return l10n.jobInProgressFailureReasonUnknown;
    }
  }

  // Using rounded icons for a modern look
  IconData _failureReasonIcon(String code) {
    switch (code) {
      case 'TRASH_CAN_NOT_VISIBLE':
        return Icons.delete_outline_rounded;
      case 'TRASH_BAG_VISIBLE':
        return Icons.delete_rounded;
      case 'DOOR_NUMBER_MISMATCH':
        return Icons.numbers_rounded;
      case 'DOOR_NUMBER_MISSING':
        return Icons.help_outline_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  // --- UI WIDGETS (REVAMPED) ---

  // REVAMPED: Building Tile with Progress Bar and Card Styling
  Widget _buildBuildingTile(Building b, AppLocalizations l10n) {
    // Calculate progress
    final totalUnits = b.units.length;
    final completedUnits = b.units.where((u) =>
        u.status == UnitVerificationStatus.verified ||
        u.status == UnitVerificationStatus.dumped ||
        (u.status == UnitVerificationStatus.failed && u.permanentFailure)).length;
    final progress = totalUnits > 0 ? completedUnits / totalUnits : 0.0;
    final isExpanded = _expansionState[b.buildingId] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Use a custom theme to remove the default divider lines of ExpansionTile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>(b.buildingId),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _expansionState[b.buildingId] = expanded;
            });
          },
          title: Text(
            b.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          // Progress visualization in subtitle
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.poofColor),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '$completedUnits/$totalUnits',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 16),
          children: b.units.map((u) => _buildUnitTile(u, l10n)).toList(),
        ),
      ),
    );
  }

  // Helper for status visualization
  (IconData, Color, String) _getUnitStatus(UnitVerification u, AppLocalizations l10n) {
    IconData icon;
    Color color;
    String label;
    switch (u.status) {
      case UnitVerificationStatus.verified:
        icon = Icons.check_circle_rounded;
        color = Colors.green.shade600;
        label = l10n.jobInProgressUnitStatusVerified;
        break;
      case UnitVerificationStatus.dumped:
        icon = Icons.delete_rounded;
        color = Colors.orange.shade600;
        label = l10n.jobInProgressUnitStatusDumped;
        break;
      case UnitVerificationStatus.failed:
        icon = u.permanentFailure ? Icons.block_rounded : Icons.error_rounded;
        color = Colors.red.shade600;
        label = u.permanentFailure
            ? l10n.jobInProgressUnitStatusFailedPermanent
            : l10n.jobInProgressUnitStatusFailed;
        break;
      default:
        icon = Icons.pending_actions_rounded;
        color = Colors.grey.shade600;
        label = l10n.jobInProgressUnitStatusPending;
    }
    return (icon, color, label);
  }

  // REVAMPED: Unit Tile Design
  Widget _buildUnitTile(UnitVerification u, AppLocalizations l10n) {
    final (icon, color, label) = _getUnitStatus(u, l10n);

    final waiting = _verifyingUnitId == u.unitId;
    final canTakePhoto =
        u.status == UnitVerificationStatus.pending ||
        (u.status == UnitVerificationStatus.failed && !u.permanentFailure);

    Widget trailingWidget;

    if (canTakePhoto) {
      // Actionable state
      final cameraBtn = waiting
          ? const SizedBox(
              width: 48, // Standard IconButton size
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.poofColor),
                ),
              ),
            )
          : IconButton(
              // Primary action emphasized
              icon: const Icon(Icons.camera_alt_rounded, color: AppColors.poofColor, size: 26),
              // tooltip: l10n.jobInProgressTakePhotoTooltip, // Ensure this localization key exists if uncommenting
              onPressed: () => _takePhoto(u),
            );

      final menuBtn = PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

      trailingWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [cameraBtn, menuBtn],
      );
    } else {
      // Non-actionable state
      if (u.status == UnitVerificationStatus.failed && u.permanentFailure) {
        // Permanent failure: Show info button
        trailingWidget = IconButton(
            icon: Icon(Icons.info_outline_rounded, color: color),
            tooltip: l10n.jobInProgressFailureReasonTitle,
            onPressed: () => _showFailureReason(u),
        );
      } else {
        // Completed state: Just the icon
         trailingWidget = Icon(icon, color: color.withOpacity(0.7));
      }
    }

    // Stylish Status Chip
    Widget statusChip(Color c, String t) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // Soft background with a subtle border
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: Text(
          t,
          style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      );
    }

    // The ListTile itself, nested within the building card
    return Padding(
      // Slight internal padding for separation
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
         decoration: BoxDecoration(
          // Use a very subtle background to distinguish from the parent card
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          // Leading icon helps visualize the status quickly
          leading: Icon(icon, color: color, size: 26),
          title: Text(
            'Unit ${u.unitNumber}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: statusChip(color, label),
          ),
          trailing: trailingWidget,
        ),
      ),
    );
  }

  // NEW: Dashboard Stat Card Widget
  Widget _buildStatCard({required IconData icon, required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Map Preview Widget
  Widget _buildMapPreview(AppLocalizations l10n) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _openFullMap,
        child: Stack(
          children: [
            SizedBox(
              height: 150,
              // Use AbsorbPointer for the preview map to ensure the GestureDetector works reliably
              child: AbsorbPointer(
                child: widget.preWarmedMap,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text('Map', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Stylized Instruction/Tip Box
  Widget _buildInstructions(AppLocalizations l10n) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // Subtle coloring using the primary color
              color: AppColors.poofColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.poofColor.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColors.poofColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.jobInProgressPhotoInstructions,
                    style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ),
        ),
    );
  }

  // NEW: Elevated Footer for Slider
  Widget _buildSliderAction(bool slideEnabled, String slideText, IconData slideIcon) {
    return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, -5), // Shadow at the top
            ),
          ],
        ),
        // Ensure padding respects the safe area (e.g., iPhone home bar)
        padding: EdgeInsets.fromLTRB(
            20.0, 16.0, 20.0, 16.0 + MediaQuery.of(context).padding.bottom),
        child: SizedBox(
          width: double.infinity,
          child: SlideAction(
            text: slideText,
            outerColor:
                slideEnabled ? AppColors.poofColor : Colors.grey.shade400,
            innerColor: Colors.white,
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            sliderButtonIcon: Icon(
              slideIcon,
              color: slideEnabled ? AppColors.poofColor : Colors.grey,
              size: 28,
            ),
            sliderRotate: false,
            enabled: slideEnabled,
            onSubmit: slideEnabled ? _dumpBags : null,
            // Slightly larger height for better ergonomics
            height: 65,
          ),
        ),
      );
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(jobsNotifierProvider);
    // Ensure the UI reflects the latest state if updated in the provider
    final job = state.inProgressJob ?? widget.job;

    final bagsCollected = bagCount(job);
    final permFailed = _permanentFailedCount(job);
    final remaining = _remainingCount(job);
    final hasVerified = bagsCollected > 0;
    final slideEnabled =
        hasVerified || (bagsCollected == 0 && permFailed > 0 && remaining == 0);
    final slideText = hasVerified
        ? l10n.jobInProgressDumpBagsAction
        : l10n.jobInProgressCompleteJobAction;
    final slideIcon = hasVerified ? Icons.delete_rounded : Icons.check_circle_rounded;

    final overallProgress = _calculateOverallProgress(job);

    // Determine color for bags collected based on proximity to limit
    Color bagColor = Colors.green.shade600;
    if (bagsCollected >= _bagLimit * 0.9) {
      bagColor = Colors.red.shade600;
    } else if (bagsCollected >= _bagLimit * 0.6) {
      bagColor = Colors.orange.shade600;
    }

    // Sort buildings consistently
    final sortedBuildings = List<Building>.from(job.buildings)
      ..sort((a, b) => a.name.compareTo(b.name));

    return PopScope(
      canPop: false,
      child: Scaffold(
        // Use a slightly off-white background for a modern look
        backgroundColor: Colors.grey.shade100,

        // --- Modern AppBar ---
        appBar: AppBar(
          automaticallyImplyLeading: false, // Hide back button
          title: Text(job.property.propertyName, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white, // Ensures AppBar color remains white when scrolling
          elevation: 0,
          actions: [
            IconButton(
              onPressed: _contactSupport,
              icon: const Icon(Icons.support_agent_rounded),
              tooltip: l10n.jobInProgressContactSupport,
            ),
            IconButton(
              onPressed: _handleCancel,
              // Make cancel button distinct
              icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent),
              tooltip: l10n.jobInProgressCancelButton,
            ),
            const SizedBox(width: 8),
          ],
          // Add an overall progress bar to the AppBar
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4.0),
            child: LinearProgressIndicator(
              value: overallProgress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.poofColor),
            ),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Dashboard Section (Map and Stats) ---
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Map Preview
                  _buildMapPreview(l10n),
                  const SizedBox(height: 16),
                  // Stats Cards
                  Row(
                    children: [
                      _buildStatCard(
                        icon: Icons.timer_rounded,
                        // Note: Assuming localization keys exist for these labels
                        label: l10n.jobInProgressTimeElapsed ?? "Time Elapsed",
                        value: _formatDuration(_elapsedTime),
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(width: 16),
                      _buildStatCard(
                        icon: Icons.shopping_bag_rounded,
                        // Note: Assuming localization keys exist for these labels
                        label: l10n.jobInProgressBagsCollectedLabel ?? "Bags Collected",
                        value: '$bagsCollected/$_bagLimit',
                        color: bagColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- Instructions/Tip ---
             _buildInstructions(l10n),

             // Section Header
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
               child: Text(
                 "Buildings & Units", // Placeholder, should use l10n key if available
                 style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
               ),
             ),


            // --- Building/Unit List ---
            Expanded(
              child: ListView.builder(
                // Use physics for a natural scrolling feel
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                itemCount: sortedBuildings.length,
                itemBuilder: (context, index) {
                  return _buildBuildingTile(sortedBuildings[index], l10n);
                },
              ),
            ),
          ],
        ),
        // --- Footer Action (Slider) ---
        bottomNavigationBar: _buildSliderAction(slideEnabled, slideText, slideIcon),
      ),
    );
  }
}

/// Counts the number of units that have been successfully verified.
int bagCount(JobInstance job) {
  return job.buildings
      .expand((b) => b.units)
      .where((u) => u.status == UnitVerificationStatus.verified)
      .length;
}
