import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_start_screen_commands.dart';
part 'occurrence_start_screen_hero.dart';
part 'occurrence_start_screen_nature.dart';

class OccurrenceStartScreen extends StatelessWidget {
  final Color accentColor;
  final Color panelColor;
  final String dogName;
  final String? dogImageUrl;
  final String locationLabel;
  final String timeLabel;
  final String dateLabel;
  final String natureText;
  final bool showNatureEditor;
  final Widget natureEditor;
  final VoidCallback onRefreshLocation;
  final VoidCallback onRefreshTime;
  final VoidCallback onToggleNatureEditor;

  const OccurrenceStartScreen({
    super.key,
    required this.accentColor,
    required this.panelColor,
    required this.dogName,
    required this.dogImageUrl,
    required this.locationLabel,
    required this.timeLabel,
    required this.dateLabel,
    required this.natureText,
    required this.showNatureEditor,
    required this.natureEditor,
    required this.onRefreshLocation,
    required this.onRefreshTime,
    required this.onToggleNatureEditor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _OccurrenceStartHero(
          dogName: dogName,
          dogImageUrl: dogImageUrl,
          accentColor: accentColor,
          panelColor: panelColor,
        ),
        const SizedBox(height: 30),
        _OccurrenceStartCommandGrid(
          panelColor: panelColor,
          locationLabel: locationLabel,
          timeLabel: timeLabel,
          dateLabel: dateLabel,
          onRefreshLocation: onRefreshLocation,
          onRefreshTime: onRefreshTime,
        ),
        const SizedBox(height: 44),
        _OccurrenceStartNatureSection(
          accentColor: accentColor,
          panelColor: panelColor,
          natureText: natureText,
          showNatureEditor: showNatureEditor,
          natureEditor: natureEditor,
          onToggleNatureEditor: onToggleNatureEditor,
        ),
      ],
    );
  }
}
