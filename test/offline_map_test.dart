import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pathsaathi/data/station_database.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/offline_map_service.dart';

void main() {
  group('Issue 4: Offline Maps Functionality & Persistent Cache Tests', () {
    late Directory tempDir;
    late OfflineMapService offlineService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('stop_vanthachu_offline_tiles_');
      final mockClient = MockClient((request) async {
        // Return dummy PNG image bytes
        final dummyPng = [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
          0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
          0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
          0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ];
        return http.Response.bytes(dummyPng, 200);
      });

      offlineService = OfflineMapService(
        client: mockClient,
        customStorageDir: tempDir,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('calculates correct Web Mercator tile X and Y coordinates', () {
      // Chennai Central: 13.0827° N, 80.2707° E
      final tileX = OfflineMapService.lonToTileX(80.2707, 12);
      final tileY = OfflineMapService.latToTileY(13.0827, 12);

      expect(tileX, equals(2961));
      expect(tileY, equals(1897));
    });

    test('downloads and caches map tiles locally to persistent storage', () async {
      final success = await offlineService.downloadAndCacheTile(12, 2961, 1897);
      expect(success, isTrue);

      final isCached = await offlineService.isTileCached(12, 2961, 1897);
      expect(isCached, isTrue);

      final tileFile = await offlineService.getTileFile(12, 2961, 1897);
      expect(tileFile.existsSync(), isTrue);
      expect(tileFile.lengthSync(), greaterThan(0));
    });

    test('calculates disk cache stats accurately', () async {
      await offlineService.downloadAndCacheTile(12, 2961, 1897);
      await offlineService.downloadAndCacheTile(12, 2961, 1898);

      final stats = await offlineService.getCacheStats();
      expect(stats['count'], equals(2));
      expect(stats['bytes'], greaterThan(0));
      expect(stats['formattedSize'], isNotEmpty);
    });

    test('clears offline map tile cache completely', () async {
      await offlineService.downloadAndCacheTile(12, 2961, 1897);
      final preStats = await offlineService.getCacheStats();
      expect(preStats['count'], equals(1));

      final cleared = await offlineService.clearTileCache();
      expect(cleared, isTrue);

      final postStats = await offlineService.getCacheStats();
      expect(postStats['count'], equals(0));
      expect(postStats['bytes'], equals(0));
    });

    test('prefetches journey map tiles adhering to OSM bounding box and rate limiting', () async {
      final stop1 = Stop(
        id: 's1',
        name: 'Guindy',
        latitude: 13.0067,
        longitude: 80.2025,
        order: 0,
      );
      final stop2 = Stop(
        id: 's2',
        name: 'Central',
        latitude: 13.0827,
        longitude: 80.2707,
        order: 1,
      );

      final journey = Journey(
        id: 'j_offline',
        name: 'Chennai Express',
        stops: [stop1, stop2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final progressReports = <int>[];
      final cachedCount = await offlineService.prefetchJourneyMap(
        journey,
        minZoom: 12,
        maxZoom: 12, // Test single zoom to verify bounding calculation
        maxTilesCap: 20,
        onProgress: (current, total) {
          progressReports.add(current);
        },
      );

      expect(cachedCount, greaterThan(0));
      expect(cachedCount, lessThanOrEqualTo(20));
      expect(progressReports, isNotEmpty);
    });

    test('provides PersistentOfflineTileProvider that instantiates cleanly', () {
      final provider = PersistentOfflineTileProvider(offlineService: offlineService);
      expect(provider, isNotNull);
      expect(provider.offlineService, equals(offlineService));
    });

    test('verifies 100% offline station search via curated local database', () {
      final resultsCentral = LocalStationDatabase.search('Central');
      expect(resultsCentral, isNotEmpty);
      expect(resultsCentral.first.name, contains('Central'));

      final resultsGuindy = LocalStationDatabase.search('Guindy');
      expect(resultsGuindy, isNotEmpty);
      expect(resultsGuindy.first.name, contains('Guindy'));

      final resultsEmpty = LocalStationDatabase.search('NonExistentPlaceXYZ123');
      expect(resultsEmpty, isEmpty);
    });
  });
}
