part of 'dashboard_screen.dart';

class _BentoDogGrid extends StatelessWidget {
  final List<Dog> dogs;
  final DogViewModel dogVM;

  const _BentoDogGrid({required this.dogs, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FeaturedDogCard(dog: dogs.first, dogVM: dogVM),
        const SizedBox(height: 10),
        if (dogs.length > 1) _DogGridRows(dogs: dogs.sublist(1), dogVM: dogVM),
      ],
    );
  }
}

class _DogGridRows extends StatelessWidget {
  final List<Dog> dogs;
  final DogViewModel dogVM;

  const _DogGridRows({required this.dogs, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < dogs.length; i += 2) {
      final left = dogs[i];
      final right = i + 1 < dogs.length ? dogs[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SmallDogCard(dog: left, dogVM: dogVM),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: right != null
                  ? _SmallDogCard(dog: right, dogVM: dogVM)
                  : const SizedBox(),
            ),
          ],
        ),
      );
      if (i + 2 < dogs.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

void _openDogDetails(BuildContext context, Dog dog) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DogDetailsScreen(dog: dog)),
  );
}
