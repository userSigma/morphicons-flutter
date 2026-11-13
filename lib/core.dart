/// Pure Dart geometry, planning, serialization and spring integration.
/// This entry has no Flutter or platform imports.
library;

export 'src/core/types.dart';
export 'src/core/normalize.dart' show fitIcon, iconToCubics, ViewBox;
export 'src/core/resample.dart' show resampleIcon, resamplePath;
export 'src/core/plan.dart' show buildPlan, MorphPlan, PlanItem;
export 'src/core/interpolate.dart' show allocOutputs, interpPolar, interpLinear;
export 'src/core/serialize.dart' show cubicsToPathD, serialize;
export 'src/core/spring.dart';
export 'src/core/region.dart' show IconPaint, paintOf;
