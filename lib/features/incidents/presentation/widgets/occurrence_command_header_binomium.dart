part of 'occurrence_command_header.dart';

class _BinomiumBlock extends StatelessWidget {
  final String dogName;
  final String? dogImageUrl;
  final Color dogAccent;
  final String operatorName;
  final String? operatorImageUrl;
  final Color operatorAccent;

  const _BinomiumBlock({
    required this.dogName,
    required this.dogImageUrl,
    required this.dogAccent,
    required this.operatorName,
    required this.operatorImageUrl,
    required this.operatorAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AvatarPair(
          dogImageUrl: dogImageUrl,
          dogAccent: dogAccent,
          operatorImageUrl: operatorImageUrl,
          operatorAccent: operatorAccent,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _NameLabel(
                name: dogName.isNotEmpty ? dogName : 'K9',
                label: 'K9',
                accent: dogAccent,
              ),
            ),
            const SizedBox(width: 18),
            Flexible(
              child: _NameLabel(
                name: operatorName.isNotEmpty ? operatorName : 'Condutor',
                label: 'GCM',
                accent: operatorAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
