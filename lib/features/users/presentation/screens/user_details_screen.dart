import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';

class UserDetailsScreen extends StatelessWidget {
  final UserModel user;
  const UserDetailsScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = user.accessLevel == 'Admin';
    final gradient = isAdmin
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF37474F), Color(0xFF263238)],
          );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(decoration: BoxDecoration(gradient: gradient)),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: Colors.white24,
                          backgroundImage: user.photoUrl != null
                              ? NetworkImage(user.photoUrl!)
                              : null,
                          child: user.photoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 56,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Text(
                  user.callsign.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                if (user.name.isNotEmpty)
                  Text(
                    user.name,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                Text(
                  isAdmin ? 'ADMINISTRADOR' : 'CONDUTOR',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 32),

                // Stats
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CompactStat(value: user.ra, label: 'RA'),
                      if (user.name.isNotEmpty)
                        _CompactStat(value: user.name, label: 'Nome'),
                      _CompactStat(
                        value: user.unit.isEmpty ? '--' : user.unit,
                        label: 'Unidade',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Linked Dogs
                _LinkedDogsSection(userRa: user.ra),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  final String value;
  final String label;
  const _CompactStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}

class _LinkedDogsSection extends StatelessWidget {
  final String userRa;
  const _LinkedDogsSection({required this.userRa});

  @override
  Widget build(BuildContext context) {
    final dogVM = Provider.of<DogViewModel>(context);
    final linkedDogs = dogVM.dogs
        .where((d) => d.conductorRa == userRa)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'K9s VINCULADOS',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 16),
          if (linkedDogs.isEmpty)
            Text(
              'Nenhum K9 vinculado a este condutor.',
              style: TextStyle(color: Colors.grey[600]),
            )
          else
            ...linkedDogs.map(
              (dog) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: dog.profileImageUrl != null
                      ? NetworkImage(dog.profileImageUrl!)
                      : null,
                  child: dog.profileImageUrl == null
                      ? const FaIcon(FontAwesomeIcons.dog, size: 20)
                      : null,
                ),
                title: Text(
                  dog.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(dog.breed),
              ),
            ),
        ],
      ),
    );
  }
}
