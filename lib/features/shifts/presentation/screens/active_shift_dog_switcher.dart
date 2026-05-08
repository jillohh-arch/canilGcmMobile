part of 'active_shift_dashboard_screen.dart';

extension _ActiveShiftDogSwitcher on _ActiveShiftDashboardScreenState {
  void _showDogSwitcher(BuildContext context, Dog currentDog) {
    HapticFeedback.heavyImpact();
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (context) {
        return _DogSwitcherSheet(
          dogs: dogVM.dogs,
          currentDog: currentDog,
          onSelected: (dog) async {
            if (dog.id != currentDog.id) {
              await shiftVM.switchDog(dog.id);
            }
          },
        );
      },
    );
  }
}

class _DogSwitcherSheet extends StatelessWidget {
  final List<Dog> dogs;
  final Dog currentDog;
  final Future<void> Function(Dog dog) onSelected;

  const _DogSwitcherSheet({
    required this.dogs,
    required this.currentDog,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TROCA RÁPIDA DE K9',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: _hudCyan,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: dogs.length,
              itemBuilder: (context, index) {
                final dog = dogs[index];
                return _DogSwitcherTile(
                  dog: dog,
                  isSelected: dog.id == currentDog.id,
                  onTap: () async {
                    await onSelected(dog);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DogSwitcherTile extends StatelessWidget {
  final Dog dog;
  final bool isSelected;
  final Future<void> Function() onTap;

  const _DogSwitcherTile({
    required this.dog,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      leading: CircleAvatar(
        backgroundColor: isSelected ? _hudCyan : Colors.white12,
        backgroundImage: dog.profileImageUrl != null
            ? CachedNetworkImageProvider(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? Icon(
                Icons.pets,
                color: isSelected ? Colors.black : Colors.white38,
              )
            : null,
      ),
      title: Text(
        dog.name.toUpperCase(),
        style: GoogleFonts.inter(
          color: isSelected ? _hudCyan : Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        dog.breed,
        style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: _hudCyan)
          : null,
      onTap: onTap,
    );
  }
}
