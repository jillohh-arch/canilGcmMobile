import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'pdf_colors.dart';
import 'pdf_common_widgets.dart';

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

/// Gerador do PDF do Histórico de Peso do Cão.
class WeightHistoryPdf {
  static final _blue = PdfInstitutionalColors.blue;
  static final _textPrimary = PdfInstitutionalColors.textPrimary;
  static final _textSecondary = PdfInstitutionalColors.textSecondary;
  static final _textTertiary = PdfInstitutionalColors.textTertiary;
  static final _lightGray = PdfInstitutionalColors.lightGray;
  static final _cardBorder = PdfInstitutionalColors.cardBorder;

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
  }) async {
    final pdf = pw.Document(
      author: 'Canil K9 GCM Limeira',
      title: 'Historico de Peso - ${dog.name}',
    );

    final fonts = await PdfFonts.load();

    // Filter weight-related logs
    final weightLogs =
        logs.where((log) => log.dogId == dog.id && log.weight != null).toList()
          ..sort((a, b) => b.date.compareTo(a.date)); // Newest first

    final docId = _buildDocId(dog);

    // Estatísticas derivadas SOMENTE de pesagens factuais (WEIGHT-01E-C2B).
    //
    // Antes, sem registros, `current` caía em `dog.weight ?? 0.0` e propagava
    // para mínimo/médio/máximo — produzindo estatística clínica inexistente
    // (inclusive 0,0 kg) em documento exportado. `dogs.weight` é projeção
    // legada, não evidência de pesagem.
    //
    // Estas são estatísticas DESCRITIVAS do conjunto exibido: `reduce` sobre
    // min/max/avg não elege peso atual nem endpoint de tendência.
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
    final PdfColor rangeColor = switch (rangeStatus) {
      'DENTRO DA FAIXA IDEAL' => PdfInstitutionalColors.greenInstitutional,
      'ABAIXO DO PESO IDEAL' => PdfInstitutionalColors.amberWarning,
      'ACIMA DO PESO IDEAL' => PdfInstitutionalColors.redAlert,
      _ => _textTertiary,
    };

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        header: (context) => PdfCommonWidgets.pageHeader(
          docType: 'HISTÓRICO DE PESO K9',
          docId: docId,
          fonts: fonts,
          color: _blue,
        ),
        footer: (context) => PdfCommonWidgets.pageFooter(
          context: context,
          docType: 'Histórico de Peso',
          fonts: fonts,
        ),
        build: (context) {
          return [
            // --- CAPA / CABEÇALHO DO RELATÓRIO ---
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ACOMPANHAMENTO BIOESTATÍSTICO K9',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 10,
                            color: _blue,
                            letterSpacing: 1.0,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          dog.name.toUpperCase(),
                          style: pw.TextStyle(
                            font: fonts.black,
                            fontSize: 26,
                            color: _textPrimary,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Raça: ${dog.breed}   |   Total de Pesagens: $count',
                          style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 10,
                            color: _textSecondary,
                          ),
                        ),
                        if (dog.idealWeightMin != null &&
                            dog.idealWeightMax != null)
                          pw.Text(
                            'Peso Ideal Configurado: ${dog.idealWeightMin!.toStringAsFixed(1)} kg a ${dog.idealWeightMax!.toStringAsFixed(1)} kg',
                            style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 9,
                              color: _textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  // Current Status Box
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: pw.BoxDecoration(
                      color: rangeColor.withAlpha(25),
                      border: pw.Border.all(color: rangeColor, width: 1.5),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'CONDIÇÃO FÍSICA',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 8,
                            color: rangeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          rangeStatus,
                          style: pw.TextStyle(
                            font: fonts.black,
                            fontSize: 10,
                            color: rangeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            PdfCommonWidgets.divider(),

            // --- 4 QUADROS DE ESTATÍSTICA ---
            pw.Row(
              children: [
                _buildStatBox(
                  'PESO ATUAL',
                  _statLabel(current),
                  fonts,
                  isPrimary: true,
                ),
                pw.SizedBox(width: 8),
                _buildStatBox('MÍNIMO', _statLabel(min), fonts),
                pw.SizedBox(width: 8),
                _buildStatBox('MÉDIO', _statLabel(avg), fonts),
                pw.SizedBox(width: 8),
                _buildStatBox('MÁXIMO', _statLabel(max), fonts),
              ],
            ),

            pw.SizedBox(height: 20),

            // --- ANÁLISE CLÍNICA ---
            PdfCommonWidgets.sectionTitle(
              title: 'AVALIAÇÃO DE DESEMPENHO FÍSICO E TENDÊNCIA',
              fonts: fonts,
              color: _blue,
            ),
            pw.SizedBox(height: 8),
            _buildClinicalAnalysis(summary, trendText, rangeColor, fonts),

            pw.SizedBox(height: 20),

            // --- TABELA DE PESAGENS ---
            PdfCommonWidgets.sectionTitle(
              title: 'REGISTROS CRONOLÓGICOS DE PESAGEM',
              fonts: fonts,
              color: _blue,
            ),
            pw.SizedBox(height: 8),
            _buildWeightTable(weightLogs, fonts),

            pw.SizedBox(height: 24),

            // --- BLOCO DE CONFORMIDADE E AUDITORIA (SEM HASH INJUSTIFICADO) ---
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _lightGray,
                border: pw.Border.all(color: _cardBorder),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 8,
                        height: 8,
                        decoration: pw.BoxDecoration(
                          color: PdfInstitutionalColors.greenInstitutional,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        'REGISTRO VERIFICADO & SINCRONIZADO',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 9,
                          color: PdfInstitutionalColors.greenInstitutional,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Este documento reflete em tempo real o histórico ponderal do cão ${dog.name}, registrado e mantido pela equipe de condutores e veterinários do Canil K9 da GCM de Limeira. Todas as modificações no prontuário geram trilhas de auditoria imutáveis.',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 8.5,
                      color: _textSecondary,
                      lineSpacing: 1.3,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Código de Rastreamento de Auditoria:',
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 8,
                          color: _textTertiary,
                        ),
                      ),
                      pw.Text(
                        _buildAuditReference(dog),
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 8.5,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Gera um ID de documento único estruturado.
  static String _buildDocId(Dog dog) {
    final year = DateTime.now().year;
    final month = DateTime.now().month.toString().padLeft(2, '0');
    final seq = dog.id.length >= 4
        ? dog.id.substring(0, 4).toUpperCase()
        : dog.id.toUpperCase().padRight(4, '0');
    return 'PESO: $year/$month/$seq-K9';
  }

  /// Gera uma referência de auditoria baseada no ID do cão e no timestamp atual.
  static String _buildAuditReference(Dog dog) {
    final dogPart = dog.id.length >= 6
        ? dog.id.substring(0, 6).toUpperCase()
        : dog.id.toUpperCase();
    final timePart = DateTime.now().millisecondsSinceEpoch.toString();
    final truncatedTime = timePart.length > 5
        ? timePart.substring(timePart.length - 5)
        : timePart;
    return 'AUDIT-$dogPart-$truncatedTime';
  }

  /// Caixa estatística.
  static pw.Widget _buildStatBox(
    String label,
    String value,
    PdfFonts fonts, {
    bool isPrimary = false,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: isPrimary ? _blue.withAlpha(20) : _lightGray,
          border: pw.Border.all(
            color: isPrimary ? _blue : _cardBorder,
            width: 1,
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 8,
                color: isPrimary ? _blue : _textTertiary,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: fonts.black,
                fontSize: 13,
                color: isPrimary ? _blue : _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rótulo de estatística: ausência explícita em vez de número fabricado.
  static String _statLabel(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} kg';

  /// Constrói a avaliação de desempenho clínico.
  ///
  /// A copy vem inteiramente de [WeightPdfSummary], que distingue os quatro
  /// estados canônicos. Antes, este bloco derivava a mensagem de um
  /// `currentWeight == null` e afirmava "Não há pesagens registradas" também em
  /// `inconclusive`/`unavailable` — falso quando existem registros legíveis.
  static pw.Widget _buildClinicalAnalysis(
    WeightPdfSummary summary,
    String trend,
    PdfColor color,
    PdfFonts fonts,
  ) {
    final message = summary.analysisMessage;

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color.withAlpha(15),
        border: pw.Border.all(color: color.withAlpha(40)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Tendência de Peso: $trend',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 10,
              color: _textPrimary,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            message,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9,
              color: _textSecondary,
              lineSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói a tabela de histórico de peso.
  static pw.Widget _buildWeightTable(
    List<HealthLogModel> logs,
    PdfFonts fonts,
  ) {
    if (logs.isEmpty) {
      return pw.Container(
        height: 80,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _cardBorder),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Text(
          'Nenhuma pesagem registrada no histórico.',
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: 10,
            color: _textTertiary,
          ),
        ),
      );
    }

    final headers = [
      'Data',
      'Peso (kg)',
      'Variação',
      'Registrado Por',
      'Observações',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _cardBorder, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(2.0),
        4: pw.FlexColumnWidth(3.0),
      },
      children: [
        // Table Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _blue),
          children: headers.map((header) {
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                header,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 9,
                  color: PdfInstitutionalColors.white,
                ),
              ),
            );
          }).toList(),
        ),
        // Table Rows
        ...List.generate(logs.length, (index) {
          final log = logs[index];
          final appDate = DateFormat('dd/MM/yyyy').format(log.date);
          final weight = log.weight ?? 0.0;
          final weightStr = '${weight.toStringAsFixed(1)} kg';

          // Variation logic
          double? diff;
          if (index + 1 < logs.length) {
            final prevWeight = logs[index + 1].weight;
            if (prevWeight != null) {
              diff = weight - prevWeight;
            }
          }

          String diffStr = '—';
          PdfColor diffColor = _textSecondary;
          if (diff != null && diff.abs() >= 0.1) {
            diffStr = '${diff > 0 ? "+" : ""}${diff.toStringAsFixed(1)} kg';
            diffColor = diff > 0
                ? PdfInstitutionalColors.amberWarning
                : PdfInstitutionalColors.greenInstitutional;
          }

          final registeredBy = log.vetName ?? log.createdBy ?? 'Sistema';
          final obs = log.healthObservations.trim().isNotEmpty
              ? log.healthObservations
              : 'Nenhuma';

          final isRowOdd = index.isOdd;
          final rowBg = isRowOdd ? _lightGray : PdfInstitutionalColors.white;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowBg),
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  appDate,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8.5,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  weightStr,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 8.5,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  diffStr,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 8.5,
                    color: diffColor,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  registeredBy,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: _textSecondary,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  obs,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: _textSecondary,
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
