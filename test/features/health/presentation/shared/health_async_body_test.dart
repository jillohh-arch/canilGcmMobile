import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/health/presentation/shared/states/health_async_body.dart';
import 'package:canil_gcm/features/health/presentation/shared/states/health_presentation_status.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('loading exibe indicador e mensagem', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HealthAsyncBody(
          status: HealthPresentationStatus.loading,
          data: Text('DADOS'),
          loadingMessage: 'Carregando prontuário',
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Carregando prontuário'), findsOneWidget);
    expect(find.text('DADOS'), findsNothing);
  });

  testWidgets('empty não confunde com data', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HealthAsyncBody(
          status: HealthPresentationStatus.empty,
          data: Text('DADOS'),
          emptyTitle: 'Sem registros',
          emptyMessage: 'Nenhum evento clínico.',
        ),
      ),
    );

    expect(find.text('Sem registros'), findsOneWidget);
    expect(find.text('Nenhum evento clínico.'), findsOneWidget);
    expect(find.text('DADOS'), findsNothing);
  });

  testWidgets('error exibe mensagem e retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      wrap(
        HealthAsyncBody(
          status: HealthPresentationStatus.error,
          data: const Text('DADOS'),
          errorMessage: 'Falha de permissão',
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.text('Falha de permissão'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    expect(retries, 1);
    expect(find.text('DADOS'), findsNothing);
  });

  testWidgets('offline tem superfície própria', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HealthAsyncBody(
          status: HealthPresentationStatus.offline,
          data: Text('DADOS'),
        ),
      ),
    );

    expect(find.text('Você está offline'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.text('DADOS'), findsNothing);
  });

  testWidgets('data renderiza conteúdo', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HealthAsyncBody(
          status: HealthPresentationStatus.data,
          data: Text('DADOS'),
        ),
      ),
    );

    expect(find.text('DADOS'), findsOneWidget);
  });

  testWidgets('submitting exibe feedback de save', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HealthAsyncBody(
          status: HealthPresentationStatus.submitting,
          data: Text('DADOS'),
          submittingMessage: 'Gravando registro',
        ),
      ),
    );

    expect(find.text('Gravando registro'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('DADOS'), findsNothing);
  });
}
