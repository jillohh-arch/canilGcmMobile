import 'package:flutter/material.dart';

import 'package:canil_gcm/features/profiles/presentation/screens/handler_profile_page.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const HandlerProfilePage(showBottomNav: true);
  }
}
