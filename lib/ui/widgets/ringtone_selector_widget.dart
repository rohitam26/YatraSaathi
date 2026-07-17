import 'package:flutter/material.dart';
import '../../services/alarm_service.dart';

/// Reusable interactive widget for choosing an arrival ringtone,
/// auditioning immediate audio previews, and adjusting preview volume.
class RingtoneSelectorWidget extends StatefulWidget {
  const RingtoneSelectorWidget({
    super.key,
    required this.selectedSound,
    required this.onSoundSelected,
    required this.alarmService,
    this.initialVolume = 1.0,
    this.onVolumeChanged,
    this.showVolumeSlider = true,
  });

  final String selectedSound;
  final ValueChanged<String> onSoundSelected;
  final AlarmService alarmService;
  final double initialVolume;
  final ValueChanged<double>? onVolumeChanged;
  final bool showVolumeSlider;

  @override
  State<RingtoneSelectorWidget> createState() => _RingtoneSelectorWidgetState();
}

class _RingtoneSelectorWidgetState extends State<RingtoneSelectorWidget> {
  late double _volume;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume.clamp(0.0, 1.0);
    widget.alarmService.addListener(_onAlarmServiceChanged);
  }

  @override
  void didUpdateWidget(covariant RingtoneSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alarmService != widget.alarmService) {
      oldWidget.alarmService.removeListener(_onAlarmServiceChanged);
      widget.alarmService.addListener(_onAlarmServiceChanged);
    }
  }

  @override
  void dispose() {
    widget.alarmService.removeListener(_onAlarmServiceChanged);
    // Automatically halt preview when navigating away
    widget.alarmService.stopPreview();
    super.dispose();
  }

  void _onAlarmServiceChanged() {
    if (mounted) setState(() {});
  }

  void _handleSoundTapped(String soundName) {
    widget.onSoundSelected(soundName);
    // Tapping sound immediately plays audio preview
    widget.alarmService.startPreview(soundName, volume: _volume);
  }

  void _handlePlayPauseToggle(String soundName) {
    if (widget.alarmService.currentPreviewSound == soundName) {
      widget.alarmService.stopPreview();
    } else {
      widget.onSoundSelected(soundName);
      widget.alarmService.startPreview(soundName, volume: _volume);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentPreview = widget.alarmService.currentPreviewSound;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showVolumeSlider) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Icon(
                  _volume == 0
                      ? Icons.volume_off
                      : (_volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Preview Volume: ${(_volume * 100).toInt()}%',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: '${(_volume * 100).toInt()}%',
                    onChanged: (val) {
                      setState(() => _volume = val);
                      widget.alarmService.setPreviewVolume(val);
                      widget.onVolumeChanged?.call(val);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],

        // Ringtones List
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(120)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: RadioGroup<String>(
              groupValue: widget.selectedSound,
              onChanged: (v) {
                if (v != null) _handleSoundTapped(v);
              },
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: AlarmService.availableSounds.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final sound = AlarmService.availableSounds[index];
                  final isSelected = widget.selectedSound == sound;
                  final isPreviewing = currentPreview == sound;
                  final desc = AlarmService.soundDescriptions[sound] ?? sound;

                  return InkWell(
                    onTap: () => _handleSoundTapped(sound),
                    child: Container(
                      color: isSelected ? colorScheme.primaryContainer.withAlpha(60) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          // Radio indicator
                          Radio<String>(
                            value: sound,
                            visualDensity: VisualDensity.compact,
                          ),

                        // Title & description
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sound,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? colorScheme.primary : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                desc,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Play / Pause preview control
                        IconButton(
                          icon: Icon(
                            isPreviewing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_outline,
                            color: isPreviewing ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            size: 28,
                          ),
                          tooltip: isPreviewing ? 'Stop Preview' : 'Play Preview',
                          onPressed: () => _handlePlayPauseToggle(sound),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ],
  );
  }
}
