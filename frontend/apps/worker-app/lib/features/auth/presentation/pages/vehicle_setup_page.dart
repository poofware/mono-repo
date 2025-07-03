// worker-app/lib/features/auth/presentation/pages/vehicle_setup_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/features/account/data/models/models.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

// ─────────────────────────────────────────────────────────────────────────────
// vPIC helper (year-specific makes + models)
// ─────────────────────────────────────────────────────────────────────────────
class _VehicleApi {
  static const _popularMakes = <String>{
    'ACURA','ALFA ROMEO','AUDI','BMW','BUICK','CADILLAC','CHEVROLET','CHRYSLER',
    'DODGE','FIAT','FORD','GENESIS','GMC','HONDA','HYUNDAI','INFINITI','JAGUAR',
    'JEEP','KIA','LAND ROVER','LEXUS','LINCOLN','MAZDA','MERCEDES-BENZ','MINI',
    'MITSUBISHI','NISSAN','PORSCHE','RAM','SUBARU','TESLA','TOYOTA',
    'VOLKSWAGEN','VOLVO'
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

    // fall back to master list if year-specific list not found
    if (res == null || res.statusCode == 404) {
      final uri = Uri.https(base, '/api/vehicles/GetAllMakes', {'format': 'json'});
      res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('VPIC GetAllMakes error ${res.statusCode}');
      }
    }

    final map  = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (map['Results'] as List).cast<Map<String, dynamic>>();
    final q    = query.toUpperCase();

    final originals = <String,String>{
      for (final row in list) (row['Make_Name'] as String).toUpperCase():
                             row['Make_Name'] as String
    };

    List<String> ranked = originals.keys.where((m) => m.contains(q)).toList()
      ..sort((a,b) {
        int score(String m) => m==q?0:(m.startsWith(q)?1:2);
        final s1=score(a), s2=score(b);
        return s1!=s2? s1.compareTo(s2): a.compareTo(b);
      });

    final common = ranked.where(_popularMakes.contains).toList();
    if (common.isNotEmpty) ranked = common;

    String titleCase(String s) => s.split(RegExp(r'\s+'))
        .map((w) => w.isEmpty? w : w[0] + w.substring(1).toLowerCase())
        .join(' ');

