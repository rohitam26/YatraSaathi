import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/offline_map_service.dart';

/// Full-screen interactive map location picker using OpenStreetMap tiles.
///
/// Ordinary users can search by place name, tap to place/move a pin,
/// pan/zoom, or use their current GPS position without knowing coordinates.
class MapLocationPicker extends StatefulWidget {
  const MapLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialPlaceName,
    this.geocodingService,
    this.locationService,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialPlaceName;
  final GeocodingService? geocodingService;
  final LocationService? locationService;

  static Future<GeocodedPlace?> pickLocation(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
    String? initialPlaceName,
    GeocodingService? geocodingService,
    LocationService? locationService,
  }) {
    return Navigator.of(context).push<GeocodedPlace>(
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
          initialLatitude: initialLatitude,
          initialLongitude: initialLongitude,
          initialPlaceName: initialPlaceName,
          geocodingService: geocodingService,
          locationService: locationService,
        ),
      ),
    );
  }

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late final MapController _mapController;
  late final GeocodingService _geocoding;
  late final LocationService _location;

  late LatLng _selectedPosition;
  String _placeName = 'Select a location';
  String _address = 'Tap map to drop pin or search above';
  bool _isLoadingAddress = false;
  bool _isSearching = false;
  List<GeocodedPlace> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _geocoding = widget.geocodingService ?? GeocodingService();
    _location = widget.locationService ?? LocationService();

    final hasInitial = widget.initialLatitude != null && widget.initialLongitude != null;
    final lat = widget.initialLatitude ?? 20.5937;
    final lon = widget.initialLongitude ?? 78.9629;
    _selectedPosition = LatLng(lat, lon);
    if (widget.initialPlaceName != null && widget.initialPlaceName!.isNotEmpty) {
      _placeName = widget.initialPlaceName!;
      _address = hasInitial ? 'Selected stop coordinate' : 'Tap to place pin';
    } else if (!hasInitial) {
      _placeName = 'Locating position...';
      _address = 'Acquiring GPS fix or search above';
    }

    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final reading = await _location.getCurrentReading();
      if (reading != null && mounted) {
        setState(() {
          _userLocation = LatLng(reading.latitude, reading.longitude);
        });
        if (widget.initialLatitude == null) {
          _updateSelectedPosition(
            LatLng(reading.latitude, reading.longitude),
            moveMap: true,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _updateSelectedPosition(LatLng pos, {bool moveMap = false}) async {
    setState(() {
      _selectedPosition = pos;
      _isLoadingAddress = true;
    });

    if (moveMap) {
      _mapController.move(pos, _mapController.camera.zoom);
    }

    final place = await _geocoding.reverseGeocode(pos.latitude, pos.longitude);
    if (mounted) {
      setState(() {
        _isLoadingAddress = false;
        if (place != null) {
          _placeName = place.name;
          _address = place.address;
        } else {
          _placeName = 'Pinned Location';
          _address =
              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        }
      });
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Railway Station':
        return Icons.train_outlined;
      case 'Metro Station':
        return Icons.subway_outlined;
      case 'Bus Terminal':
        return Icons.directions_bus_outlined;
      case 'Hospital / Health':
        return Icons.local_hospital_outlined;
      case 'College / Institute':
        return Icons.school_outlined;
      case 'Landmark':
        return Icons.account_balance_outlined;
      case 'Street / Area':
        return Icons.signpost_outlined;
      default:
        return Icons.place_outlined;
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _isSearching = true);
      final results = await _geocoding.searchPlaces(
        query,
        biasLatitude: _userLocation?.latitude ?? _selectedPosition.latitude,
        biasLongitude: _userLocation?.longitude ?? _selectedPosition.longitude,
      );
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = results;
        });
      }
    });
  }

  void _selectSearchResult(GeocodedPlace place) {
    FocusScope.of(context).unfocus();
    final pos = LatLng(place.latitude, place.longitude);
    setState(() {
      _selectedPosition = pos;
      _placeName = place.name;
      _address = place.address;
      _searchResults = [];
      _searchController.clear();
    });
    _mapController.move(pos, 15.5);
  }

  Future<void> _showManualCoordinateDialog() async {
    final latController = TextEditingController(
      text: _selectedPosition.latitude.toStringAsFixed(5),
    );
    final lonController = TextEditingController(
      text: _selectedPosition.longitude.toStringAsFixed(5),
    );
    final nameController = TextEditingController(text: _placeName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Coordinates (Offline Fallback)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Place Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: latController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Latitude (-90 to +90)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lonController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Longitude (-180 to +180)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final lat = double.tryParse(latController.text.trim());
      final lon = double.tryParse(lonController.text.trim());
      if (lat != null && lon != null && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
        final pos = LatLng(lat, lon);
        setState(() {
          _selectedPosition = pos;
          if (nameController.text.trim().isNotEmpty) {
            _placeName = nameController.text.trim();
          }
          _address = 'Manual coordinates: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
        });
        _mapController.move(pos, 15.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Location on Map'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop(
                GeocodedPlace(
                  name: _placeName,
                  address: _address,
                  latitude: _selectedPosition.latitude,
                  longitude: _selectedPosition.longitude,
                ),
              );
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirm'),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Interactive Flutter Map with OpenStreetMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPosition,
              initialZoom: 14.5,
              onTap: (tapPosition, point) {
                _updateSelectedPosition(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                tileProvider: PersistentOfflineTileProvider(),
                userAgentPackageName: 'com.example.pathsaathi',
                maxZoom: 19,
              ),
              SimpleAttributionWidget(
                source: const Text('© OpenStreetMap contributors'),
                alignment: Alignment.bottomLeft,
              ),
              // Markers
              MarkerLayer(
                markers: [
                  // User's current location marker (if available)
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(200),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Pinned target location marker
                  Marker(
                    point: _selectedPosition,
                    width: 50,
                    height: 50,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.redAccent,
                      size: 46,
                      shadows: [
                        Shadow(
                          color: Colors.black38,
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Search Bar at Top
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search station, landmark, or address...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              },
                            )
                          : (_isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                // Search Results Dropdown List
                if (_searchResults.isNotEmpty)
                  Card(
                    elevation: 6,
                    margin: const EdgeInsets.only(top: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final place = _searchResults[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(
                                _getCategoryIcon(place.category),
                                size: 18,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    place.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (place.category != 'Place')
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      place.category,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              place.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSearchResult(place),
                          );
                        },
                      ),
                    ),
                  )
                else if (_searchController.text.trim().length >= 2 && !_isSearching)
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(top: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No matching places found. Tap anywhere on the map to place a pin, or enter coordinates.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: _showManualCoordinateDialog,
                            child: const Text('Manual Coords'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Offline Cache Active Badge
          Positioned(
            top: 74,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(175),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24, width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.offline_pin, size: 12, color: Colors.tealAccent),
                  SizedBox(width: 4),
                  Text(
                    'Offline Cache Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Zoom and "My Location" Action Controls
          Positioned(
            right: 14,
            bottom: 160,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'map_zoom_in',
                  backgroundColor: colorScheme.surface,
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    );
                  },
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_zoom_out',
                  backgroundColor: colorScheme.surface,
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    );
                  },
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_my_location',
                  backgroundColor: colorScheme.surface,
                  onPressed: () async {
                    if (_userLocation != null) {
                      _updateSelectedPosition(_userLocation!, moveMap: true);
                    } else {
                      await _fetchCurrentLocation();
                    }
                  },
                  tooltip: 'My Location',
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map_manual_coords',
                  backgroundColor: colorScheme.surface,
                  onPressed: _showManualCoordinateDialog,
                  tooltip: 'Manual Coordinates',
                  child: const Icon(Icons.edit_location_alt_outlined),
                ),
              ],
            ),
          ),

          // 4. Bottom Selected Location Confirmation Card
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pin_drop, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _placeName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isLoadingAddress)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _address,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          GeocodedPlace(
                            name: _placeName,
                            address: _address,
                            latitude: _selectedPosition.latitude,
                            longitude: _selectedPosition.longitude,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Use This Location'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

