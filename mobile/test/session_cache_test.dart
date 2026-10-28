import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanage/session_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionCache.clearDataCache();
  });

  test('room cache expires after 15 minutes and is removed', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rooms_cache_json', '[]');
    await prefs.setInt(
      'rooms_cache_saved_at',
      DateTime.now()
          .subtract(const Duration(minutes: 16))
          .millisecondsSinceEpoch,
    );

    expect(await SessionCache.loadRooms(), isNull);
    expect(prefs.containsKey('rooms_cache_json'), isFalse);
    expect(prefs.containsKey('rooms_cache_saved_at'), isFalse);
  });

  test('room cache without a timestamp is removed', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rooms_cache_json', '[]');

    expect(await SessionCache.loadRooms(), isNull);
    expect(prefs.containsKey('rooms_cache_json'), isFalse);
  });

  test(
    'room cache is not accepted when its timestamp is in the future',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rooms_cache_json', '[]');
      await prefs.setInt(
        'rooms_cache_saved_at',
        DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );

      expect(await SessionCache.loadRooms(), isNull);
      expect(prefs.containsKey('rooms_cache_json'), isFalse);
    },
  );
}
