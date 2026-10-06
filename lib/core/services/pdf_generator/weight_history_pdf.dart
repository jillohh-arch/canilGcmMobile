import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'pdf_common_widgets.dart';
import 'template/template.dart';

/// Estado canônico da autoridade de peso, transportado para o documento.
///
/// WEIGHT-01E-R-PDF: antes o documento recebia `double?`, o que colapsava três
/// estados distintos em `null` e permitia afirmar "Não há pesagens registradas"
/// sobre um cão com 12 pesagens válidas e um documento ilegível. Os quatro
/// estados espelham `ProntuarioWeightState`; o enum é redeclarado aqui para não
/// criar dependência de `features/health/presentation` a partir de `core`.
enum WeightPdfAuthorityState {
  /// Há peso atual factual decidido pela WeightCollectionPolicy.
  current,

  /// Coleção analisada com sucesso e nenhum registro elegível.
  none,

  /// Bloqueador global (`malformed`/`unsupported`/`entityId` duplicado): o
  /// peso atual é desconhecido e NENHUM registro pode ser promovido.
  inconclusive,

  /// Falha de leitura/resolução. NÃO é ausência de registro.
  unavailable,
}

/// Decisão canônica recebida pelo documento — ele nunca a recalcula.
final class WeightPdfAuthority {
  const WeightPdfAuthority({
    required this.state,
    this.currentKg,
    this.oldestKg,
  });

  const WeightPdfAuthority.none()
    : state = WeightPdfAuthorityState.none,
      currentKg = null,
      oldestKg = null;

  const WeightPdfAuthority.inconclusive()
    : state = WeightPdfAuthorityState.inconclusive,
      currentKg = null,
      oldestKg = null;

  const WeightPdfAuthority.unavailable()
    : state = WeightPdfAuthorityState.unavailable,
      currentKg = null,
      oldestKg = null;

  final WeightPdfAuthorityState state;

  /// Peso atual canônico; só existe em [WeightPdfAuthorityState.current].
  final double? currentKg;

  /// Extremo histórico mais antigo elegível, escolhido pela ordenação canônica
  /// (`measuredAt` → `recordedAt` → `entityId`) ANTES da conversão para
  /// `HealthLogModel`, que descarta `recordedAt`/`entityId`. `null` quando não
  /// há segundo registro com que comparar.
  ///
  /// Não é o "peso anterior": a tendência deste documento compara o atual com o
  /// extremo antigo da série, não com o registro imediatamente anterior.
  final double? oldestKg;

  bool get isCurrent => state == WeightPdfAuthorityState.current;
}

/// Semântica textual do documento, derivada de forma pura e testável.
///
/// Existe para que os estados canônicos sejam verificáveis sem inspecionar
/// bytes de PDF: toda a decisão de copy vive aqui.
final class WeightPdfSummary {
  const WeightPdfSummary({
    required this.currentLabel,
    required this.trendText,
    required this.rangeStatus,
    required this.analysisMessage,
    required this.totalDisplayedRecords,
    required this.isConclusive,
  });

