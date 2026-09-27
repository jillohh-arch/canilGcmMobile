import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/conditioning/domain/conditioning_session.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/history/presentation/widgets/gps_track_detail_widget.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpScreen(WidgetTester tester, HistoryEntry entry) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: RegistroDetalhePage(entry: entry),
      ),
    );
    await tester.pump();
  }

  void assertStrictAbsenceOfObedienceCommands() {
    // Assert strictly that NO obedience commands are rendered anywhere
    expect(find.text('Senta', findRichText: true), findsNothing);
    expect(find.text('Deita', findRichText: true), findsNothing);
    expect(find.text('Fica', findRichText: true), findsNothing);
    expect(find.text('Vem', findRichText: true), findsNothing);
    expect(find.text('Junto', findRichText: true), findsNothing);
    expect(
      find.textContaining('Vem (chamada)', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Latir sob comando', findRichText: true),
      findsNothing,
    );
    expect(find.text('COMANDOS · ESTÁGIO'), findsNothing);
    expect(find.text('OPERACIONAIS'), findsNothing);
    expect(find.text('POSICIONAIS'), findsNothing);
  }

  group('CT3.F50.PILOT-BATCH01-TRAINING-HISTORY-FIX-R1 — Condicionamento Físico', () {
    testWidgets(
      'renders conditioning session with Passeio, cardio metrics, gps track, notes and NO obedience commands',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'cond_sess_1',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 9, 30),
          trainingType: 'Condicionamento',
          location: 'Parque Ecológico',
          weather: 'Ensolarado',
          handlerNotes: 'Cão demonstrou excelente resistência aeróbica.',
          metadata: {
            'specialty': 'condicionamento',
            'exercise': 'Passeio',
            'intensity': 'Moderada',
            'condition': 'Normal',
            'duration': '35',
            'distance': '3.5',
            'gps': true,
            'gps_track': {
              'points': [
                {'lat': -23.5505, 'lng': -46.6333, 'time': '2026-09-27T09:30:00Z'},
                {'lat': -23.5515, 'lng': -46.6343, 'time': '2026-09-27T10:05:00Z'},
              ],
              'distanceMeters': 3500.0,
              'durationSeconds': 2100,
            },
          },
        );

        final entry = HistoryEntry(
          id: 'entry_cond_1',
          type: HistoryEntryType.training,
          title: 'Treino • Condicionamento',
          subtitle: 'Parque Ecológico',
          time: DateTime(2026, 9, 27, 9, 30),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Condicionamento',
            'Local': 'Parque Ecológico',
            'Duração': '35 min',
            'exercise': 'Passeio',
            'intensity': 'Moderada',
            'condition': 'Normal',
            'duration': '35',
            'distance': '3.5',
            'gps_track': session.metadata!['gps_track'],
          },
        );

        await pumpScreen(tester, entry);

        // Body must be HistoryCondicionamentoBody
        expect(find.byType(HistoryCondicionamentoBody), findsOneWidget);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        // Exercise summary
        expect(find.text('Passeio'), findsWidgets);
        expect(find.text('CARDIOVASCULAR'), findsOneWidget);
        expect(find.text('MODERADA'), findsWidgets);
        expect(find.text('NORMAL'), findsWidgets);

        // Metrics
        expect(find.text('35 min'), findsWidgets);
        expect(find.text('3.5 km'), findsOneWidget);
        expect(find.text('DURAÇÃO'), findsWidgets);
        expect(find.text('DISTÂNCIA'), findsWidgets);

        // GPS Track detail widget must be present
        expect(find.byType(GpsTrackDetailWidget), findsOneWidget);

        // Notes
        expect(
          find.text('Cão demonstrou excelente resistência aeróbica.'),
          findsOneWidget,
        );

        // STRICT ABSENCE OF OBEDIENCE COMMANDS
        assertStrictAbsenceOfObedienceCommands();
      },
    );

    testWidgets(
      'renders conditioning session for Esteira (Cardio) with sets, speed, duration',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'cond_sess_2',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 10, 0),
          trainingType: 'Condicionamento',
          location: 'Canil Central',
          weather: '',
          handlerNotes: 'Treino de velocidade em esteira mecânica.',
          metadata: {
            'specialty': 'condicionamento',
            'exercise': 'Esteira',
            'intensity': 'Intensa',
            'condition': 'Ofegante',
            'sets': '3',
            'duration': '15',
            'speed': '12',
          },
        );

        final entry = HistoryEntry(
          id: 'entry_cond_2',
          type: HistoryEntryType.training,
          title: 'Treino • Condicionamento',
          subtitle: 'Canil Central',
          time: DateTime(2026, 9, 27, 10, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Condicionamento',
            'exercise': 'Esteira',
            'intensity': 'Intensa',
            'condition': 'Ofegante',
            'sets': '3',
            'duration': '15',
            'speed': '12',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryCondicionamentoBody), findsOneWidget);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('Esteira'), findsWidgets);
        expect(find.text('CARDIOVASCULAR'), findsOneWidget);
        expect(find.text('INTENSA'), findsWidgets);
        expect(find.text('OFEGANTE'), findsWidgets);

        // Metrics
        expect(find.text('3 x'), findsOneWidget);
        expect(find.text('SÉRIES'), findsOneWidget);
        expect(find.text('15 min'), findsWidgets);
        expect(find.text('12 km/h'), findsOneWidget);
        expect(find.text('VELOCIDADE'), findsOneWidget);

        assertStrictAbsenceOfObedienceCommands();
      },
    );

    testWidgets(
      'renders conditioning session for Tração c/ peso (Força) with load, reps',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'cond_sess_3',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 11, 0),
          trainingType: 'Condicionamento',
          location: 'Campo de Treinamento',
          weather: '',
          handlerNotes: 'Desenvolvimento de força e tração com colete de peso.',
          metadata: {
            'specialty': 'condicionamento',
            'exercise': 'Tração c/ peso',
            'intensity': 'Intensa',
            'condition': 'Exausto',
            'load': '12',
            'reps': '8',
            'duration': '20',
          },
        );

        final entry = HistoryEntry(
          id: 'entry_cond_3',
          type: HistoryEntryType.training,
          title: 'Treino • Condicionamento',
          subtitle: 'Campo de Treinamento',
          time: DateTime(2026, 9, 27, 11, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Condicionamento',
            'exercise': 'Tração c/ peso',
            'intensity': 'Intensa',
            'condition': 'Exausto',
            'load': '12',
            'reps': '8',
            'duration': '20',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryCondicionamentoBody), findsOneWidget);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('Tração c/ peso'), findsWidgets);
        expect(find.text('FORÇA'), findsOneWidget);
        expect(find.text('INTENSA'), findsWidgets);
        expect(find.text('EXAUSTO'), findsWidgets);

        // Metrics
        expect(find.text('12 kg'), findsOneWidget);
        expect(find.text('CARGA'), findsOneWidget);
        expect(find.text('8 x'), findsOneWidget);
        expect(find.text('REPETIÇÕES'), findsOneWidget);
        expect(find.text('20 min'), findsWidgets);

        assertStrictAbsenceOfObedienceCommands();
      },
    );

    testWidgets(
      'renders conditioning session for Cavaletes (Agilidade) with height, reps',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'cond_sess_4',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 14, 0),
          trainingType: 'Condicionamento',
          location: 'Pista de Agilidade',
          weather: '',
          handlerNotes: 'Propriocepção e coordenação motora nos cavaletes.',
          metadata: {
            'specialty': 'condicionamento',
            'exercise': 'Cavaletes',
            'intensity': 'Leve',
            'condition': 'Normal',
            'height': '25',
            'reps': '10',
          },
        );

        final entry = HistoryEntry(
          id: 'entry_cond_4',
          type: HistoryEntryType.training,
          title: 'Treino • Condicionamento',
          subtitle: 'Pista de Agilidade',
          time: DateTime(2026, 9, 27, 14, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Condicionamento',
            'exercise': 'Cavaletes',
            'intensity': 'Leve',
            'condition': 'Normal',
            'height': '25',
            'reps': '10',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryCondicionamentoBody), findsOneWidget);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('Cavaletes'), findsWidgets);
        expect(find.text('AGILIDADE E PLIOMETRIA'), findsOneWidget);
        expect(find.text('LEVE'), findsWidgets);
        expect(find.text('NORMAL'), findsWidgets);

        expect(find.text('25 cm'), findsOneWidget);
        expect(find.text('ALTURA'), findsOneWidget);
        expect(find.text('10 x'), findsOneWidget);
        expect(find.text('REPETIÇÕES'), findsOneWidget);

        assertStrictAbsenceOfObedienceCommands();
      },
    );

    testWidgets(
      'renders conditioning session from ConditioningSession domain model',
      (tester) async {
        final condModel = ConditioningSession(
          id: 'cond_session_domain_1',
          exerciseType: 'natacao',
          exerciseNameCustom: 'Natação Terapêutica',
          intensity: 'leve',
          postCondition: 'normal',
          observations: 'Trabalho de baixo impacto para articulações.',
          performedAt: DateTime(2026, 9, 27, 15, 0),
          performedBy: 'GCM Silva',
          metrics: {
            'duration_minutes': 25,
          },
        );

        final entry = HistoryEntry(
          id: 'entry_cond_domain',
          type: HistoryEntryType.training,
          title: 'Treino • Condicionamento',
          subtitle: 'Piscina Canil',
          time: DateTime(2026, 9, 27, 15, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: condModel,
          details: {
            'Tipo': 'Condicionamento',
            'exercise': 'Natação Terapêutica',
            'intensity': 'leve',
            'condition': 'normal',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryCondicionamentoBody), findsOneWidget);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('Natação Terapêutica'), findsWidgets);
        expect(find.text('CARDIOVASCULAR'), findsOneWidget);
        expect(find.text('LEVE'), findsWidgets);
        expect(find.text('NORMAL'), findsWidgets);
        expect(find.text('25 min'), findsWidgets);
        expect(
          find.text('Trabalho de baixo impacto para articulações.'),
          findsOneWidget,
        );

        assertStrictAbsenceOfObedienceCommands();
      },
    );

    testWidgets(
      'legacy conditioning record compatibility (no originalModel, metadata in details map)',
      (tester) async {
        final entry = HistoryEntry(
          id: 'entry_legacy_cond',
          type: HistoryEntryType.training,
          title: 'Treino • Condicionamento',
          subtitle: 'Área externa',
          time: DateTime(2026, 9, 27, 16, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: null, // Legacy record without original model instance
          details: {
            'Tipo': 'Condicionamento',
            'specialty': 'condicionamento',
            'exercise': 'Bolinha em campo',
            'intensity': 'Moderada',
            'condition': 'Ofegante',
            'reps': '15',
            'diagonal': '40',
            'duration': '20',
            'Notas': 'Ótima resposta de explosão física.',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryCondicionamentoBody), findsOneWidget);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('Bolinha em campo'), findsWidgets);
        expect(find.text('AGILIDADE E PLIOMETRIA'), findsOneWidget);
        expect(find.text('MODERADA'), findsWidgets);
        expect(find.text('OFEGANTE'), findsWidgets);
        expect(find.text('15 x'), findsOneWidget);
        expect(find.text('40 m'), findsOneWidget);
        expect(find.text('20 min'), findsWidgets);
        expect(
          find.text('Ótima resposta de explosão física.'),
          findsOneWidget,
        );

        assertStrictAbsenceOfObedienceCommands();
      },
    );
  });

  group('Obediência — renderização com e sem comandos (Requirement 3)', () {
    testWidgets(
      'obedience session with actual commands displays selected commands and stages',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'obed_sess_1',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 10, 0),
          trainingType: 'Obediência',
          location: 'Pátio Central',
          weather: '',
          handlerNotes: 'Treino de foco e transição de comandos.',
          metadata: {
            'specialty': 'obediencia',
            'commands': ['Senta', 'Fica', 'Junto'],
            'guia': 'Sem guia',
            'distracao': 'Média',
            'distancia': '10 m',
          },
        );

        final entry = HistoryEntry(
          id: 'entry_obed_1',
          type: HistoryEntryType.training,
          title: 'Treino • Obediência',
          subtitle: 'Pátio Central',
          time: DateTime(2026, 9, 27, 10, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Obediência',
            'commands': ['Senta', 'Fica', 'Junto'],
            'guia': 'Sem guia',
            'distracao': 'Média',
            'distancia': '10 m',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryObedienciaBody), findsOneWidget);
        expect(find.byType(HistoryCondicionamentoBody), findsNothing);

        // Expected actual commands are present (RichText)
        expect(find.textContaining('Senta', findRichText: true), findsOneWidget);
        expect(find.textContaining('Fica', findRichText: true), findsOneWidget);
        expect(find.textContaining('Junto', findRichText: true), findsOneWidget);
        expect(find.text('COMANDOS · ESTÁGIO'), findsOneWidget);
        expect(find.text('OPERACIONAIS'), findsOneWidget);

        // Unselected commands are NOT displayed
        expect(find.text('Deita', findRichText: true), findsNothing);
        expect(
          find.textContaining('Vem (chamada)', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('Latir sob comando', findRichText: true),
          findsNothing,
        );
      },
    );

    testWidgets(
      'obedience session with NO commands displays empty state and NEVER falls back to dummy commands',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'obed_sess_empty',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 11, 0),
          trainingType: 'Obediência',
          location: 'Pátio Central',
          weather: '',
          handlerNotes: 'Sessão introdutória de ambientação.',
          metadata: {
            'specialty': 'obediencia',
            'guia': 'Com guia',
            'distracao': 'Baixa',
            'distancia': '5 m',
            // No commands key in metadata
          },
        );

        final entry = HistoryEntry(
          id: 'entry_obed_empty',
          type: HistoryEntryType.training,
          title: 'Treino • Obediência',
          subtitle: 'Pátio Central',
          time: DateTime(2026, 9, 27, 11, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Obediência',
            'guia': 'Com guia',
            'distracao': 'Baixa',
            'distancia': '5 m',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryObedienciaBody), findsOneWidget);
        expect(find.byType(HistoryCondicionamentoBody), findsNothing);

        // Must display the empty state message
        expect(
          find.text('Nenhum comando registrado para esta sessão.'),
          findsOneWidget,
        );

        // MUST NOT display dummy hardcoded obedience commands
        expect(find.text('Senta', findRichText: true), findsNothing);
        expect(find.text('Deita', findRichText: true), findsNothing);
        expect(find.text('Fica', findRichText: true), findsNothing);
        expect(find.text('Vem', findRichText: true), findsNothing);
        expect(find.text('Junto', findRichText: true), findsNothing);
        expect(
          find.textContaining('Vem (chamada)', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('Latir sob comando', findRichText: true),
          findsNothing,
        );
        expect(find.text('OPERACIONAIS'), findsNothing);
        expect(find.text('POSICIONAIS'), findsNothing);
      },
    );
  });

  group('Preservação de outras linhas de treino (Detecção, Busca e Captura, Guarda)', () {
    testWidgets(
      'detection / scent session preserved and routes to HistoryDetectionBody',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'detec_sess_1',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 8, 0),
          trainingType: 'Detecção de Drogas',
          location: 'Hangar Canil',
          weather: 'Ameno',
          handlerNotes: 'Treino com caixas de faro.',
          metadata: {
            'line': 'Entorpecentes',
            'phase': 'Fase 3',
            'consecutiveHits': 12,
            'attempts': ['hit', 'hit', 'hit', 'hit'],
          },
        );

        final entry = HistoryEntry(
          id: 'entry_detec_1',
          type: HistoryEntryType.training,
          title: 'Treino • Detecção de Drogas',
          subtitle: 'Hangar Canil',
          time: DateTime(2026, 9, 27, 8, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Detecção de Drogas',
            'Linha': 'Entorpecentes',
            'current_phase': 'Fase 3',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryDetectionBody), findsOneWidget);
        expect(find.byType(HistoryCondicionamentoBody), findsNothing);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('PROTOCOLO RAGONHA'), findsOneWidget);
        expect(find.text('LINHA: ENTORPECENTES'), findsOneWidget);
        expect(find.text('⭐ FASE 3'), findsOneWidget);

        assertStrictAbsenceOfObedienceCommands();
      },
    );

    testWidgets(
      'search / track session preserved and routes to HistoryBuscaCapturaBody',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'busca_sess_1',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 7, 0),
          trainingType: 'Busca e Captura',
          location: 'Mata da Represa',
          weather: 'Úmido',
          handlerNotes: 'Rastreio em mata densa.',
          metadata: {
            'distance': '600m',
            'trailAge': '45 min',
            'searchDuration': '18 min',
            'odor': 'Artigo pessoal',
            'figurante': 'GCM Souza',
            'environment': 'Mata',
          },
        );

        final entry = HistoryEntry(
          id: 'entry_busca_1',
          type: HistoryEntryType.training,
          title: 'Treino • Busca e Captura',
          subtitle: 'Mata da Represa',
          time: DateTime(2026, 9, 27, 7, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Busca e Captura',
            'distance': '600m',
            'trailAge': '45 min',
            'searchDuration': '18 min',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryBuscaCapturaBody), findsOneWidget);
        expect(find.byType(HistoryCondicionamentoBody), findsNothing);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('RASTRO PERCORRIDO'), findsOneWidget);
        expect(find.text('600m'), findsOneWidget);
        expect(find.text('45 min'), findsOneWidget);
        expect(find.text('18 min'), findsOneWidget);

        assertStrictAbsenceOfObedienceCommands();
      },
    );

    testWidgets(
      'guard and protection session preserved and routes to HistoryGuardaProtecaoBody',
      (tester) async {
        final session = TrainingSessionModel(
          id: 'guarda_sess_1',
          dogId: 'dog_thor',
          dogName: 'Thor',
          date: DateTime(2026, 9, 27, 13, 0),
          trainingType: 'Guarda e Proteção',
          location: 'Pátio Tático',
          weather: 'Limpo',
          handlerNotes: 'Treino de mordida e coragem.',
          metadata: {
            'impulse': 'Defesa',
            'figurante': 'GCM Souza',
            'equipment': 'Manga',
          },
        );

        final entry = HistoryEntry(
          id: 'entry_guarda_1',
          type: HistoryEntryType.training,
          title: 'Treino • Guarda e Proteção',
          subtitle: 'Pátio Tático',
          time: DateTime(2026, 9, 27, 13, 0),
          author: 'GCM Silva',
          tag: 'TREINO',
          icon: Icons.fitness_center_rounded,
          color: Colors.green,
          originalModel: session,
          details: {
            'Tipo': 'Guarda e Proteção',
            'impulse': 'Defesa',
            'figurante': 'GCM Souza',
            'equipment': 'Manga',
          },
        );

        await pumpScreen(tester, entry);

        expect(find.byType(HistoryGuardaProtecaoBody), findsOneWidget);
        expect(find.byType(HistoryCondicionamentoBody), findsNothing);
        expect(find.byType(HistoryObedienciaBody), findsNothing);

        expect(find.text('IMPULSOS · ESTADO ATUAL'), findsOneWidget);

        assertStrictAbsenceOfObedienceCommands();
      },
    );
  });
}
