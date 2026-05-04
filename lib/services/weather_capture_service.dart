import 'package:geolocator/geolocator.dart';

import 'weather_service.dart';

class CapturedWeather {
  final dynamic temperature;
  final dynamic humidity;

  const CapturedWeather({required this.temperature, required this.humidity});

  String get terrainSummary =>
      'Temp média: $temperature°C / Umidade: $humidity%';
}

class WeatherCaptureService {
  const WeatherCaptureService();

  Future<CapturedWeather?> currentWeather() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    final weather = await WeatherService().getCurrentWeather(
      position.latitude,
      position.longitude,
    );
    if (weather == null) return null;

    return CapturedWeather(
      temperature: weather['temperature'],
      humidity: weather['humidity'],
    );
  }
}