  /// Deriva a semântica a partir da autoridade canônica e dos registros legíveis.
  ///
  /// [displayedWeights] são as pesagens efetivamente exibidas na tabela. Elas
  /// alimentam mínimo/médio/máximo e a contagem, mas NUNCA decidem peso atual
  /// nem endpoint de tendência.
  factory WeightPdfSummary.from({
    required WeightPdfAuthority authority,
    required List<double> displayedWeights,
    double? idealWeightMin,
    double? idealWeightMax,
  }) {
    final count = displayedWeights.length;
    final current = authority.isCurrent ? authority.currentKg : null;

    // Estado não conclusivo NÃO promove registro algum, mesmo havendo válidos.
    if (current == null) {
      final String message;
      final String range;
      switch (authority.state) {
        case WeightPdfAuthorityState.none:
          message =
              'Não há pesagens registradas para este cão. Sem evidência de '
              'pesagem não é possível avaliar peso atual, tendência ou faixa '
              'ideal.';
          range = 'Sem Pesagem Registrada';
        case WeightPdfAuthorityState.inconclusive:
          // O histórico legível permanece visível; o que não é permitido é
          // afirmar ausência de pesagens ou eleger um dos registros.
          message =
              'Análise atual não conclusiva: existe registro de pesagem '
              'inconsistente nesta coleção. $count registro(s) legível(is) '
              'permanecem listados para fins históricos, mas peso atual, '
              'tendência e faixa ideal não podem ser afirmados.';
          range = 'Análise Não Conclusiva';
        case WeightPdfAuthorityState.unavailable:
          message =
              'Não foi possível consultar as pesagens deste cão. Ausência de '
              'leitura não equivale a ausência de registro.';
          range = 'Peso Atual Indisponível';
        case WeightPdfAuthorityState.current:
          // Inalcançável: `current` nulo com estado `current` seria contrato
          // violado; tratado como indisponível em vez de fabricar valor.
          message =
              'Não foi possível determinar o peso atual canônico deste cão.';
          range = 'Peso Atual Indisponível';
      }
      return WeightPdfSummary(
        currentLabel: '—',
        trendText: switch (authority.state) {
          WeightPdfAuthorityState.none => 'Sem pesagens registradas',
          WeightPdfAuthorityState.unavailable => 'Tendência indisponível',
          _ => 'Tendência não conclusiva',
        },
        rangeStatus: range,
        analysisMessage: message,
        totalDisplayedRecords: count,
        isConclusive: false,
      );
    }

    // Tendência: atual canônico contra o extremo antigo canônico.
    final oldest = authority.oldestKg;
    var trend = 'Estável';
    if (oldest != null) {
      final diff = current - oldest;
      if (diff.abs() < 0.5) {
        trend = 'Estável (Variação insignificante)';
      } else if (diff > 0) {
        trend = 'Ganho de Peso (+${diff.toStringAsFixed(1)} kg)';
      } else {
        trend = 'Perda de Peso (${diff.toStringAsFixed(1)} kg)';
      }
    }

    var range = 'Faixa Ideal Não Configurada';
    var message =
        'Faixa ideal não configurada para este cão. Sem referência não é '
        'possível classificar o peso atual.';
    if (idealWeightMin != null && idealWeightMax != null) {
      if (current >= idealWeightMin && current <= idealWeightMax) {
        range = 'DENTRO DA FAIXA IDEAL';
        message =
            'O cão encontra-se no peso recomendado para as atividades '
            'institucionais e de alta intensidade do canil. Recomenda-se manter '
            'a rotina nutricional e de treinos atual.';
      } else if (current < idealWeightMin) {
        range = 'ABAIXO DO PESO IDEAL';
        message =
            'Atenção: O cão está abaixo do peso ideal recomendado. Isso pode '
            'impactar sua performance de guarda, proteção e resistência física. '
            'Sugere-se avaliação de ração/suplementação.';
      } else {
        range = 'ACIMA DO PESO IDEAL';
        message =
            'Atenção: O cão está acima do peso ideal recomendado. O excesso de '
            'peso pode reduzir agilidade, resistência e vida útil operacional. '
            'Sugere-se ajuste nutricional e reavaliação de carga de treino.';
      }
    }

    return WeightPdfSummary(
      currentLabel: '${current.toStringAsFixed(1)} kg',
      trendText: trend,
      rangeStatus: range,
      analysisMessage: message,
      totalDisplayedRecords: count,
      isConclusive: true,
    );
  }

  final String currentLabel;
  final String trendText;
  final String rangeStatus;
  final String analysisMessage;
  final int totalDisplayedRecords;

  /// `false` em `none`/`inconclusive`/`unavailable`: nenhuma afirmação clínica
  /// de peso atual, tendência ou faixa é autoritativa.
  final bool isConclusive;
}