    return ranked.take(10).map((u) => titleCase(originals[u]!)).toList();
  }

  Future<List<String>> fetchModels(int year, String make, String query) async {
    final uri = Uri.https(
      'vpic.nhtsa.dot.gov',
      '/api/vehicles/GetModelsForMakeYear/make/$make/modelyear/$year',
      {'format':'json'},
    );
    final res = await http.get(uri);

    if (res.statusCode == 404 || res.statusCode != 200) return [];

    final map  = jsonDecode(res.body) as Map<String,dynamic>;
    final list = (map['Results'] as List).cast<Map<String,dynamic>>();
    final q    = query.toUpperCase();
    final set  = <String>{
      for (final row in list) (row['Model_Name'] as String).toUpperCase()
    };

    return set.where((m)=>m.contains(q)).take(15).map((m){
      return m.split(RegExp(r'\s+'))
          .map((w)=> w.isEmpty? w : w[0] + w.substring(1).toLowerCase())
          .join(' ');
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────
class VehicleSetupPage extends ConsumerStatefulWidget {
  const VehicleSetupPage({super.key});
  @override
  ConsumerState<VehicleSetupPage> createState() => _VehicleSetupPageState();
}

class _VehicleSetupPageState extends ConsumerState<VehicleSetupPage> {
  late final TextEditingController _yearController;
  late final TextEditingController _makeController;
  late final TextEditingController _modelController;

  final SuggestionsController<String> _makeSuggestionsController  =
      SuggestionsController<String>();
  final SuggestionsController<String> _modelSuggestionsController =
      SuggestionsController<String>();

  bool _yearValid     = false;
  bool _makeResolved  = false;
  bool _modelResolved = false;
  bool _isLoading     = false;

  final _api = _VehicleApi();

  @override
  void initState() {
    super.initState();
    _yearController  = TextEditingController();
    _makeController  = TextEditingController();
    _modelController = TextEditingController();

    // Populate controllers from provider state after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final signUpState = ref.read(signUpProvider);
        if (signUpState.vehicleYear > 0) {
          final yr = signUpState.vehicleYear;
          final ok = yr >= 1900 && yr <= DateTime.now().year + 1;
          setState(() {
            _yearController.text = yr.toString();
            _yearValid = ok;
          });
        }
        if (signUpState.vehicleMake.isNotEmpty) {
          setState(() {
            _makeController.text = signUpState.vehicleMake;
            _makeResolved = true;
          });
        }
        if (signUpState.vehicleModel.isNotEmpty) {
          setState(() {
            _modelController.text = signUpState.vehicleModel;
            _modelResolved = true;
          });
        }
      }
    });
  }

  bool get _canContinue =>
      !_isLoading && _yearValid && _makeResolved && _modelResolved;

  // ─────────── handlers ───────────
  void _onYearChanged(String text) {
    final yr = int.tryParse(text) ?? 0;
    final ok = yr >= 1900 && yr <= DateTime.now().year + 1;
    if (ok != _yearValid) {
      setState(() => _yearValid = ok);
    }

    setState(() {
      _makeResolved  = false;
      _modelResolved = false;
      _makeController.clear();
      _modelController.clear();
    });

    // Update the provider state
    ref.read(signUpProvider.notifier).setVehicleInfo(
      vehicleYear: yr,
      vehicleMake: '',
      vehicleModel: '',
    );
  }

  void _onMakeChanged(String text) {
    setState(() {
      _makeResolved  = false;
      _modelResolved = false;
      _modelController.clear();
    });

    // Update the provider state
    ref.read(signUpProvider.notifier).setVehicleInfo(
      vehicleMake: text,
      vehicleModel: '',
    );
  }

  void _onModelChanged(String text) {
    setState(() => _modelResolved = false);

    // Update the provider state
    ref.read(signUpProvider.notifier).setVehicleInfo(
      vehicleModel: text,
    );
  }

  Future<void> _onContinue() async {
    if (!_canContinue) return;
    setState(() => _isLoading = true);

    // Read the source of truth from the provider
    final onboarding = ref.read(signUpProvider);
    final isTestMode = PoofWorkerFlavorConfig.instance.testMode;

    try {
      if (!isTestMode) {
        final repo = ref.read(workerAccountRepositoryProvider);
        final req  = SubmitPersonalInfoRequest(
          streetAddress : onboarding.streetAddress,
          aptSuite      : onboarding.aptSuite.isEmpty ? null : onboarding.aptSuite,
          city          : onboarding.city,
          state         : onboarding.stateName,
          zipCode       : onboarding.zipCode,
          vehicleYear   : onboarding.vehicleYear,
          vehicleMake   : onboarding.vehicleMake,
          vehicleModel  : onboarding.vehicleModel,
        );
        await repo.submitPersonalInfo(req);
      }
      if (mounted) context.pushNamed(AppRouteNames.stripeIdvPage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            e is ApiException
                ? userFacingMessage(context, e)
                : AppLocalizations.of(context).loginUnexpectedError(e.toString()),
          )),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────── UI helpers ───────────
  InputDecoration _decor(BuildContext ctx, String label) {
    final theme = Theme.of(ctx);
    return InputDecoration(
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
  }

  Widget _yearField(BuildContext ctx, String label) => TextField(
        controller      : _yearController,
        onChanged       : _onYearChanged,
        keyboardType    : TextInputType.number,
        inputFormatters : [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: _decor(ctx, label),
      );

  Widget _makeField(BuildContext ctx, String label) {
    Future<List<String>> suggestions(String pattern) async {
      if (!_yearValid || pattern.length < 2) return const <String>[];
      try {
        return await _api.fetchMakes(int.parse(_yearController.text), pattern);
      } catch (e, s) {
        debugPrint('fetchMakes failed: $e\n$s');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to load makes')));
        }
        return const <String>[];
      }
    }

    void onSelect(String suggestion) {
      setState(() {
        _makeController.text = suggestion;
        _makeResolved        = true;
        _modelResolved       = false;
        _modelController.clear();
      });

      // Update provider state
      ref.read(signUpProvider.notifier).setVehicleInfo(
        vehicleMake: suggestion,
        vehicleModel: '',
      );

      _makeSuggestionsController.close();
      FocusScope.of(context).nextFocus();
    }

    return TypeAheadField<String>(
      controller           : _makeController,
      suggestionsController: _makeSuggestionsController,
      debounceDuration     : const Duration(milliseconds: 300),
      hideOnSelect         : true,
      hideOnEmpty          : true,
      suggestionsCallback  : suggestions,
      builder              : (context, controller, focusNode) => TextField(
        controller : controller,
        focusNode  : focusNode,
        onChanged  : _onMakeChanged,
        enabled    : _yearValid,
        decoration : _decor(ctx, label),
      ),
      itemBuilder : (context, s) => ListTile(title: Text(s)),
      onSelected  : onSelect,
      emptyBuilder: (context) => const SizedBox.shrink(),
    );
  }

  Widget _modelField(BuildContext ctx, String label) {
    Future<List<String>> suggestions(String pattern) async {
      if (!_yearValid || !_makeResolved || pattern.isEmpty) return const <String>[];
      return await _api.fetchModels(
        int.parse(_yearController.text),
        _makeController.text,
        pattern,
      );
    }

    void onSelect(String suggestion) {
      setState(() {
        _modelController.text = suggestion;
        _modelResolved        = true;
      });
      
      // Update provider state
      ref.read(signUpProvider.notifier).setVehicleInfo(
        vehicleModel: suggestion,
      );

      _modelSuggestionsController.close();
      FocusScope.of(context).nextFocus();
    }

    return TypeAheadField<String>(
      controller           : _modelController,
      suggestionsController: _modelSuggestionsController,
      debounceDuration     : const Duration(milliseconds: 300),
      hideOnSelect         : true,
      hideOnEmpty          : true,
      suggestionsCallback  : suggestions,
      builder              : (context, controller, focusNode) => TextField(
        controller : controller,
        focusNode  : focusNode,
        onChanged  : _onModelChanged,
        enabled    : _makeResolved,
        decoration : _decor(ctx, label),
      ),
      itemBuilder : (context, s) => ListTile(title: Text(s)),
      onSelected  : onSelect,
      emptyBuilder: (context) => const SizedBox.shrink(),
    );
  }

  // ─────────── lifecycle ───────────
  @override
  void dispose() {
    _yearController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _makeSuggestionsController.dispose();
    _modelSuggestionsController.dispose();
    super.dispose();
  }

  // ─────────── build ───────────
  @override
  Widget build(BuildContext context) {
    final app   = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
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
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => context.pop(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Center(
                        child: Icon(Icons.directions_car_outlined,
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
                        app.vehicleSetupPageTitle,
                        style: theme.textTheme.headlineLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      )
                          .animate()
                          .fadeIn(delay: 300.ms)
                          .slideX(
                              begin: -0.1,
                              duration: 400.ms,
                              curve: Curves.easeOutCubic),
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          app.vehicleSetupPageSubtitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 400.ms)
                          .slideX(
                              begin: -0.1,
                              duration: 400.ms,
                              curve: Curves.easeOutCubic),
                      const SizedBox(height: 32),

                      _yearField(context, app.vehicleSetupPageYearLabel),
                      const SizedBox(height: 16),

                      _makeField(context, app.vehicleSetupPageMakeLabel),
                      const SizedBox(height: 16),

                      _modelField(context, app.vehicleSetupPageModelLabel),
                    ]
                        .animate(interval: 80.ms)
                        .fadeIn(duration: 500.ms, delay: 500.ms)
                        .slideY(begin: 0.1),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: WelcomeButton(
                  text      : app.vehicleSetupPageContinueButton,
                  isLoading : _isLoading,
                  onPressed : _canContinue ? _onContinue : null,
                )
                .animate()
                .fadeIn(delay: 600.ms, duration: 400.ms)
                .slideY(begin: 0.5),
             ),
            ],
          ),
        ),
      ),
    );
  }
}

