// worker-app/lib/features/jobs/data/models/dummy_week_job_data.dart

import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:intl/intl.dart';

String _makeServiceDate(int dayOffset) =>
    DateFormat('yyyy-MM-dd').format(DateTime.now().add(Duration(days: dayOffset)));

class DummyWeekJobData {
  static final List<JobInstance> acceptedJobs = [
    /* existing 7 instances kept as-is … */

    // extra six
    JobInstance(
      instanceId: 'week_Lakeview_Towers',
      definitionId: 'def_Wk_Lakeview_Towers',
      propertyId: 'prop_Wk_Lakeview_Towers',
      serviceDate: _makeServiceDate(0),
      status: JobInstanceStatus.assigned,
      pay: 38,
      property: const Property(
        propertyId: 'prop_Wk_Lakeview_Towers',
        propertyName: 'Lakeview Towers',
        address: '808 Lakeview Cir',
        city: 'Huntsville', // Assuming city
        state: 'AL',        // Assuming state
        zipCode: '35801',   // Assuming zip
        latitude: 34.7312,
        longitude: -86.5805,
      ),
      numberOfBuildings: 2,
      buildings: const [],
      numberOfDumpsters: 1,
      dumpsters: const [],
      startTimeHint: '11:00',
      workerStartTimeHint: '11:00',
      propertyServiceWindowStart: '11:00',
      workerServiceWindowStart: '11:00',
      propertyServiceWindowEnd: '19:00',
      workerServiceWindowEnd: '19:00',
      distanceMiles: 1.4,
      travelMinutes: 15,
      estimatedTimeMinutes: 60,
      transportMode: TransportMode.car,
    ),
    JobInstance(
      instanceId: 'week_Meadowlark_Court',
      definitionId: 'def_Wk_Meadowlark_Court',
      propertyId: 'prop_Wk_Meadowlark_Court',
      serviceDate: _makeServiceDate(1),
      status: JobInstanceStatus.assigned,
      pay: 25,
      property: const Property(
        propertyId: 'prop_Wk_Meadowlark_Court',
        propertyName: 'Meadowlark Court',
        address: '909 Meadowlark Ct',
        city: 'Huntsville', // Assuming city
        state: 'AL',        // Assuming state
        zipCode: '35801',   // Assuming zip
        latitude: 34.7308,
        longitude: -86.5815,
      ),
      numberOfBuildings: 1,
      buildings: const [],
      numberOfDumpsters: 0,
      dumpsters: const [],
      startTimeHint: '10:15',
      workerStartTimeHint: '10:15',
      propertyServiceWindowStart: '10:15',
      workerServiceWindowStart: '10:15',
      propertyServiceWindowEnd: '18:15',
      workerServiceWindowEnd: '18:15',
      distanceMiles: 0.5,
      travelMinutes: 10,
      estimatedTimeMinutes: 55,
      transportMode: TransportMode.walk,
    ),
    JobInstance(
      instanceId: 'week_Parkside_Commons',
      definitionId: 'def_Wk_Parkside_Commons',
      propertyId: 'prop_Wk_Parkside_Commons',
      serviceDate: _makeServiceDate(2),
      status: JobInstanceStatus.assigned,
      pay: 46,
      property: const Property(
        propertyId: 'prop_Wk_Parkside_Commons',
        propertyName: 'Parkside Commons',
        address: '1010 Parkside Blvd',
        city: 'Huntsville', // Assuming city
        state: 'AL',        // Assuming state
        zipCode: '35801',   // Assuming zip
        latitude: 34.7328,
        longitude: -86.5775,
      ),
      numberOfBuildings: 3,
      buildings: const [],
      numberOfDumpsters: 1,
      dumpsters: const [],
      startTimeHint: '14:30',
      workerStartTimeHint: '14:30',
      propertyServiceWindowStart: '14:30',
      workerServiceWindowStart: '14:30',
      propertyServiceWindowEnd: '22:30',
      workerServiceWindowEnd: '22:30',
      distanceMiles: 3.3,
      travelMinutes: 15,
      estimatedTimeMinutes: 19,
      transportMode: TransportMode.car,
    ),
    JobInstance(
      instanceId: 'week_Birchwood_Trails',
      definitionId: 'def_Wk_Birchwood_Trails',
      propertyId: 'prop_Wk_Birchwood_Trails',
      serviceDate: _makeServiceDate(3),
      status: JobInstanceStatus.assigned,
      pay: 31,
      property: const Property(
        propertyId: 'prop_Wk_Birchwood_Trails',
        propertyName: 'Birchwood Trails',
        address: '111 Birchwood Trl',
        city: 'Huntsville', // Assuming city
        state: 'AL',        // Assuming state
        zipCode: '35801',   // Assuming zip
        latitude: 34.7302,
        longitude: -86.5840,
      ),
      numberOfBuildings: 1,
      buildings: const [],
      numberOfDumpsters: 0,
      dumpsters: const [],
      startTimeHint: '09:45',
      workerStartTimeHint: '09:45',
      propertyServiceWindowStart: '09:45',
      workerServiceWindowStart: '09:45',
      propertyServiceWindowEnd: '17:45',
      workerServiceWindowEnd: '17:45',
      distanceMiles: 1.1,
      travelMinutes: 15,
      estimatedTimeMinutes: 24,
      transportMode: TransportMode.walk,
    ),
    JobInstance(
      instanceId: 'week_Cottonwood_Place',
      definitionId: 'def_Wk_Cottonwood_Place',
      propertyId: 'prop_Wk_Cottonwood_Place',
      serviceDate: _makeServiceDate(5),
      status: JobInstanceStatus.assigned,
      pay: 44,
      property: const Property(
        propertyId: 'prop_Wk_Cottonwood_Place',
        propertyName: 'Cottonwood Place',
        address: '1212 Cottonwood Pl',
        city: 'Huntsville', // Assuming city
        state: 'AL',        // Assuming state
        zipCode: '35801',   // Assuming zip
        latitude: 34.7337,
        longitude: -86.5892,
      ),
      numberOfBuildings: 2,
      buildings: const [],
      numberOfDumpsters: 1,
      dumpsters: const [],
      startTimeHint: '13:50',
      workerStartTimeHint: '13:50',
      propertyServiceWindowStart: '13:50',
      workerServiceWindowStart: '13:50',
      propertyServiceWindowEnd: '21:50',
      workerServiceWindowEnd: '21:50',
      distanceMiles: 2.6,
      travelMinutes: 15,
      estimatedTimeMinutes: 37,
      transportMode: TransportMode.car,
    ),
    JobInstance(
      instanceId: 'week_Highland_Vista',
      definitionId: 'def_Wk_Highland_Vista',
      propertyId: 'prop_Wk_Highland_Vista',
      serviceDate: _makeServiceDate(6),
      status: JobInstanceStatus.assigned,
      pay: 36,
      property: const Property(
        propertyId: 'prop_Wk_Highland_Vista',
        propertyName: 'Highland Vista',
        address: '1313 Highland Vis',
        city: 'Huntsville', // Assuming city
        state: 'AL',        // Assuming state
        zipCode: '35801',   // Assuming zip
        latitude: 34.7350,
        longitude: -86.5903,
      ),
      numberOfBuildings: 1,
      buildings: const [],
      numberOfDumpsters: 0,
      dumpsters: const [],
      startTimeHint: '12:30',
      workerStartTimeHint: '12:30',
      propertyServiceWindowStart: '12:30',
      workerServiceWindowStart: '12:30',
      propertyServiceWindowEnd: '20:30',
      workerServiceWindowEnd: '20:30',
      distanceMiles: 3.9,
      travelMinutes: 15,
      estimatedTimeMinutes: 30,
      transportMode: TransportMode.car,
    ),
  ];
}
