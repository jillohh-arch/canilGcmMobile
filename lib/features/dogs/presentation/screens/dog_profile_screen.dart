import 'package:flutter/material.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/profiles/presentation/screens/k9_profile_page.dart';

class DogProfileScreen extends StatelessWidget {
  final Dog dog;

  const DogProfileScreen({super.key, required this.dog});

  @override
  Widget build(BuildContext context) {
    return K9ProfilePage(dog: dog, showBottomNav: true);
  }
}
