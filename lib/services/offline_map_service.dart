import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/journey.dart';

/// Service managing persistent offline OpenStreetMap raster tiles.
///
/// Complies with OpenStreetMap Foundation Tile Usage Policy:
/// - Uses descriptive, custom User-Agent header.
/// - Limits prefetch bounding box and max tile count (max 80 tiles per journey).
/// - Enforces rate-limiting delay between requests (min 100ms).
/// - Never performs aggressive bulk scraping or scraping of zoom levels > 15.
class OfflineMapService {
  OfflineMapService({
    http.Client? client,
    this.customStorageDir,
  })  : _client = client ?? http.Client();

  final http.Client _client;
  final Directory? customStorageDir;

  static const String userAgent =
      'STOPVanthachu-App/1.0 (info@stopvanthachu.app; Smart Transit Companion)';
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  Directory? _cachedBaseDir;

  /// Returns the base directory for offline tile storage.
  Future<Directory> getStorageDirectory() async {
    final custom = customStorageDir;
    if (custom != null) return custom;
    if (_cachedBaseDir != null) return _cachedBaseDir!;
    final appDir = await getApplicationSupportDirectory();
    final tilesDir = Directory('${appDir.path}/offline_tiles');
    if (!tilesDir.existsSync()) {
      tilesDir.createSync(recursive: true);
    }
    return _cachedBaseDir = tilesDir;
  }

  /// Calculates total size and count of cached tiles on disk.
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final dir = await getStorageDirectory();
      if (!dir.existsSync()) {
        return {'count': 0, 'bytes': 0, 'formattedSize': '0 KB'};
      }

      int count = 0;
      int totalBytes = 0;

      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.png')) {
          count++;
          totalBytes += entity.lengthSync();
        }
      }

      final formatted = totalBytes > 1024 * 1024
          ? '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(totalBytes / 1024).toStringAsFixed(0)} KB';

      return {
        'count': count,
        'bytes': totalBytes,
        'formattedSize': formatted,
      };
    } catch (e) {
      debugPrint('[OfflineMapService] Error getting cache stats: $e');
      return {'count': 0, 'bytes': 0, 'formattedSize': '0 KB'};
    }
  }

  /// Clears all cached offline map tiles from device storage.
  Future<bool> clearTileCache() async {
    try {
      final dir = await getStorageDirectory();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
      }
      return true;
    } catch (e) {
      debugPrint('[OfflineMapService] Error clearing cache: $e');
      return false;
    }
  }

  /// Converts latitude to Web Mercator tile Y coordinate.
  static int latToTileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180.0;
    final n = math.pow(2.0, zoom);
    return ((1.0 - math.log(math.tan(latRad) + (1.0 / math.cos(latRad))) / math.pi) /
            2.0 *
            n)
        .floor();
  }

  /// Converts longitude to Web Mercator tile X coordinate.
  static int lonToTileX(double lon, int zoom) {
    final n = math.pow(2.0, zoom);
    return (((lon + 180.0) / 360.0) * n).floor();
  }

  /// Returns target file path for a specific tile.
  Future<File> getTileFile(int z, int x, int y) async {
    final dir = await getStorageDirectory();
    return File('${dir.path}/$z/$x/$y.png');
  }

  /// Checks if a tile is already cached locally.
  Future<bool> isTileCached(int z, int x, int y) async {
    final file = await getTileFile(z, x, y);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// Fetches and caches a single map tile, respecting OSM policy.
  Future<bool> downloadAndCacheTile(int z, int x, int y) async {
    try {
      final file = await getTileFile(z, x, y);
      if (file.existsSync() && file.lengthSync() > 0) {
        return true; // Already cached
      }

      final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': userAgent,
          'Accept': 'image/png,image/*',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (!file.parent.existsSync()) {
          file.parent.createSync(recursive: true);
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[OfflineMapService] Failed to cache tile $z/$x/$y: $e');
      return false;
    }
  }

  /// Pre-fetches tiles covering all stops in [journey] for offline transit monitoring.
  ///
  /// Strictly bounds zoom levels (12-14) and caps total tiles to 80 to adhere to OSM guidelines.
  Future<int> prefetchJourneyMap(
    Journey journey, {
    Function(int current, int total)? onProgress,
    int minZoom = 12,
    int maxZoom = 14,
    int maxTilesCap = 80,
  }) async {
    if (journey.stops.isEmpty) return 0;

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLon = double.infinity;
    double maxLon = -double.infinity;

    for (final stop in journey.stops) {
      if (stop.latitude < minLat) minLat = stop.latitude;
      if (stop.latitude > maxLat) maxLat = stop.latitude;
      if (stop.longitude < minLon) minLon = stop.longitude;
      if (stop.longitude > maxLon) maxLon = stop.longitude;
    }

    // Add 0.02 degree safety margin (~2.2 km)
    minLat -= 0.02;
    maxLat += 0.02;
    minLon -= 0.02;
    maxLon += 0.02;

    // Collect all tile coordinates across zoom levels
    final tilesToDownload = <List<int>>[];

    for (int z = minZoom; z <= maxZoom; z++) {
      final startX = lonToTileX(minLon, z);
      final endX = lonToTileX(maxLon, z);
      final startY = latToTileY(maxLat, z); // Note: Y coordinates invert in Mercator
      final endY = latToTileY(minLat, z);

      final minX = math.min(startX, endX);
      final maxX = math.max(startX, endX);
      final minY = math.min(startY, endY);
      final maxY = math.max(startY, endY);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tilesToDownload.add([z, x, y]);
          if (tilesToDownload.length >= maxTilesCap) break;
        }
        if (tilesToDownload.length >= maxTilesCap) break;
      }
      if (tilesToDownload.length >= maxTilesCap) break;
    }

    int downloadedCount = 0;
    final total = tilesToDownload.length;

    for (int i = 0; i < total; i++) {
      final tile = tilesToDownload[i];
      final success = await downloadAndCacheTile(tile[0], tile[1], tile[2]);
      if (success) downloadedCount++;

      if (onProgress != null) {
        onProgress(i + 1, total);
      }

      // Mandatory rate-limiting pause to respect OpenStreetMap servers (100ms)
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    return downloadedCount;
  }
}

