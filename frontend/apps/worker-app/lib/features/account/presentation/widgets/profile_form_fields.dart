// frontend/apps/worker-app/lib/features/account/presentation/widgets/profile_form_fields.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Address Form Field
// ─────────────────────────────────────────────────────────────────────────────

/// A data class to hold the resolved components of an address.
class AddressResolved {
  final String street;
  final String city;
  final String state;
  final String postalCode;
  final LatLng? latLng;

  const AddressResolved({
    required this.street,
    required this.city,
    required this.state,
    required this.postalCode,
    this.latLng,
  });

  static const AddressComponent _emptyComp = AddressComponent(
    name: '',
    shortName: '',
    types: [],
  );

  factory AddressResolved.fromPlace(Place p) {
    String comp(String type, {bool short = false}) {
      final component = p.addressComponents?.firstWhere(
        (c) => c.types.contains(type),
        orElse: () => _emptyComp,
      );
      return short ? (component!.shortName) : component!.name;
    }

    final streetNum = comp('street_number');
    final route = comp('route');
    return AddressResolved(
      street: '$streetNum $route'.trim(),
      city: comp('locality'),
      state: comp('administrative_area_level_1', short: true),
      postalCode: comp('postal_code'),
      latLng: p.latLng,
    );
  }
}

/// A reusable form field for address input with Google Places autocomplete.
class AddressFormField extends ConsumerStatefulWidget {
  final String initialStreet;
  final String initialAptSuite;
  final String initialCity;
  final String initialState;
  final String initialZip;
  final bool isEditing;
  final void Function(AddressResolved? resolvedAddress, String aptSuite)
  onChanged;

  const AddressFormField({
    super.key,
    required this.initialStreet,
    required this.initialAptSuite,
    required this.initialCity,
    required this.initialState,
    required this.initialZip,
    required this.isEditing,
    required this.onChanged,
  });

  @override
  ConsumerState<AddressFormField> createState() => _AddressFormFieldState();
}

class _AddressFormFieldState extends ConsumerState<AddressFormField> {
  late final TextEditingController _streetController;
  late final TextEditingController _aptSuiteController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _zipController;

  late final FlutterGooglePlacesSdk _places;
  bool _placesReady = false;
  AddressResolved? _resolvedAddress;

  @override
  void initState() {
    super.initState();
    _streetController = TextEditingController(text: widget.initialStreet);
    _aptSuiteController = TextEditingController(text: widget.initialAptSuite);
    _cityController = TextEditingController(text: widget.initialCity);
    _stateController = TextEditingController(text: widget.initialState);
    _zipController = TextEditingController(text: widget.initialZip);

    _resolvedAddress = widget.initialStreet.isNotEmpty
        ? AddressResolved(
            street: widget.initialStreet,
            city: widget.initialCity,
            state: widget.initialState,
            postalCode: widget.initialZip,
          )
        : null;

    _initPlaces();

    _aptSuiteController.addListener(() {
      widget.onChanged(_resolvedAddress, _aptSuiteController.text);
    });
  }

