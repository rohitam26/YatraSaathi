import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/station_database.dart';

/// Represents a geographic place found via geocoding search or reverse geocoding.
class GeocodedPlace {
  const GeocodedPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.category = 'Place',
    this.categoryType,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;
  final String? categoryType;

  @override
  String toString() => '$name [$category] ($latitude, $longitude)';
}

/// Service providing OpenStreetMap geocoding and reverse geocoding with
/// multi-provider fallback (Photon by Komoot + Nominatim), rich categorization
/// (railway stations, metro, bus terminals, hospitals, colleges, landmarks),
/// debounced search, and offline fallback.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // Rate limiting timestamp (Nominatim requires max 1 req/sec)
  static DateTime _lastNominatimRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  static const String _userAgent = 'STOPVanthachu-App/1.0 (info@stopvanthachu.app)';

  /// Categorizes a place based on OSM tags and query name.
  static String categorizePlace({
    String? osmKey,
    String? osmValue,
    String? className,
    String? typeName,
    required String name,
  }) {
    final lowerName = name.toLowerCase();
    final lowerKey = (osmKey ?? className ?? '').toLowerCase();
    final lowerVal = (osmValue ?? typeName ?? '').toLowerCase();

    // Metro Station (checked first because in OSM subway stations have osm_key: railway, osm_value: subway)
    if (lowerVal == 'subway' ||
        lowerVal == 'subway_entrance' ||
        lowerVal == 'tram_stop' ||
        lowerName.contains('metro') ||
        lowerName.contains('subway')) {
      return 'Metro Station';
    }

    // Railway Station
    if (lowerVal == 'station' ||
        lowerKey == 'railway' ||
        lowerName.contains('railway station') ||
        lowerName.contains(' rly stn') ||
        lowerName.contains('junction') ||
        lowerName.contains('terminus')) {
      return 'Railway Station';
    }

    // Bus Terminal / Stop
    if (lowerVal == 'bus_station' ||
        lowerVal == 'bus_stop' ||
        lowerName.contains('bus stand') ||
        lowerName.contains('bus terminal') ||
        lowerName.contains('bus stop') ||
        lowerName.contains('isbt')) {
      return 'Bus Terminal';
    }

    // Hospital / Medical
    if (lowerVal == 'hospital' ||
        lowerVal == 'clinic' ||
        lowerVal == 'doctors' ||
        lowerVal == 'pharmacy' ||
        lowerName.contains('hospital') ||
        lowerName.contains('clinic') ||
        lowerName.contains('dispensary')) {
      return 'Hospital / Health';
    }

    // College / University / Education
    if (lowerVal == 'college' ||
        lowerVal == 'university' ||
        lowerVal == 'school' ||
        lowerName.contains('college') ||
        lowerName.contains('university') ||
        lowerName.contains('campus') ||
        lowerName.contains('institute')) {
      return 'College / Institute';
    }

    // Landmark / Tourism / Monument / Place of Worship
    if (lowerKey == 'tourism' ||
        lowerVal == 'attraction' ||
        lowerVal == 'monument' ||
        lowerVal == 'museum' ||
        lowerVal == 'place_of_worship' ||
        lowerName.contains('temple') ||
        lowerName.contains('church') ||
        lowerName.contains('mosque') ||
        lowerName.contains('gurudwara') ||
        lowerName.contains('park')) {
      return 'Landmark';
    }

    // Street / Locality
    if (lowerKey == 'highway' ||
        lowerVal == 'residential' ||
        lowerVal == 'suburb' ||
        lowerVal == 'neighbourhood') {
      return 'Street / Area';
    }

    return 'Place';
  }

  /// Searches for places matching [query] using Photon (OSM-based Elasticsearch)
  /// with automatic fallback to OpenStreetMap Nominatim.
  Future<List<GeocodedPlace>> searchPlaces(
    String query, {
    double? biasLatitude,
    double? biasLongitude,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return [];

    // 1. Try Photon by Komoot (optimized for transit & autocomplete search)
    try {
      final photonResults = await _searchWithPhoton(
        cleanQuery,
        biasLat: biasLatitude,
        biasLon: biasLongitude,
      );
      if (photonResults.isNotEmpty) {
        return photonResults;
      }
    } catch (e) {
      debugPrint('[GeocodingService] Photon search notice: $e');
    }

    // 2. Fallback to OpenStreetMap Nominatim
    try {
      final nominatimResults = await _searchWithNominatim(cleanQuery);
      if (nominatimResults.isNotEmpty) {
        return nominatimResults;
      }
    } catch (e) {
      debugPrint('[GeocodingService] Nominatim fallback notice: $e');
    }

    // 3. Offline fallback to local transit station database
    final offlineMatches = LocalStationDatabase.search(cleanQuery);
    if (offlineMatches.isNotEmpty) {
      debugPrint(
        '[GeocodingService] Offline database matched ${offlineMatches.length} stations for "$cleanQuery"',
      );
      return offlineMatches;
    }

    return [];
  }

  /// Primary search using Photon by Komoot (OpenStreetMap data with fast autocomplete).
  Future<List<GeocodedPlace>> _searchWithPhoton(
    String query, {
    double? biasLat,
    double? biasLon,
  }) async {
    final queryParams = <String, String>{
      'q': query,
      'limit': '10',
    };
    if (biasLat != null && biasLon != null) {
      queryParams['lat'] = biasLat.toStringAsFixed(4);
      queryParams['lon'] = biasLon.toStringAsFixed(4);
    }

    final uri = Uri.https('photon.komoot.io', '/api', queryParams);
    final response = await _client.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? [];

    final results = <GeocodedPlace>[];
    for (final feature in features) {
      final featMap = feature as Map<String, dynamic>;
      final geom = featMap['geometry'] as Map<String, dynamic>?;
      final coords = geom?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.length < 2) continue;

      final lon = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();

      final props = featMap['properties'] as Map<String, dynamic>? ?? {};
      final rawName = props['name']?.toString() ?? query;
      final osmKey = props['osm_key']?.toString();
      final osmValue = props['osm_value']?.toString();

      final addressParts = <String>[];
      if (props['street'] != null) addressParts.add(props['street'].toString());
      if (props['district'] != null) addressParts.add(props['district'].toString());
      if (props['city'] != null) addressParts.add(props['city'].toString());
      if (props['state'] != null) addressParts.add(props['state'].toString());
      if (props['country'] != null) addressParts.add(props['country'].toString());

      final fullAddress = addressParts.isNotEmpty
          ? '$rawName, ${addressParts.join(', ')}'
          : rawName;

      final category = categorizePlace(
        osmKey: osmKey,
        osmValue: osmValue,
        name: rawName,
      );

      results.add(
        GeocodedPlace(
          name: rawName,
          address: fullAddress,
          latitude: lat,
          longitude: lon,
          category: category,
          categoryType: osmValue,
        ),
      );
    }

    return results;
  }

  /// Fallback search using official OpenStreetMap Nominatim endpoint.
  Future<List<GeocodedPlace>> _searchWithNominatim(String query) async {
    final elapsed = DateTime.now().difference(_lastNominatimRequestTime);
    if (elapsed.inMilliseconds < 1100) {
      await Future<void>.delayed(
        Duration(milliseconds: 1100 - elapsed.inMilliseconds),
      );
    }
    _lastNominatimRequestTime = DateTime.now();

    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}'
      '&format=json'
      '&limit=10'
      '&addressdetails=1'
      '&extratags=1',
    );

    final response = await _client.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return [];

    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) {
      final map = item as Map<String, dynamic>;
      final lat = double.tryParse(map['lat']?.toString() ?? '0') ?? 0.0;
      final lon = double.tryParse(map['lon']?.toString() ?? '0') ?? 0.0;
      final displayName = map['display_name']?.toString() ?? query;
      final className = map['class']?.toString();
      final typeName = map['type']?.toString();

      final parts = displayName.split(',');
      final shortName = parts.isNotEmpty ? parts.first.trim() : query;

      final category = categorizePlace(
        className: className,
        typeName: typeName,
        name: shortName,
      );

      return GeocodedPlace(
        name: shortName,
        address: displayName,
        latitude: lat,
        longitude: lon,
        category: category,
        categoryType: typeName,
      );
    }).toList();
  }

  /// Looks up a human-readable address for the given coordinates.
  Future<GeocodedPlace?> reverseGeocode(double lat, double lon) async {
    final elapsed = DateTime.now().difference(_lastNominatimRequestTime);
    if (elapsed.inMilliseconds < 1100) {
      await Future<void>.delayed(
        Duration(milliseconds: 1100 - elapsed.inMilliseconds),
      );
    }
    _lastNominatimRequestTime = DateTime.now();

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=json',
      );

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        final displayName = map['display_name']?.toString() ??
            'Location (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})';

        final parts = displayName.split(',');
        final shortName = parts.isNotEmpty ? parts.first.trim() : displayName;

        return GeocodedPlace(
          name: shortName,
          address: displayName,
          latitude: lat,
          longitude: lon,
          category: 'Location',
        );
      }
    } catch (e) {
      debugPrint('[GeocodingService] Reverse geocode error: $e');
    }

    // Graceful offline fallback: check curated station database first
    final nearestStation = LocalStationDatabase.findNearest(lat, lon);
    if (nearestStation != null) {
      return nearestStation;
    }

    return GeocodedPlace(
      name: 'Location (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})',
      address: 'Coordinates: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
      latitude: lat,
      longitude: lon,
      category: 'Coordinates',
    );
  }

  void dispose() {
    _client.close();
  }
}
