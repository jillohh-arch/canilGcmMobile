import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/features/health/presentation/shared/widgets/health_date_time_field.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_field_label.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('exibe valor formatado e label', (tester) async {
    final value = DateTime(2026, 7, 15);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthDateTimeField(
            label: 'Data do evento',
            value: value,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(HealthFieldLabel), findsOneWidget);
    expect(find.text('DATA DO EVENTO'), findsOneWidget);
    expect(find.text(DateFormat('dd/MM/yyyy').format(value)), findsOneWidget);
  });

  testWidgets('sem valor mostra hint e não cria controller em build', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthDateTimeField(
            label: 'Próxima dose',
            value: null,
            hintText: 'Informe a data',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Informe a data'), findsOneWidget);
    // Campo é decorativo (InputDecorator), sem TextEditingController.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });
}