  @override
  void didUpdateWidget(covariant AddressFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing != oldWidget.isEditing && !widget.isEditing) {
      _streetController.text = widget.initialStreet;
      _aptSuiteController.text = widget.initialAptSuite;
      _cityController.text = widget.initialCity;
      _stateController.text = widget.initialState;
      _zipController.text = widget.initialZip;
      _resolvedAddress = widget.initialStreet.isNotEmpty
          ? AddressResolved(
              street: widget.initialStreet,
              city: widget.initialCity,
              state: widget.initialState,
              postalCode: widget.initialZip,
            )
          : null;
    }
  }

  Future<void> _initPlaces() async {
    final apiKey = PoofWorkerFlavorConfig.instance.gcpSdkKey;
    _places = FlutterGooglePlacesSdk(apiKey, locale: const Locale('en'));
    await _places.isInitialized();
    if (mounted) setState(() => _placesReady = true);
  }

  @override
  void dispose() {
    _streetController.dispose();
    _aptSuiteController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, {bool isHighlighted = false}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: isHighlighted
          ? theme.colorScheme.surface
          : theme.colorScheme.surfaceContainer,
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

  @override
  Widget build(BuildContext context) {
    final app = AppLocalizations.of(context);

    if (!widget.isEditing) {
      final readOnlyDisplay = widget.initialAptSuite.isNotEmpty
          ? '${widget.initialStreet}, ${widget.initialAptSuite}'
          : widget.initialStreet;
      return ProfileReadOnlyField(
        icon: Icons.location_on_outlined,
        label: app.myProfilePageAddressLabel,
        value: readOnlyDisplay,
      );
    }

    return Column(
      children: [
        if (_placesReady)
          TypeAheadField<AutocompletePrediction>(
            controller: _streetController,
            suggestionsCallback: (pattern) async {
              if (pattern.length < 3) return const [];
              final rsp = await _places.findAutocompletePredictions(
                pattern,
                placeTypesFilter: [PlaceTypeFilter.ADDRESS],
                newSessionToken: true,
              );
              return rsp.predictions;
            },
            builder: (context, controller, focusNode) => TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: (val) {
                setState(() => _resolvedAddress = null);
                widget.onChanged(null, _aptSuiteController.text);
              },
              decoration: _inputDecoration(
                app.addressInfoPageStreetLabel,
                isHighlighted: true,
              ),
            ),
            itemBuilder: (context, p) => ListTile(
              title: Text(p.primaryText),
              subtitle: Text(p.secondaryText),
            ),
            onSelected: (p) async {
              final resp = await _places.fetchPlace(
                p.placeId,
                fields: [
                  PlaceField.Address,
                  PlaceField.AddressComponents,
                  PlaceField.Location,
                ],
              );
              final place = resp.place;
              if (place == null) return;

              final resolved = AddressResolved.fromPlace(place);
              setState(() {
                _resolvedAddress = resolved;
                _streetController.text = resolved.street;
                _cityController.text = resolved.city;
                _stateController.text = resolved.state;
                _zipController.text = resolved.postalCode;
              });
              widget.onChanged(resolved, _aptSuiteController.text);
              if (context.mounted) FocusScope.of(context).unfocus();
            },
          )
        else
          TextField(
            enabled: false,
            decoration: _inputDecoration(
              app.addressInfoPageStreetLabel,
              isHighlighted: true,
            ).copyWith(suffixIcon: const Icon(Icons.place_outlined)),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _aptSuiteController,
          decoration: _inputDecoration(app.addressInfoPageAptSuiteLabel),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cityController,
          enabled: false,
          decoration: _inputDecoration(app.addressInfoPageCityLabel),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _stateController,
                enabled: false,
                decoration: _inputDecoration(app.addressInfoPageStateLabel),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _zipController,
                enabled: false,
                decoration: _inputDecoration(app.addressInfoPageZipLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vehicle Form Field
// ─────────────────────────────────────────────────────────────────────────────

class _VehicleApi {
  static const _popularMakes = <String>{
    'ACURA',
    'ALFA ROMEO',
    'AUDI',
    'BMW',
    'BUICK',
    'CADILLAC',
    'CHEVROLET',
    'CHRYSLER',
    'DODGE',
    'FIAT',
    'FORD',
    'GENESIS',
    'GMC',
    'HONDA',
    'HYUNDAI',
    'INFINITI',
    'JAGUAR',
    'JEEP',
    'KIA',
    'LAND ROVER',
    'LEXUS',
    'LINCOLN',
    'MAZDA',
    'MERCEDES-BENZ',
    'MINI',
    'MITSUBISHI',
    'NISSAN',
    'PORSCHE',
    'RAM',
    'SUBARU',
    'TESLA',
    'TOYOTA',
    'VOLKSWAGEN',
    'VOLVO',
  };

  Future<List<String>> fetchMakes(int year, String query) async {
    const base = 'vpic.nhtsa.dot.gov';
    final paths = [
      '/api/vehicles/GetMakesForVehicleModelYear/$year',
      '/api/vehicles/GetMakesForVehicleModelYear/modelyear/$year',
    ];

    http.Response? res;
    for (final p in paths) {
      final uri = Uri.https(base, p, {'format': 'json'});
      res = await http.get(uri);
      if (res.statusCode == 200) break;
      if (res.statusCode == 404) continue;
      throw Exception('VPIC error ${res.statusCode} for $p');
    }

    if (res == null || res.statusCode == 404) {
      final uri = Uri.https(base, '/api/vehicles/GetAllMakes', {
        'format': 'json',
      });
      res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('VPIC GetAllMakes error ${res.statusCode}');
      }
    }

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (map['Results'] as List).cast<Map<String, dynamic>>();
    final q = query.toUpperCase();

    final originals = <String, String>{
      for (final row in list)
        (row['Make_Name'] as String).toUpperCase(): row['Make_Name'] as String,
    };

    List<String> ranked = originals.keys.where((m) => m.contains(q)).toList()
      ..sort((a, b) {
        int score(String m) => m == q ? 0 : (m.startsWith(q) ? 1 : 2);
        final s1 = score(a), s2 = score(b);
        return s1 != s2 ? s1.compareTo(s2) : a.compareTo(b);
      });

    final common = ranked.where(_popularMakes.contains).toList();
    if (common.isNotEmpty) ranked = common;

    String titleCase(String s) => s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
        .join(' ');

    return ranked.take(10).map((u) => titleCase(originals[u]!)).toList();
  }

  Future<List<String>> fetchModels(int year, String make, String query) async {
    final uri = Uri.https(
      'vpic.nhtsa.dot.gov',
      '/api/vehicles/GetModelsForMakeYear/make/$make/modelyear/$year',
      {'format': 'json'},
    );
    final res = await http.get(uri);

    if (res.statusCode == 404 || res.statusCode != 200) return [];

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (map['Results'] as List).cast<Map<String, dynamic>>();
    final q = query.toUpperCase();
    final set = <String>{
      for (final row in list) (row['Model_Name'] as String).toUpperCase(),
    };

    return set.where((m) => m.contains(q)).take(15).map((m) {
      return m
          .split(RegExp(r'\s+'))
          .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
          .join(' ');
    }).toList();
  }
}

class VehicleFormField extends StatefulWidget {
  final int initialYear;
  final String initialMake;
  final String initialModel;
  final bool isEditing;
  final void Function(int year, String make, String model) onChanged;

  const VehicleFormField({
    super.key,
    required this.initialYear,
    required this.initialMake,
    required this.initialModel,
    required this.isEditing,
    required this.onChanged,
  });

  @override
  State<VehicleFormField> createState() => _VehicleFormFieldState();
}

class _VehicleFormFieldState extends State<VehicleFormField> {
  late final TextEditingController _yearController;
  late final TextEditingController _makeController;
  late final TextEditingController _modelController;

  final FocusNode _modelFocusNode = FocusNode();

  final SuggestionsController<String> _makeSuggestionsController =
      SuggestionsController<String>();
  final SuggestionsController<String> _modelSuggestionsController =
      SuggestionsController<String>();

  bool _yearValid = false;
  bool _makeResolved = false;

  final _api = _VehicleApi();

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(
      text: widget.initialYear > 0 ? widget.initialYear.toString() : '',
    );
    _makeController = TextEditingController(text: widget.initialMake);
    _modelController = TextEditingController(text: widget.initialModel);

    _yearValid =
        widget.initialYear >= 1900 &&
        widget.initialYear <= DateTime.now().year + 1;
    _makeResolved = widget.initialMake.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant VehicleFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing != oldWidget.isEditing && !widget.isEditing) {
      _yearController.text = widget.initialYear > 0
          ? widget.initialYear.toString()
          : '';
      _makeController.text = widget.initialMake;
      _modelController.text = widget.initialModel;
      _yearValid =
          widget.initialYear >= 1900 &&
          widget.initialYear <= DateTime.now().year + 1;
      _makeResolved = widget.initialMake.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _yearController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _makeSuggestionsController.dispose();
    _modelSuggestionsController.dispose();
    _modelFocusNode.dispose();
    super.dispose();
  }

  void _onYearChanged(String text) {
    final yr = int.tryParse(text) ?? 0;
    final ok = yr >= 1900 && yr <= DateTime.now().year + 1;
    setState(() {
      _yearValid = ok;
      _makeResolved = false;
      _makeController.clear();
      _modelController.clear();
    });
    widget.onChanged(yr, '', '');
  }

  void _onMakeChanged(String text) {
    setState(() {
      _makeResolved = false;
      _modelController.clear();
    });
    // not a valid make until a suggestion is chosen
    widget.onChanged(int.tryParse(_yearController.text) ?? 0, '', '');
  }

  void _onModelChanged(String text) {
    setState(() {});
    // not a valid model until a suggestion is chosen
    widget.onChanged(
      int.tryParse(_yearController.text) ?? 0,
      _makeController.text,
      '',
    );
  }

  InputDecoration _decor(BuildContext ctx, String label) {
    final theme = Theme.of(ctx);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainer,
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

  @override
  Widget build(BuildContext context) {
    final app = AppLocalizations.of(context);

    if (!widget.isEditing) {
      return Column(
        children: [
          ProfileReadOnlyField(
            icon: Icons.calendar_today_outlined,
            label: app.myProfilePageVehicleYearLabel,
            value: widget.initialYear.toString(),
          ),
          const SizedBox(height: 16),
          ProfileReadOnlyField(
            icon: Icons.factory_outlined,
            label: app.myProfilePageVehicleMakeLabel,
            value: widget.initialMake,
          ),
          const SizedBox(height: 16),
          ProfileReadOnlyField(
            icon: Icons.directions_car_outlined,
            label: app.myProfilePageVehicleModelLabel,
            value: widget.initialModel,
          ),
        ],
      );
    }

    return Column(
      children: [
        TextField(
          controller: _yearController,
          onChanged: _onYearChanged,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: _decor(context, app.vehicleSetupPageYearLabel),
        ),
        const SizedBox(height: 16),
        TypeAheadField<String>(
          controller: _makeController,
          suggestionsController: _makeSuggestionsController,
          debounceDuration: const Duration(milliseconds: 300),
          hideOnSelect: true,
          hideOnEmpty: true,
          suggestionsCallback: (pattern) async {
            if (!_yearValid || pattern.length < 2) return const <String>[];
            try {
              return await _api.fetchMakes(
                int.parse(_yearController.text),
                pattern,
              );
            } catch (e) {
              return const <String>[];
            }
          },
          builder: (context, controller, focusNode) => TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: _onMakeChanged,
            enabled: _yearValid,
            decoration: _decor(context, app.vehicleSetupPageMakeLabel),
          ),
          itemBuilder: (context, s) => ListTile(title: Text(s)),
          onSelected: (suggestion) {
            setState(() {
              _makeController.text = suggestion;
              _makeResolved = true;
              _modelController.clear();
            });
            widget.onChanged(
              int.tryParse(_yearController.text) ?? 0,
              suggestion,
              '',
            );
            _makeSuggestionsController.close();
            // wait until the model field is rebuilt & enabled, then give focus
            // directly to the *model* text field instead of wrapping to the top
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _modelFocusNode.requestFocus();
            });
          },
        ),
        const SizedBox(height: 16),
        TypeAheadField<String>(
          controller: _modelController,
          suggestionsController: _modelSuggestionsController,
          debounceDuration: const Duration(milliseconds: 300),
          hideOnSelect: true,
          hideOnEmpty: true,
          suggestionsCallback: (pattern) async {
            if (!_yearValid || !_makeResolved || pattern.isEmpty) {
              return const <String>[];
            }
            return await _api.fetchModels(
              int.parse(_yearController.text),
              _makeController.text,
              pattern,
            );
          },
          builder: (context, controller, focusNode) => TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: _onModelChanged,
            enabled: _makeResolved,
            decoration: _decor(context, app.vehicleSetupPageModelLabel),
          ),
          itemBuilder: (context, s) => ListTile(title: Text(s)),
          onSelected: (suggestion) {
            setState(() {
              _modelController.text = suggestion;
            });
            widget.onChanged(
              int.tryParse(_yearController.text) ?? 0,
              _makeController.text,
              suggestion,
            );
            _modelSuggestionsController.close();
            FocusScope.of(
              context,
            ).unfocus(disposition: UnfocusDisposition.scope); // new
          },
          emptyBuilder: (context) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// A clean, read-only display for a profile field.
class ProfileReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const ProfileReadOnlyField({
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
              Text(value, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
