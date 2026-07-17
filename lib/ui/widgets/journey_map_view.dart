import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/stop.dart';

/// Interactive map view rendering a complete multi-stop journey route.
///
/// Displays numbered markers, geofence radius circles, transit connection lines,
/// and the user's real-time position.
class JourneyMapView extends StatefulWidget {
  const JourneyMapView({
    super.key,
    required this.stops,
    this.activeStop,
    this.userPosition,
    this.height = 240,
    this.isInteractive = true,
    this.onStopTapped,
  });

  final List<Stop> stops;
  final Stop? activeStop;
  final LatLng? userPosition;
  final double height;
  final bool isInteractive;
  final ValueChanged<Stop>? onStopTapped;

  @override
  State<JourneyMapView> createState() => _JourneyMapViewState();
}

class _JourneyMapViewState extends State<JourneyMapView> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  LatLng _computeInitialCenter() {
    if (widget.userPosition != null) {
      return widget.userPosition!;
    }
    if (widget.activeStop != null) {
      return LatLng(
        widget.activeStop!.latitude,
        widget.activeStop!.longitude,
      );
    }
    if (widget.stops.isNotEmpty) {
      return LatLng(
        widget.stops.first.latitude,
        widget.stops.first.longitude,
      );
    }
    return const LatLng(13.0827, 80.2707); // Default fallback
  }

  void _fitBounds() {
    if (widget.stops.isEmpty) return;

    final points = widget.stops
        .map((s) => LatLng(s.latitude, s.longitude))
        .toList();

    if (widget.userPosition != null) {
      points.add(widget.userPosition!);
    }

    if (points.length == 1) {
      _mapController.move(points.first, 14.5);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(36.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initialCenter = _computeInitialCenter();

    final stopPoints = widget.stops
        .map((s) => LatLng(s.latitude, s.longitude))
        .toList();

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: widget.stops.length > 1 ? 12.0 : 14.0,
                interactionOptions: InteractionOptions(
                  flags: widget.isInteractive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.pathsaathi',
                  maxZoom: 19,
                ),
                SimpleAttributionWidget(
                  source: const Text('© OpenStreetMap contributors'),
                  alignment: Alignment.bottomLeft,
                ),

                // 1. Geofence arrival radius circles around stops
                CircleLayer(
                  circles: widget.stops.map((stop) {
                    final isActive = widget.activeStop?.id == stop.id;
                    final isReached = stop.isReached;
                    return CircleMarker(
                      point: LatLng(stop.latitude, stop.longitude),
                      radius: stop.radiusMeters,
                      useRadiusInMeter: true,
                      color: isReached
                          ? Colors.grey.withAlpha(30)
                          : (isActive
                              ? Colors.green.withAlpha(50)
                              : colorScheme.primary.withAlpha(35)),
                      borderColor: isReached
                          ? Colors.grey
                          : (isActive ? Colors.green : colorScheme.primary),
                      borderStrokeWidth: isActive ? 2.0 : 1.0,
                    );
                  }).toList(),
                ),

                // 2. Direct route polyline connecting sequence of stops
                if (stopPoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: stopPoints,
                        color: colorScheme.primary.withAlpha(180),
                        strokeWidth: 3.5,
                        pattern: StrokePattern.dashed(segments: const [8, 4]),
                      ),
                    ],
                  ),

                // 3. Numbered Stop Markers
                MarkerLayer(
                  markers: [
                    // Stop markers
                    for (int i = 0; i < widget.stops.length; i++) ...[
                      Marker(
                        point: LatLng(
                          widget.stops[i].latitude,
                          widget.stops[i].longitude,
                        ),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => widget.onStopTapped?.call(widget.stops[i]),
                          child: _buildStopBadge(
                            context,
                            widget.stops[i],
                            i + 1,
                            isActive: widget.activeStop?.id == widget.stops[i].id,
                            isFinal: i == widget.stops.length - 1 &&
                                widget.stops.length > 1,
                          ),
                        ),
                      ),
                    ],

                    // Real-time user position marker (if provided)
                    if (widget.userPosition != null)
                      Marker(
                        point: widget.userPosition!,
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3.0),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Fit All Stops Button overlay
            if (widget.isInteractive && widget.stops.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: FloatingActionButton.small(
                  heroTag: 'journey_fit_bounds_${widget.key}',
                  backgroundColor: colorScheme.surface.withAlpha(220),
                  onPressed: _fitBounds,
                  tooltip: 'Fit All Stops on Screen',
                  child: const Icon(Icons.crop_free, size: 20),
                ),
              ),

            // Route disclaimer banner at bottom left
            Positioned(
              bottom: 6,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(120),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '© OpenStreetMap contributors • Direct Path',
                  style: TextStyle(color: Colors.white70, fontSize: 9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopBadge(
    BuildContext context,
    Stop stop,
    int index, {
    required bool isActive,
    required bool isFinal,
  }) {
    Color bg;
    if (stop.isReached) {
      bg = Colors.grey.shade600;
    } else if (isActive) {
      bg = Colors.green.shade600;
    } else if (isFinal) {
      bg = Colors.deepOrange.shade600;
    } else {
      bg = Theme.of(context).colorScheme.primary;
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? Colors.white : Colors.white70,
          width: isActive ? 2.5 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: isFinal && !stop.isReached
            ? const Icon(Icons.flag, color: Colors.white, size: 16)
            : Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
      ),
    );
  }
}

