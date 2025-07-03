// worker-app/lib/features/auth/presentation/pages/address_info_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/routing/router.dart';

import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

class AddressInfoPage extends ConsumerStatefulWidget {
  const AddressInfoPage({super.key});

  @override
  ConsumerState<AddressInfoPage> createState() => _AddressInfoPageState();
}

class _AddressInfoPageState extends ConsumerState<AddressInfoPage> {
  late final TextEditingController _aptSuiteController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _zipController;

  late final FlutterGooglePlacesSdk _places;
  bool _placesReady = false;

  bool _isLoading       = false;
  bool _addressResolved = false;
  String _streetValue   = '';

  @override
  void initState() {
    super.initState();
    _aptSuiteController  = TextEditingController();
    _cityController      = TextEditingController();
    _stateController     = TextEditingController();
    _zipController       = TextEditingController();
    _initPlaces();
  }

  Future<void> _initPlaces() async {
    final apiKey = PoofWorkerFlavorConfig.instance.gcpSdkKey;
    _places = FlutterGooglePlacesSdk(apiKey, locale: const Locale('en'));
    await _places.isInitialized();
    if (mounted) setState(() => _placesReady = true);
  }

  @override
  void dispose() {
    _aptSuiteController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      !_isLoading &&
      _addressResolved &&
      _cityController.text.isNotEmpty &&
      _stateController.text.isNotEmpty &&
      _zipController.text.isNotEmpty;

  Future<void> _onContinue() async {
    if (!_canContinue) return;
    setState(() => _isLoading = true);

    ref.read(signUpProvider.notifier).setAddressInfo(
      streetAddress: _streetValue.trim(),
      aptSuite     : _aptSuiteController.text.trim(),
      city         : _cityController.text.trim(),
      stateName    : _stateController.text.trim(),
      zipCode      : _zipController.text.trim(),
    );

    await context.pushNamed(AppRouteNames.vehicleSetupPage);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app   = AppLocalizations.of(context);
    final theme = Theme.of(context);

    InputDecoration highlightDecor(String label) => InputDecoration(
          labelText : label,
          filled    : true,
          fillColor : theme.colorScheme.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: AppColors.poofColor, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: AppColors.poofColor, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : BorderSide.none,
          ),
        );

    InputDecoration normalDecor(String label) => InputDecoration(
          labelText : label,
          filled    : true,
          fillColor : theme.colorScheme.surfaceContainer,
          border    : OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: AppColors.poofColor, width: 2),
          ),
        );

    InputDecoration disabledDecor(String label) => normalDecor(label);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: AppConstants.kDefaultPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Center(
                          child: Icon(Icons.location_on_outlined,
                              size: 64, color: AppColors.poofColor),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 400.ms)
                            .scale(
                                begin: const Offset(0.8, 0.8),
                                end:   const Offset(1, 1),
                                curve: Curves.easeOutBack),
                        const SizedBox(height: 24),
                        Text(
                          app.addressInfoPageTitle,
                          style: theme.textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        )
                            .animate()
                            .fadeIn(delay: 300.ms)
                            .slideX(begin: -0.1, duration: 400.ms, curve: Curves.easeOutCubic),
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            app.addressInfoPageSubtitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 400.ms)
                            .slideX(begin: -0.1, duration: 400.ms, curve: Curves.easeOutCubic),
                        const SizedBox(height: 32),

                        // ───── Street (Material TypeAhead) ─────
                        if (_placesReady)
                          AddressAutocompleteField(
                            places       : _places,
                            decoration   : highlightDecor(app.addressInfoPageStreetLabel),
                            onTextChanged: (val) => setState(() {
                              _streetValue     = val;
                              _addressResolved = false;
                            }),
                            onResolved: (resolved) => setState(() {
                              _streetValue               = resolved.street;
                              _cityController.text       = resolved.city;
                              _stateController.text      = resolved.state;
                              _zipController.text        = resolved.postalCode;
                              _addressResolved           = true;
                            }),
                          )
                        else
                          TextField(
                            enabled   : false,
                            decoration: highlightDecor(app.addressInfoPageStreetLabel)
                                .copyWith(
                                    suffixIcon: const Icon(Icons.place_outlined)),
                          ),
                        const SizedBox(height: 16),

                        // ───── Apt / Suite ─────
                        TextField(
                          controller: _aptSuiteController,
                          decoration: normalDecor(app.addressInfoPageAptSuiteLabel),
                        ),
                        const SizedBox(height: 16),

                        // ───── City / State / ZIP (read-only) ─────
                        TextField(
                          controller: _cityController,
                          enabled   : false,
                          decoration: disabledDecor(app.addressInfoPageCityLabel),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _stateController,
                                enabled   : false,
                                decoration: disabledDecor(app.addressInfoPageStateLabel),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _zipController,
                                enabled   : false,
                                decoration: disabledDecor(app.addressInfoPageZipLabel),
                              ),
                            ),
                          ],
                        ),
                      ]
                          .animate(interval: 80.ms)
                          .fadeIn(duration: 500.ms, delay: 500.ms)
                          .slideY(begin: 0.1),
                    ),
                  ),
                ),

                // ───── Continue button ─────
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: WelcomeButton(
                    text      : app.addressInfoPageContinueButton,
                    isLoading : _isLoading,
                    onPressed : _canContinue ? _onContinue : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AddressAutocompleteField (Material TypeAhead)
// ─────────────────────────────────────────────────────────────────────────────
class AddressAutocompleteField extends StatefulWidget {
  final FlutterGooglePlacesSdk places;
  final InputDecoration decoration;
  final void Function(String text) onTextChanged;
  final void Function(ResolvedAddress address) onResolved;

  const AddressAutocompleteField({
    super.key,
    required this.places,
    required this.decoration,
    required this.onTextChanged,
    required this.onResolved,
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _controller = TextEditingController();
  final SuggestionsController<AutocompletePrediction> _suggestionsController =
      SuggestionsController<AutocompletePrediction>();

  Future<List<AutocompletePrediction>> _suggestions(String pattern) async {
    if (pattern.length < 3) return const [];
    final rsp = await widget.places.findAutocompletePredictions(
      pattern,
      placeTypesFilter: [PlaceTypeFilter.ADDRESS],
      newSessionToken: true,
    );
    return rsp.predictions;
  }

  Future<void> _handleSelect(AutocompletePrediction p) async {
    final resp = await widget.places.fetchPlace(
      p.placeId,
      fields: [
        PlaceField.Address,
        PlaceField.AddressComponents,
        PlaceField.Location,
      ],
    );
    final place = resp.place;
    if (place == null) return;

    final resolved = _toResolved(place);
    widget.onResolved(resolved);

    _controller
      ..text      = resolved.street
      ..selection = TextSelection.collapsed(offset: resolved.street.length);

    // Close suggestions to prevent flicker
    _suggestionsController.close();

    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _suggestionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TypeAheadField<AutocompletePrediction>(
      controller          : _controller,
      suggestionsController: _suggestionsController,
      debounceDuration    : const Duration(milliseconds: 300),
      hideOnSelect        : true,
      hideOnEmpty         : true,
      suggestionsCallback : _suggestions,
      builder: (context, ctrl, focusNode) => TextField(
        controller : ctrl,
        focusNode  : focusNode,
        onChanged  : (val) {
          widget.onTextChanged(val);
          if (val.length >= 3) {
            _suggestionsController.open(); // reopen when user edits again
          }
        },
        decoration : widget.decoration,
      ),
      itemBuilder: (context, p) => ListTile(
        title   : Text(p.primaryText),
        subtitle: Text(p.secondaryText),
      ),
      onSelected  : _handleSelect,
      emptyBuilder: (context) => const SizedBox.shrink(),
    );
  }

  ResolvedAddress _toResolved(Place p) {
    String comp(String type, {bool short = false}) {
      final component = p.addressComponents?.firstWhere(
        (c) => c.types.contains(type),
        orElse: () => _emptyComp,
      );
      return short ? (component!.shortName) : component!.name;
    }

    final streetNum = comp('street_number');
    final route     = comp('route');
    return ResolvedAddress(
      street     : '$streetNum $route'.trim(),
      city       : comp('locality'),
      state      : comp('administrative_area_level_1', short: true),
      postalCode : comp('postal_code'),
      latLng     : p.latLng,
    );
  }

  static const AddressComponent _emptyComp =
      AddressComponent(name: '', shortName: '', types: []);
}

class ResolvedAddress {
  final String street;
  final String city;
  final String state;
  final String postalCode;
  final LatLng? latLng;

  const ResolvedAddress({
    required this.street,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.latLng,
  });
}

