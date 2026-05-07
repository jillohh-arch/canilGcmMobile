import 'package:flutter/material.dart';

// DashboardViewModel — apenas proxy sem dados mockados.
// Os dados reais vêm de DogViewModel (Firestore stream).
class DashboardViewModel extends ChangeNotifier {
  // Mantido para compatibilidade de injeção no MultiProvider do main.dart
  // Funcionalidades de incidente/treino podem ser expandidas aqui no futuro.
}
