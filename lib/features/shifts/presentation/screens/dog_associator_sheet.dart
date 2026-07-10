import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

/// Bottom sheet para selecionar e embarcar um cão na guarnição.
///
/// Fluxo:
/// 1. Exibe lista de cães operacionais LIVRES (não embarcados).
/// 2. Se o cão tem titular diferente de quem embarca, mostra confirmação.
/// 3. Ao confirmar, associa o cão ao member e ao doc pai.
Future<void> showDogAssociatorSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DogAssociatorSheet(),
  );
}

class _DogAssociatorSheet extends StatefulWidget {
  const _DogAssociatorSheet();

  @override
  State<_DogAssociatorSheet> createState() => _DogAssociatorSheetState();
}

class _DogAssociatorSheetState extends State<_DogAssociatorSheet> {
  late Future<Set<String>> _dogsInUseFuture;

  @override
  void initState() {
    super.initState();
    _dogsInUseFuture = _fetchDogsInUse();
  }

  /// Busca todos os dog IDs atualmente embarcados em guarnições ativas.
  Future<Set<String>> _fetchDogsInUse() async {
    // Buscar crews ativas com service_dog_id definido
    final crewsSnap = await FirebaseFirestore.instance
        .collection('vehicle_crews')
        .where('active', isEqualTo: true)
        .get();

    final inUse = <String>{};
    for (final doc in crewsSnap.docs) {
      final dogId = doc.data()['service_dog_id']?.toString().trim();
      if (dogId != null && dogId.isNotEmpty) {
        inUse.add(dogId);
      }
    }
    return inUse;
  }

  @override
  Widget build(BuildContext context) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final currentHandlerId = shiftVM.handlerId ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withAlpha(60)),
                      ),
                      child: const Icon(
                        Icons.pets_rounded,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EMBARCAR K9',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'Selecione um cão operacional livre',
                            style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: AppTheme.textTertiary,
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.outlineVariant, height: 1),
              // Lista de cães
              Expanded(
                child: FutureBuilder<Set<String>>(
                  future: _dogsInUseFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      );
                    }

                    final dogsInUse = snapshot.data ?? const <String>{};

                    // Filtro: status='Ativo' + não está em uso
                    final availableDogs = dogVM.dogs.where((d) {
                      if (d.status != 'Ativo') return false;
                      if (dogsInUse.contains(d.id)) return false;
                      return true;
                    }).toList();

                    if (availableDogs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.pets_rounded,
                                size: 48,
                                color: AppTheme.textTertiary.withAlpha(100),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum cão operacional livre',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Todos os cães estão embarcados ou inativos',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textTertiary,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: availableDogs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final dog = availableDogs[index];
                        return _DogCard(
                          dog: dog,
                          currentHandlerId: currentHandlerId,
                          onTap: () => _onDogSelected(context, dog, currentHandlerId, userVM),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onDogSelected(
    BuildContext context,
    Dog dog,
    String currentHandlerId,
    UserViewModel userVM,
  ) async {
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);

    // Verificar titularidade
    final ownership = await shiftVM.checkDogOwnership(dog.id);

    if (!context.mounted) return;

    if (ownership.hasTitular && !ownership.isTitular) {
      // Mostrar confirmação com aviso
      final confirmed = await _showOwnershipConfirmation(
        context,
        dog: dog,
        titularName: ownership.titularName ?? ownership.titularRa ?? 'desconhecido',
      );

      if (confirmed != true) return;
    }

    if (!context.mounted) return;

    // Associar o cão
    await shiftVM.associateDog(dog.id);

    if (!context.mounted) return;

    if (shiftVM.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shiftVM.error!),
          backgroundColor: AppTheme.error,
        ),
      );
    } else {
      Navigator.pop(context); // Fecha o sheet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${dog.name} embarcado na guarnição!'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<bool?> _showOwnershipConfirmation(
    BuildContext context, {
    required Dog dog,
    required String titularName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Embarcar cão de outro titular?',
          style: GoogleFonts.inter(
            color: AppTheme.warning,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${dog.name} é titular de $titularName.',
              style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Deseja embarcar mesmo assim?',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Embarcar',
              style: GoogleFonts.inter(
                color: AppTheme.warning,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de cão na lista de seleção.
class _DogCard extends StatelessWidget {
  final Dog dog;
  final String currentHandlerId;
  final VoidCallback onTap;

  const _DogCard({
    required this.dog,
    required this.currentHandlerId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.outlineVariant),
        ),
        child: Row(
          children: [
            // Ícone do cão
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withAlpha(50)),
              ),
              child: const Icon(
                Icons.pets_rounded,
                color: AppTheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // Info do cão
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dog.name,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withAlpha(15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.success.withAlpha(60)),
                        ),
                        child: Text(
                          'OPERACIONAL',
                          style: GoogleFonts.robotoMono(
                            color: AppTheme.success,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (dog.breed.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          dog.breed,
                          style: GoogleFonts.inter(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Botão
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withAlpha(60)),
              ),
              child: Text(
                'EMBARCAR',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
