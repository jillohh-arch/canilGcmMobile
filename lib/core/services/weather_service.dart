import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherService {
  /// Retorna um Map com 'temperature' e 'humidity' da API Open-Meteo
  Future<Map<String, dynamic>?> getCurrentWeather(
    double latitude,
    double longitude,
  ) async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=temperature_2m,relative_humidity_2m',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['current'] != null) {
          final temp = data['current']['temperature_2m'];
          final hum = data['current']['relative_humidity_2m'];
          return {'temperature': temp, 'humidity': hum};
        }
      }
      return null;
    } catch (e) {
      debugPrint('[WeatherService] Erro ao coletar clima: $e');
      return null;
    }
  }
}