/// Gerador do PDF do Histórico de Peso do Cão baseado na Foundation F70 Oficial.
class WeightHistoryPdf {
  /// Gera os bytes do PDF de histórico de peso.
  ///
  /// [authority] transporta a decisão da `WeightCollectionPolicy` — os quatro
  /// estados canônicos, o peso atual e o extremo antigo da tendência. O
  /// documento NUNCA recalcula essa decisão: `HealthLogModel` carrega apenas
  /// `date` + `weight`, então `recordedAt`/`entityId` já foram descartados aqui
  /// e o desempate canônico é inexpressável neste ponto.
  ///
  /// [logs] alimentam somente tabela e estatísticas descritivas
  /// (mínimo/médio/máximo) e devem vir da coleção COMPLETA, não de uma janela.
  static Future<Uint8List> generate(
    Dog dog,
    List<HealthLogModel> logs, {
    required WeightPdfAuthority authority,
    Uint8List? dogPhotoBytes,
  }) async {
    final fonts = await PdfFonts.load();

    // Filtra logs de pesagem do cão (mais recentes primeiro)
    final weightLogs = logs
        .where((log) => log.dogId == dog.id && log.weight != null)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    // Estatísticas derivadas SOMENTE de pesagens factuais (WEIGHT-01E-C2B).
    final weights = weightLogs.map((l) => l.weight!).toList();
    final summary = WeightPdfSummary.from(
      authority: authority,
      displayedWeights: weights,
      idealWeightMin: dog.idealWeightMin,
      idealWeightMax: dog.idealWeightMax,
    );
    final count = summary.totalDisplayedRecords;
    final double? current = authority.isCurrent ? authority.currentKg : null;
    final double? min = weights.isNotEmpty
        ? weights.reduce((a, b) => a < b ? a : b)
        : null;
    final double? max = weights.isNotEmpty
        ? weights.reduce((a, b) => a > b ? a : b)
        : null;
    final double? avg = weights.isNotEmpty
        ? weights.reduce((a, b) => a + b) / weights.length
        : null;

    final trendText = summary.trendText;
    final rangeStatus = summary.rangeStatus;
    final ReportTone rangeTone = switch (rangeStatus) {
      'DENTRO DA FAIXA IDEAL' => ReportTone.positive,
      'ABAIXO DO PESO IDEAL' => ReportTone.attention,
      'ACIMA DO PESO IDEAL' => ReportTone.critical,
      _ => ReportTone.neutral,
    };

    final now = DateTime.now();

    final metadata = ReportMetadata(
      generatedAt: now,
      dogIdentity: '${dog.name} (${dog.breed})',
      operatorName: dog.conductorRa != null ? 'Condutor RA: ${dog.conductorRa}' : null,
    );

    final builder = ReportTemplateBuilder(
      title: 'HISTÓRICO DE PESO K9',
      subtitle: 'ACOMPANHAMENTO BIOESTATÍSTICO E CONDICIONAMENTO FÍSICO',
      category: 'AVALIAÇÃO PONDERAL K9',
      motto: 'DISCIPLINA · PROTEÇÃO · RESULTADO',
      metadata: metadata,
      statusLabel: rangeStatus,
      statusTone: rangeTone,
      useDarkFooter: true,
      archetypeConfig: ReportArchetypeConfig.clinicalTactical(),
    );

    // 1. Hero Section / Identidade do Cão (Foto Ampliada + Ficha em 2 Colunas)
    builder.addWidget(
      ReportPrimitives.entityIdentityBlock(
        EntityIdentityData(
          title: dog.name.toUpperCase(),
          subtitle: 'Raça: ${dog.breed}',
          registrationBadge: dog.registrationNumber,
          tags: [
            'CÃO DE TRABALHO',
            if (dog.specialties != null) ...dog.specialties!,
          ],
          statusLabel: dog.status.toUpperCase(),
          statusTone: dog.status.toLowerCase() == 'ativo'
              ? ReportTone.positive
              : ReportTone.neutral,
          avatar: dogPhotoBytes != null ? ReportImageSlot(bytes: dogPhotoBytes) : null,
          avatarPlaceholder: dog.name.isNotEmpty
              ? dog.name.substring(0, dog.name.length >= 2 ? 2 : 1).toUpperCase()
              : 'K9',
          fields: [
            EntityIdentityField(label: 'Raça', value: dog.breed),
            EntityIdentityField(label: 'Sexo', value: dog.sex == 'M' ? 'Macho' : 'Fêmea'),
            EntityIdentityField(
              label: 'Nascimento',
              value: DateFormat('dd/MM/yyyy').format(dog.dateOfBirth),
              isMonospace: true,
            ),
            EntityIdentityField(
              label: 'Microchip',
              value: dog.microchip ?? 'Não informado',
              isMonospace: true,
            ),
            EntityIdentityField(
              label: 'Condutor',
              value: dog.conductorRa != null ? 'GCM RA ${dog.conductorRa}' : 'Não informado',
            ),
            EntityIdentityField(
              label: 'Total de Pesagens',
              value: '$count registradas',
            ),
            EntityIdentityField(
              label: 'Faixa Ideal Configurada',
              value: dog.idealWeightMin != null && dog.idealWeightMax != null
                  ? '${dog.idealWeightMin!.toStringAsFixed(1)} kg a ${dog.idealWeightMax!.toStringAsFixed(1)} kg'
                  : 'Não configurada',
            ),
          ],
        ),
        fonts,
      ),
    );

    // 2. 4 Quadros de Estatística / Métricas (PESO ATUAL, MÍNIMO, MÉDIO, MÁXIMO)
    builder.addWidget(
      pw.Row(
        children: [
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Peso Atual',
                value: _statLabel(current),
                tone: summary.isConclusive ? ReportTone.info : ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Mínimo',
                value: _statLabel(min),
                tone: ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Médio',
                value: _statLabel(avg),
                tone: ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Máximo',
                value: _statLabel(max),
                tone: ReportTone.neutral,
              ),
              fonts,
            ),
          ),
        ],
      ),
    );

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 3. Análise Clínica e Tendência guiada por WeightPdfSummary
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'AVALIAÇÃO DE DESEMPENHO FÍSICO E TENDÊNCIA',
        fonts,
        iconText: 'BIO',
        subtitle: 'Análise bioestatística autoritativa baseada na série temporal de pesagens',
      ),
    );

    builder.addWidget(
      ReportPrimitives.summaryCard(
        SummaryCardData(
          title: 'Tendência Ponderal: $trendText',
          description: summary.analysisMessage,
          bulletItems: [
            'Classificação: $rangeStatus',
            if (summary.isConclusive && count >= 2)
              'Avaliação baseada no extremo canônico de comparação da série histórica.',
          ],
          tone: rangeTone,
        ),
        fonts,
      ),
    );

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 4. Gráfico de Evolução Ponderal K9
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'EVOLUÇÃO PONDERAL (GRÁFICO)',
        fonts,
        iconText: 'EVO',
        subtitle: 'Curva temporal de pesagens com faixa ideal operacional',
      ),
    );

    final chartPoints = weightLogs.reversed
        .map((l) => WeightChartPoint(date: l.date, weight: l.weight!))
        .toList();

    builder.addWidget(
      ReportPrimitives.weightTrendChart(
        points: chartPoints,
        idealMin: dog.idealWeightMin,
        idealMax: dog.idealWeightMax,
        fonts: fonts,
      ),
    );

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 5. Tabela Rica de Pesagens Cronológicas com zebra
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'REGISTROS CRONOLÓGICOS DE PESAGEM',
        fonts,
        iconText: 'LOG',
        subtitle: 'Histórico factual completo registrado pela equipe técnica',
      ),
    );

    builder.addWidget(_buildWeightTable(weightLogs, fonts));

    builder.addWidget(pw.SizedBox(height: ReportSpacing.md));

    // 6. Bloco de Emissão
    builder.addWidget(
      pw.Container(
        padding: const pw.EdgeInsets.all(ReportSpacing.sm),
        decoration: pw.BoxDecoration(
          color: ReportColors.surfaceSubtle,
          border: pw.Border.all(color: ReportColors.borderSoft, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'ACOMPANHAMENTO BIOESTATÍSTICO · SISTEMA K9 OPS',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 7,
                color: ReportColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            pw.Text(
              'Emissão: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
              style: pw.TextStyle(
                font: fonts.monoRegular,
                fontSize: 7.5,
                color: ReportColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );

    return builder.buildPdf(customFonts: fonts);
  }

  /// Rótulo de estatística: ausência explícita em vez de número fabricado.
  static String _statLabel(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} kg';

  /// Constrói a tabela rica de histórico de peso.
  static pw.Widget _buildWeightTable(
    List<HealthLogModel> logs,
    PdfFonts fonts,
  ) {
    if (logs.isEmpty) {
      return ReportPrimitives.observationBlock(
        const ObservationBlockData(
          title: 'Histórico de Pesagem',
          text: 'Nenhuma pesagem registrada no histórico.',
        ),
        fonts,
      );
    }

    final columns = const [
      DataTableColumn(
        header: 'Data',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.2,
      ),
      DataTableColumn(
        header: 'Peso (kg)',
        alignment: DataTableCellAlignment.right,
        isMonospace: true,
        flex: 1.2,
      ),
      DataTableColumn(
        header: 'Variação',
        alignment: DataTableCellAlignment.right,
        isMonospace: true,
        flex: 1.2,
      ),
      DataTableColumn(header: 'Registrado Por', flex: 2.0),
      DataTableColumn(header: 'Observações', flex: 3.0),
    ];

    final rows = <RichDataTableRow>[];
    for (int index = 0; index < logs.length; index++) {
      final log = logs[index];
      final appDate = DateFormat('dd/MM/yyyy').format(log.date);
      final weight = log.weight ?? 0.0;
      final weightStr = '${weight.toStringAsFixed(1)} kg';

      // Lógica de variação em relação ao registro cronológico anterior
      double? diff;
      if (index + 1 < logs.length) {
        final prevWeight = logs[index + 1].weight;
        if (prevWeight != null) {
          diff = weight - prevWeight;
        }
      }

      String diffStr = '—';
      PdfColor diffColor = ReportColors.textSecondary;
      if (diff != null && diff.abs() >= 0.1) {
        diffStr = '${diff > 0 ? "+" : ""}${diff.toStringAsFixed(1)} kg';
        diffColor = diff > 0
            ? PdfColor.fromHex('B88A0C')
            : PdfColor.fromHex('166534');
      }

      final registeredBy = log.vetName ?? log.createdBy ?? 'Sistema';
      final obs = log.healthObservations.trim().isNotEmpty
          ? log.healthObservations.trim()
          : 'Nenhuma';

      rows.add(
        RichDataTableRow(
          cells: [
            RichTableCell.text(appDate, isMonospace: true),
            RichTableCell.text(weightStr, isBold: true, isMonospace: true),
            RichTableCell.text(
              diffStr,
              isBold: true,
              isMonospace: true,
              textColor: diffColor,
            ),
            RichTableCell.text(registeredBy),
            RichTableCell.text(obs),
          ],
        ),
      );
    }

    return ReportPrimitives.richDataTable(
      RichDataTableData(columns: columns, rows: rows),
      fonts,
    );
  }
}