/// Custom [TileProvider] that seamlessly loads tiles from local disk cache
/// and gracefully falls back to network when online.
class PersistentOfflineTileProvider extends TileProvider {
  PersistentOfflineTileProvider({
    OfflineMapService? offlineService,
  }) : offlineService = offlineService ?? OfflineMapService();

  final OfflineMapService offlineService;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _PersistentTileImage(
      coordinates: coordinates,
      options: options,
      offlineService: offlineService,
    );
  }
}

class _PersistentTileImage extends ImageProvider<_PersistentTileImage> {
  const _PersistentTileImage({
    required this.coordinates,
    required this.options,
    required this.offlineService,
  });

  final TileCoordinates coordinates;
  final TileLayer options;
  final OfflineMapService offlineService;

  @override
  Future<_PersistentTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_PersistentTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(_PersistentTileImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadAsync(key, decode));
  }

  Future<ImageInfo> _loadAsync(_PersistentTileImage key, ImageDecoderCallback decode) async {
    final z = key.coordinates.z.toInt();
    final x = key.coordinates.x.toInt();
    final y = key.coordinates.y.toInt();

    // 1. Check if cached on local disk
    final file = await key.offlineService.getTileFile(z, x, y);
    if (file.existsSync() && file.lengthSync() > 0) {
      final bytes = await file.readAsBytes();
      final buffer = await uiDecode(bytes, decode);
      return ImageInfo(image: buffer);
    }

    // 2. Not on disk: Fetch from network and persist
    try {
      final url = options.urlTemplate
          ?.replaceAll('{z}', z.toString())
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString());

      if (url == null) throw Exception('No URL template configured');

      final uri = Uri.parse(url);
      final client = http.Client();
      try {
        final response = await client.get(
          uri,
          headers: {
            'User-Agent': OfflineMapService.userAgent,
            'Accept': 'image/png,image/*',
          },
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          if (!file.parent.existsSync()) {
            file.parent.createSync(recursive: true);
          }
          await file.writeAsBytes(response.bodyBytes, flush: true);
          final buffer = await uiDecode(response.bodyBytes, decode);
          return ImageInfo(image: buffer);
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[PersistentOfflineTileProvider] Tile fetch failed for $z/$x/$y (offline): $e');
    }

    // Return empty fallback transparent 1x1 image so flutter_map doesn't crash in Airplane Mode
    final transparent1x1 = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
      0x00, 0x05, 0x00, 0x01, 0xE9, 0xFA, 0xDC, 0xD8, 0x00, 0x00, 0x00, 0x00,
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    final buffer = await uiDecode(transparent1x1, decode);
    return ImageInfo(image: buffer);
  }

  Future<ui.Image> uiDecode(Uint8List bytes, ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _PersistentTileImage &&
        other.coordinates == coordinates &&
        other.options.urlTemplate == options.urlTemplate;
  }

  @override
  int get hashCode => Object.hash(coordinates, options.urlTemplate);
}
