// worker-app/lib/features/jobs/presentation/pages/job_in_progress_page.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_map_page.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/slide_button_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

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

  static const int _bagLimit = 8;

  void _openFullMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JobMapPage(
          job: widget.job,
          buildAsScaffold: true,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.job.checkInAt != null) {
      _elapsedTime =
          DateTime.now().toUtc().difference(widget.job.checkInAt!.toUtc());
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

  Future<void> _takePhoto(UnitVerification unit) async {
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
        await ref
            .read(jobsNotifierProvider.notifier)
            .verifyUnitPhoto(unit.unitId, photo);
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
      if (job == null) Navigator.of(context).pop();
    }
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

    if (confirmed != true) return;

    final wasSuccess =
        await ref.read(jobsNotifierProvider.notifier).cancelJob(widget.job.instanceId);
    if (mounted && wasSuccess) Navigator.of(context).pop();
  }

  void _showFailureReason(UnitVerification unit) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.jobInProgressFailureReasonTitle),
        content: Text(unit.failureReason?.isNotEmpty == true
            ? unit.failureReason!
            : l10n.jobInProgressFailureReasonUnknown),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.okButtonLabel),
          ),
        ],
      ),
    );
  }

  int _verifiedCount(JobInstance job) {
    return job.buildings
        .expand((b) => b.units)
        .where((u) => u.status == UnitVerificationStatus.verified)
        .length;
  }


  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildBuildingTile(Building b, AppLocalizations l10n) {
    return ExpansionTile(
      title: Text(b.name),
      children: b.units.map((u) => _buildUnitTile(u, l10n)).toList(),
    );
  }

  Widget _buildUnitTile(UnitVerification u, AppLocalizations l10n) {
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
        icon = Icons.error;
        color = Colors.red;
        label = l10n.jobInProgressUnitStatusFailed;
        break;
      default:
        icon = Icons.hourglass_bottom;
        color = Colors.grey;
        label = l10n.jobInProgressUnitStatusPending;
    }

    final waiting = _verifyingUnitId == u.unitId;
    final canTakePhoto =
        u.status == UnitVerificationStatus.pending ||
        u.status == UnitVerificationStatus.failed;
    Widget trailing;
    if (canTakePhoto) {
      final cameraBtn = waiting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () => _takePhoto(u),
            );
      if (u.status == UnitVerificationStatus.failed) {
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showFailureReason(u),
            ),
            cameraBtn,
          ],
        );
      } else {
        trailing = cameraBtn;
      }
    } else {
      trailing = Icon(icon, color: color);
    }

    return ListTile(
      title: Text('Unit ${u.unitNumber}'),
      subtitle: Text(label),
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(jobsNotifierProvider);
    final job = state.inProgressJob ?? widget.job;

    final verified = _verifiedCount(job);
    final slideEnabled = verified > 0;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: Column(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      job.property.propertyName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      onPressed: _handleCancel,
                      icon: const Icon(Icons.cancel),
                      tooltip: l10n.jobInProgressCancelButton,
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _openFullMap,
                child: Stack(
                  children: [
                    SizedBox(height: 180, child: widget.preWarmedMap),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
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
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.jobInProgressBagsCollected(verified, _bagLimit)),
                Text(_formatDuration(_elapsedTime)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  l10n.jobInProgressPhotoInstructions,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: job.buildings
                  .map((b) => _buildBuildingTile(b, l10n))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0),
            child: SizedBox(
              width: double.infinity,
              child: SlideAction(
                text: l10n.jobInProgressDumpBagsAction,
                outerColor:
                    slideEnabled ? AppColors.poofColor : Colors.grey.shade400,
                innerColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                sliderButtonIcon: Icon(
                  Icons.delete,
                  color: slideEnabled ? AppColors.poofColor : Colors.grey,
                ),
                sliderRotate: false,
                enabled: slideEnabled,
                onSubmit: slideEnabled ? _dumpBags : null,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}
