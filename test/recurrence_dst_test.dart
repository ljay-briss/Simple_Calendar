import 'package:flutter_test/flutter_test.dart';
import 'package:simple_calendar/main.dart';

void main() {
  test('daysBetweenUtc stays stable across DST offset shifts', () {
    final start = DateTime.parse('2024-03-09T00:00:00-05:00');
    final end = DateTime.parse('2024-03-16T00:00:00-04:00');

    expect(end.difference(start).inDays, 6);
    expect(daysBetweenUtc(start, end), 7);
  });
}
