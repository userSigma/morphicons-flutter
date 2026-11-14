import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morphicons/core.dart';

void main() {
  final path = Platform.environment['UPSTREAM_FIXTURES'];
  group('upstream TypeScript/Dart numerical parity', () {
    late Map<String, dynamic> fixtures;
    setUpAll(() {
      fixtures =
          jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>;
    });

    test('centerline plans agree at endpoints and intermediate frames', () {
      for (final raw in fixtures['pairs'] as List<dynamic>) {
        final pair = raw as Map<String, dynamic>;
        final plan = buildPlan(
          resampleIcon(pair['from'] as String),
          resampleIcon(pair['to'] as String),
        );
        final output = allocOutputs(plan);
        expect(plan.items.length, pair['items'],
            reason: pair['name'] as String);
        for (final rawFrame in pair['frames'] as List<dynamic>) {
          final frame = rawFrame as Map<String, dynamic>;
          interpPolar(plan, (frame['t'] as num).toDouble(), output);
          final expected = frame['points'] as List<dynamic>;
          for (var p = 0; p < output.length; p++) {
            final cloud = expected[p] as List<dynamic>;
            expect(output[p].length, cloud.length);
            for (var i = 0; i < cloud.length; i++) {
              expect(output[p][i], closeTo((cloud[i] as num).toDouble(), 1e-8),
                  reason: '${pair['name']} t=${frame['t']} path=$p point=$i');
            }
          }
        }
      }
    });

    test('spring presets and interruption retain the same numerical state', () {
      for (final raw in fixtures['springs'] as List<dynamic>) {
        final item = raw as Map<String, dynamic>;
        final spring = Spring()
          ..config((item['k'] as num).toDouble(), (item['c'] as num).toDouble())
          ..start();
        final states = item['states'] as List<dynamic>;
        for (var i = 0; i < states.length; i++) {
          if (i == 7) spring.start();
          final state = states[i] as Map<String, dynamic>;
          final settled = spring.step((state['dt'] as num).toDouble());
          expect(spring.x, closeTo((state['x'] as num).toDouble(), 1e-12));
          expect(spring.v, closeTo((state['v'] as num).toDouble(), 1e-12));
          expect(settled, state['settled']);
        }
      }
    });
  },
      skip: path == null
          ? 'Set UPSTREAM_FIXTURES after running the reference exporter.'
          : false);
}
