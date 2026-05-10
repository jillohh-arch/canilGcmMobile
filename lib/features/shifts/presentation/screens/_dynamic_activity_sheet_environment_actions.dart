part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetEnvironmentActions
    on _DynamicActivitySheetState {
  Future<void> _fetchCurrentAddress() async {
    try {
      HapticFeedback.lightImpact();
      final location = await const LocationResolutionService()
          .currentHighAccuracy();
      _updateState(() {
        _locationController.text = location.address;
        _occCtrl.selectedLocationLatLng = location.point;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao obter endereço: $e')));
      }
    }
  }

  Future<void> _selectOccurrenceLocation(LatLng point) async {
    _updateState(() => _occCtrl.selectedLocationLatLng = point);
    final address = await const LocationResolutionService().addressForPoint(
      point,
    );
    if (address.isNotEmpty) {
      _updateState(() => _locationController.text = address);
    }
  }

  void _setTimeToNow() {
    _updateState(() {
      _timeController.text = _formatTimeOfDay(DateTime.now());
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pullCurrentWeather() async {
    try {
      HapticFeedback.lightImpact();
      final weather = await const WeatherCaptureService().currentWeather();
      if (weather != null) {
        _updateState(() {
          _tempController.text = weather.temperature.toString();
          _humidityController.text = weather.humidity.toString();
          if (_condicaoTerrenoController.text.isEmpty) {
            _condicaoTerrenoController.text = weather.terrainSummary;
          }
        });
        HapticFeedback.mediumImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clima atualizado com sucesso!'),
              backgroundColor: Color(0xFF1B8A4C),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao coletar clima: $e')));
      }
    }
  }

  DateTime _resolveFormTimestamp() {
    final baseTimestamp = widget.initialData?['_rawDate'] ?? DateTime.now();
    return const PtBrDateTimeService().withTimeText(
      base: baseTimestamp,
      timeText: _timeController.text,
    );
  }
}
