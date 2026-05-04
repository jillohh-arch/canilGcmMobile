import 'package:flutter/material.dart';

class LocationTimeRow extends StatelessWidget {
  final Widget locationField;
  final Widget timeField;

  const LocationTimeRow({
    super.key,
    required this.locationField,
    required this.timeField,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 3, child: locationField),
        const SizedBox(width: 12),
        Expanded(flex: 1, child: timeField),
      ],
    );
  }
}
