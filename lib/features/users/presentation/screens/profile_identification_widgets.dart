part of 'profile_screen.dart';

class _ProfileIdentificationSliver extends StatelessWidget {
  final String callsign;
  final String nameStr;
  final String raStr;
  final UserModel? userModel;
  final bool isEditMode;

  const _ProfileIdentificationSliver({
    required this.callsign,
    required this.nameStr,
    required this.raStr,
    required this.userModel,
    required this.isEditMode,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, isEditMode ? 24 : 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileSectionTitle('IDENTIFICAÇÃO'),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.military_tech_rounded,
              label: 'Codinome',
              value: callsign,
            ),
            if (nameStr.isNotEmpty)
              _InfoRow(
                icon: Icons.person_rounded,
                label: 'Nome',
                value: nameStr,
              ),
            _InfoRow(icon: Icons.numbers_rounded, label: 'R.A.', value: raStr),
            if (userModel?.unit.isNotEmpty == true)
              _InfoRow(
                icon: Icons.business_rounded,
                label: 'Unidade',
                value: userModel!.unit,
              ),
            if (userModel?.accessLevel.isNotEmpty == true)
              _InfoRow(
                icon: Icons.security_rounded,
                label: 'Nível',
                value: userModel!.accessLevel,
              ),
          ],
        ),
      ),
    );
  }
}
