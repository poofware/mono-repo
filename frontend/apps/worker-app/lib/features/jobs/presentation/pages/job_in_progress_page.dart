// worker-app/lib/features/jobs/presentation/pages/job_in_progress_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/slide_button_widget.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_map_page.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/features/jobs/utils/job_photo_persistence.dart';

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
  // --- Page State ---
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;
  final List<XFile> _photos = [];
  bool _isCompleting = false;
  bool _isCancelling = false;
  bool _isRestoring = true; // Used to show a loader while restoring photos
  bool _isTakingPhoto = false; // Protect the camera button

  // --- Map State ---
  GoogleMapController? _gmapController;
  StreamSubscription<Position>? _positionStream;
  Widget? _mapWidget;
  bool _isFollowingUser = true;

  // --- Draggable Sheet State ---
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // --- Constants for Dynamic Sheet Height Calculation ---
  static const double _kHeaderHeight = 200.0;
  static const double _kPhotoTitleHeight = 32.0;
  static const double _kPhotoGalleryHeight = 120.0;
  static const double _kFooterHeight = 92.0;

  @override
  void initState() {
    super.initState();
    _loadPersistedStateAndInitialize();

    // Now run the original initState logic
    _startTimerAndCalculateInitialElapsed();
    _prepareMapWidget();
  }

  /// Loads persisted photos from storage and then calls original init logic.
  Future<void> _loadPersistedStateAndInitialize() async {
    final persistedPhotos =
        await JobPhotoPersistence.loadPhotos(widget.job.instanceId);

    if (mounted) {
      setState(() {
        _photos.addAll(persistedPhotos);
        _isRestoring = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _gmapController?.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _startTimerAndCalculateInitialElapsed() {
    if (widget.job.checkInAt != null) {
      _elapsedTime =
          DateTime.now().toUtc().difference(widget.job.checkInAt!.toUtc());
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedTime += const Duration(seconds: 1));
    });
  }

  void _prepareMapWidget() {
    _mapWidget = JobMapPage(
      key: widget.preWarmedMap.key,
      job: widget.job,
      buildAsScaffold: false,
      isForWarmup: false,
      onMapCreated: (controller) {
        if (!mounted) return;
        _gmapController = controller;
        _setupLocationStream();
      },
      onCameraMoveStarted: () {
        if (mounted && _isFollowingUser) {
          setState(() => _isFollowingUser = false);
        }
      },
    );
  }

  Future<void> _setupLocationStream() async {
    final permissionOk = await ensureLocationGranted();
    if (!permissionOk || !mounted || _gmapController == null) return;
    if (!_isFollowingUser) return;

    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((Position position) {
      if (mounted && _isFollowingUser) {
        _gmapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
      }
    });
  }

  Future<void> _reCenterAndFollow() async {
    if (!mounted || _gmapController == null) return;
    setState(() => _isFollowingUser = true);

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 7),
        ),
      );
      if (mounted) {
        _gmapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            await _gmapController!.getZoomLevel(),
          ),
        );
      }
    } catch (_) {
      // Ignore
    }
    _setupLocationStream();
  }

  Future<void> _takePhoto() async {
    if (_isTakingPhoto) return;
    setState(() => _isTakingPhoto = true);

    final picker = ImagePicker();
    try {
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo == null || !mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final appLocalizations = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(appLocalizations.jobInProgressPhotoConfirmDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.file(File(photo.path), fit: BoxFit.contain),
                const SizedBox(height: 16),
                Text(appLocalizations.jobInProgressPhotoConfirmDialogContent),
              ],
            ),
            actions: [
              TextButton(
                child:
                    Text(appLocalizations.jobInProgressPhotoConfirmDialogRetake),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              FilledButton(
                child:
                    Text(appLocalizations.jobInProgressPhotoConfirmDialogConfirm),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        final persistentPhoto =
            await JobPhotoPersistence.savePhoto(widget.job.instanceId, photo);
        if (mounted) {
          setState(() => _photos.add(persistentPhoto));
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isTakingPhoto = false);
      }
    }
  }

  void _navigateBack() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route is PopupRoute) {
      Navigator.of(context).pop();
    } else {
      context.goNamed('MainTab');
    }
  }

  Future<void> _handleComplete() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);

    final photoFiles = _photos.map((xfile) => File(xfile.path)).toList();
    final wasSuccess = await ref
        .read(jobsNotifierProvider.notifier)
        .completeJob(widget.job.instanceId, photoFiles);
        
    if (mounted) {
      if (wasSuccess) {
        await JobPhotoPersistence.clearPhotos(widget.job.instanceId);
        _navigateBack();
      } else {
        // Just reset the UI state. Error is handled globally.
        setState(() => _isCompleting = false);
      }
    }
  }

  Future<void> _handleCancel() async {
    if (_isCancelling) return;
    final appLocalizations = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.jobInProgressCancelDialogTitle),
        content: Text(appLocalizations.jobInProgressCancelDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appLocalizations.jobInProgressCancelDialogBack),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appLocalizations.jobInProgressCancelDialogConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);

    final wasSuccess = await ref
        .read(jobsNotifierProvider.notifier)
        .cancelJob(widget.job.instanceId);

    if (mounted) {
       if (wasSuccess) {
        await JobPhotoPersistence.clearPhotos(widget.job.instanceId);
        _navigateBack();
      } else {
        // Just reset the UI state. Error is handled globally.
        setState(() => _isCancelling = false);
      }
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomSafeArea = mediaQuery.padding.bottom;

    const minSheetSize = 0.31;
    final double contentHeight = _kHeaderHeight +
        _kPhotoTitleHeight +
        _kPhotoGalleryHeight +
        _kFooterHeight +
        10 +
        bottomSafeArea;
    final maxSheetSize =
        (contentHeight / screenHeight).clamp(minSheetSize, 1.0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: Stack(
          children: [
            if (_mapWidget != null)
              _mapWidget!
            else
              const Center(child: CircularProgressIndicator()),
            if (_isRestoring) const Center(child: CircularProgressIndicator()),
            Positioned(
              top: mediaQuery.padding.top + 12,
              right: 12,
              child: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'cancel') _handleCancel();
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                color: Colors.white,
                elevation: 4,
                tooltip: appLocalizations.jobInProgressMoreOptionsTooltip,
                icon: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withAlpha(230),
                  child: const Icon(Icons.more_vert, color: Colors.black87),
                ),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'cancel',
                    child: ListTile(
                      leading: Icon(Icons.cancel, color: Colors.red.shade700),
                      title: Text(appLocalizations.jobInProgressCancelButton,
                          style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isFollowingUser)
              Positioned(
                bottom: screenHeight * minSheetSize + 16,
                right: 16,
                child: FloatingActionButton(
                  onPressed: _reCenterAndFollow,
                  backgroundColor: Colors.white.withAlpha(230),
                  child:
                      const Icon(Icons.my_location, color: AppColors.poofColor),
                ),
              ),
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: minSheetSize,
              minChildSize: minSheetSize,
              maxChildSize: maxSheetSize,
              snap: true,
              snapSizes: [minSheetSize, maxSheetSize],
              builder: (context, scrollController) {
                return _buildSheetContent(
                    context, scrollController, appLocalizations);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildSheetContent(
    BuildContext context,
    ScrollController scrollController,
    AppLocalizations appLocalizations,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final bottomSafeArea = mediaQuery.padding.bottom;

    // total blank height for the invisible list content
    final blankScrollHeight =
        _kHeaderHeight + _kPhotoTitleHeight + _kPhotoGalleryHeight;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(217),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Stack(
            children: [
              // invisible scroll surface to drive the sheet’s drag behavior
              ListView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                children: [
                  SizedBox(height: blankScrollHeight),
                  SizedBox(height: _kFooterHeight + bottomSafeArea),
                ],
              ),

              // HEADER
              _buildHeader(context, appLocalizations),

              // “Photos Taken” title
              Positioned(
                top: _kHeaderHeight,
                left: 0,
                right: 0,
                child: _buildPhotoSectionHeader(context, appLocalizations),
              ),

              // PHOTO GALLERY (now fixed in place)
              Positioned(
                top: _kHeaderHeight + _kPhotoTitleHeight,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: _kPhotoGalleryHeight,
                  child: _buildPhotoGallery(appLocalizations),
                ),
              ),

              // DIVIDER above the footer
              Positioned(
                bottom: _kFooterHeight + bottomSafeArea,
                left: 0,
                right: 0,
                child: const Divider(height: 1, thickness: 1),
              ),

              // FOOTER (camera button + slide button)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildFooter(context, appLocalizations),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations appLocalizations) {
    final textTheme = Theme.of(context).textTheme;
    return IgnorePointer(
      child: Container(
        height: _kHeaderHeight,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.job.property.propertyName,
              style: textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              widget.job.property.address,
              style: textTheme.bodyLarge?.copyWith(color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _formatDuration(_elapsedTime),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.poofColor,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '/ ${appLocalizations.jobInProgressEstTimeLabel(widget.job.displayTime)}',
                    style: textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSectionHeader(
      BuildContext context, AppLocalizations appLocalizations) {
    return IgnorePointer(
      child: Container(
        height: _kPhotoTitleHeight,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        alignment: Alignment.centerLeft,
        child: Text(
          appLocalizations.jobInProgressPhotosTakenHeader,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppLocalizations appLocalizations) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return Container(
      height: _kFooterHeight + bottomSafeArea,
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, bottomSafeArea > 0 ? bottomSafeArea : 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(242),
      ),
      child: Row(
        children: [
          FloatingActionButton(
            heroTag: 'take_photo',
            onPressed: _isTakingPhoto ? null : _takePhoto, // Disable when busy
            tooltip: appLocalizations.jobInProgressTakePictureButton,
            elevation: 2,
            backgroundColor: _isTakingPhoto ? Colors.grey.shade400 : Colors.grey.shade200,
            child: _isTakingPhoto
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
                : const Icon(Icons.camera_alt, size: 28, color: Colors.black87),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SlideAction(
                  height: 60,
                  text: appLocalizations.jobInProgressCompleteAction,
                  textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  outerColor: AppColors.poofColor,
                  innerColor: Colors.white,
                  sliderButtonIcon:
                      const Icon(Icons.check, color: AppColors.poofColor),
                  showSubmittedAnimation: true,
                  sliderRotate: false,
                  enabled: !_isCompleting,
                  onSubmit: _handleComplete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGallery(AppLocalizations appLocalizations) {
    // If there are no photos, display a placeholder message.
    if (_photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Center(
          child: Text(
            appLocalizations.jobInProgressNoPhotos,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ),
      );
    }
    // Otherwise, build the horizontal list.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: _photos.map((photo) {
          return Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.all(10),
                    child: InteractiveViewer(
                      child: Image.file(File(photo.path), fit: BoxFit.contain),
                    ),
                  ),
                );
              },
              child: Hero(
                tag: 'photo_${_photos.indexOf(photo)}',
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(photo.path), fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
