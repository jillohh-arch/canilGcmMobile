import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';

import 'pdf_colors.dart';
import 'pdf_common_widgets.dart';

/// Gerador do PDF institucional de Ocorrência (6 páginas).
class OccurrencePdfGenerator {
  static final _identityColor = PdfInstitutionalColors.cyan;
  static const _docType = 'REGISTRO DE OCORRÊNCIA';

  /// Gera o PDF completo e retorna os bytes.
  Future<Uint8List> generate({
    required Occurrence occurrence,
    required List<OccurrenceEvent> events,
    required Dog dog,
    required String handlerName,
    required String handlerRa,
  }) async {
    final pdf = pw.Document(
      author: 'Canil K9 GCM Limeira',
      title: 'Registro de Ocorrência - ${occurrence.typeName}',
    );
    final fonts = await PdfFonts.load();
    final docId = _buildDocId(occurrence);
    final sortedEvents = [...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Página 1: Capa
    pdf.addPage(_buildCoverPage(occurrence, dog, handlerName, handlerRa, docId, fonts));

    // Página 2: Identificação
    pdf.addPage(_buildIdentificationPage(occurrence, dog, handlerName, handlerRa, docId, fonts));

    // Página 3: Ocorrência e Localização
    pdf.addPage(_buildLocationPage(occurrence, docId, fonts));

    // Página 4: Timeline de Eventos
    pdf.addPage(_buildTimelinePage(sortedEvents, docId, fonts));

    // Página 5: Relato e Resultado
    pdf.addPage(_buildReportPage(occurrence, docId, fonts));

    // Página 6: Auditoria e Assinatura
    pdf.addPage(_buildAuditPage(occurrence, handlerName, docId, fonts));

    return pdf.save();
  }

  String _buildDocId(Occurrence occ) {
    final date = occ.startedAt;
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final seq = occ.id.substring(0, 4).toUpperCase();
    return 'REG $y/$m/$seq-K9';
  }

  String _formatDate(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt);
  String _formatTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  String _formatDuration(Occurrence occ) {
    if (occ.finalizedAt == null) return '--';
    final diff = occ.finalizedAt!.difference(occ.startedAt);
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, "0")}min';
    return '${m}min';
  }

  // ═══════════════════════════════════════════════════════════════════
  // PÁGINA 1 — CAPA
  // ═══════════════════════════════════════════════════════════════════

  pw.Page _buildCoverPage(
    Occurrence occ,
    Dog dog,
    String handlerName,
    String handlerRa,
    String docId,
    PdfFonts fonts,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Topo: Brasão + Instituição
          pw.Column(
            children: [
              pw.SizedBox(height: 40),
              pw.Container(
                width: 60,
                height: 60,
                decoration: pw.BoxDecoration(
                  color: _identityColor,
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Center(
                  child: pw.Text('K9',
                      style: pw.TextStyle(
                          font: fonts.black, fontSize: 20, color: PdfColors.white)),
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text('GUARDA CIVIL MUNICIPAL',
                  style: pw.TextStyle(
                      font: fonts.black, fontSize: 14, letterSpacing: 2)),
              pw.Text('DE LIMEIRA',
                  style: pw.TextStyle(
                      font: fonts.bold, fontSize: 12, letterSpacing: 2)),
              pw.SizedBox(height: 6),
              pw.Text('CANIL K9 · SEÇÃO OPERACIONAL',
                  style: fonts.label(color: _identityColor)),
            ],
          ),
          // Centro: Tipo + Título
          pw.Column(
            children: [
              pw.Container(height: 2, width: 200, color: _identityColor),
              pw.SizedBox(height: 20),
              pw.Text(_docType,
                  style: fonts.label(color: PdfInstitutionalColors.textTertiary)),
              pw.SizedBox(height: 8),
              pw.Text(occ.typeName,
                  style: fonts.heading(),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 20),
              // Metadata card
              PdfCommonWidgets.card(
                borderColor: _identityColor,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    _metaItem('DATA', _formatDate(occ.startedAt), fonts),
                    _metaItem('INÍCIO', _formatTime(occ.startedAt), fonts),
                    _metaItem('DURAÇÃO', _formatDuration(occ), fonts),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(docId,
                  style: pw.TextStyle(
                      font: fonts.bold, fontSize: 14, color: _identityColor)),
            ],
          ),
          // Rodapé: Binômio
          pw.Column(
            children: [
              pw.Text('BINÔMIO RESPONSÁVEL',
                  style: fonts.label(color: _identityColor)),
              pw.SizedBox(height: 8),
              pw.Text(handlerName,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 13)),
              pw.Text('RA $handlerRa · K9 ${dog.name}',
                  style: fonts.caption()),
              pw.SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _metaItem(String label, String value, PdfFonts fonts) {
    return pw.Column(
      children: [
        pw.Text(label, style: fonts.label()),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(font: fonts.bold, fontSize: 13)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PÁGINA 2 — IDENTIFICAÇÃO
  // ═══════════════════════════════════════════════════════════════════

  pw.Page _buildIdentificationPage(
    Occurrence occ,
    Dog dog,
    String handlerName,
    String handlerRa,
    String docId,
    PdfFonts fonts,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfCommonWidgets.pageHeader(
              docType: _docType, docId: docId, fonts: fonts, color: _identityColor),
          PdfCommonWidgets.sectionTitle(
              title: 'Identificação do Binômio', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Condutor
              pw.Expanded(
                child: PdfCommonWidgets.card(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CONDUTOR',
                          style: fonts.label(color: _identityColor)),
                      pw.SizedBox(height: 6),
                      pw.Text(handlerName,
                          style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
                      pw.SizedBox(height: 4),
                      pw.Text('RA: $handlerRa', style: fonts.body()),
                      pw.Text('Função: Condutor K9', style: fonts.caption()),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              // Cão
              pw.Expanded(
                child: PdfCommonWidgets.card(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CÃO K9',
                          style: fonts.label(color: _identityColor)),
                      pw.SizedBox(height: 6),
                      pw.Text(dog.name.toUpperCase(),
                          style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
                      pw.SizedBox(height: 4),
                      pw.Text('Raça: ${dog.breed}', style: fonts.body()),
                      pw.Text('Matrícula: ${dog.registrationNumber ?? "N/I"}',
                          style: fonts.body()),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          PdfCommonWidgets.sectionTitle(
              title: 'Dados Administrativos', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          PdfCommonWidgets.infoTable(
            rows: [
              MapEntry('TURNO/PLANTÃO', occ.shiftId.isNotEmpty ? occ.shiftId.substring(0, 8) : 'N/I'),
              MapEntry('DATA', _formatDate(occ.startedAt)),
              MapEntry('INÍCIO', _formatTime(occ.startedAt)),
              MapEntry('TÉRMINO', occ.finalizedAt != null ? _formatTime(occ.finalizedAt!) : 'N/I'),
              MapEntry('DURAÇÃO', _formatDuration(occ)),
              MapEntry('NATUREZA', occ.typeName),
            ],
            fonts: fonts,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PÁGINA 3 — OCORRÊNCIA E LOCALIZAÇÃO
  // ═══════════════════════════════════════════════════════════════════

  pw.Page _buildLocationPage(
    Occurrence occ,
    String docId,
    PdfFonts fonts,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfCommonWidgets.pageHeader(
              docType: _docType, docId: docId, fonts: fonts, color: _identityColor),
          PdfCommonWidgets.sectionTitle(
              title: 'Ocorrência e Localização', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          // Mapa placeholder
          pw.Container(
            height: 160,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('E8F0F2'),
              border: pw.Border.all(color: _identityColor),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('LOCALIZAÇÃO GPS',
                      style: fonts.label(color: _identityColor)),
                  pw.SizedBox(height: 8),
                  if (occ.gpsLat != null && occ.gpsLng != null)
                    pw.Text(
                      '${occ.gpsLat!.toStringAsFixed(6)}, ${occ.gpsLng!.toStringAsFixed(6)}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                    )
                  else
                    pw.Text('Coordenadas indisponíveis', style: fonts.body()),
                  pw.SizedBox(height: 4),
                  pw.Text('Mapa estático disponível em versão futura',
                      style: fonts.caption()),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          if (occ.locationAddress != null && occ.locationAddress!.isNotEmpty)
            pw.Text(occ.locationAddress!,
                style: fonts.caption(), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 16),
          // Boxes destacados
          pw.Row(
            children: [
              pw.Expanded(
                child: _highlightBox('NATUREZA', occ.typeName, fonts),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _highlightBox('DURAÇÃO', _formatDuration(occ), fonts),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          PdfCommonWidgets.sectionTitle(
              title: 'Dados de Localização', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          PdfCommonWidgets.infoTable(
            rows: [
              MapEntry('ENDEREÇO', occ.locationAddress ?? 'N/I'),
              MapEntry('LATITUDE', occ.gpsLat?.toStringAsFixed(6) ?? 'N/I'),
              MapEntry('LONGITUDE', occ.gpsLng?.toStringAsFixed(6) ?? 'N/I'),
              MapEntry('PRECISÃO GPS',
                  occ.gpsAccuracy != null ? '±${occ.gpsAccuracy!.toStringAsFixed(0)}m' : 'N/I'),
            ],
            fonts: fonts,
          ),
        ],
      ),
    );
  }

  pw.Widget _highlightBox(String label, String value, PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfInstitutionalColors.lightGray,
        border: pw.Border(left: pw.BorderSide(color: _identityColor, width: 3)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: fonts.label()),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(font: fonts.black, fontSize: 13)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PÁGINA 4 — TIMELINE DE EVENTOS
  // ═══════════════════════════════════════════════════════════════════

  pw.Page _buildTimelinePage(
    List<OccurrenceEvent> events,
    String docId,
    PdfFonts fonts,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfCommonWidgets.pageHeader(
              docType: _docType, docId: docId, fonts: fonts, color: _identityColor),
          PdfCommonWidgets.sectionTitle(
              title: 'Linha do Tempo de Eventos', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          if (events.isEmpty)
            pw.Text('Nenhum evento registrado.', style: fonts.body())
          else
            ...events.map((e) => _buildTimelineEntry(e, fonts)),
        ],
      ),
    );
  }

  pw.Widget _buildTimelineEntry(OccurrenceEvent event, PdfFonts fonts) {
    final time = _formatTime(event.timestamp);
    final hasPhotos = event.photoUrls.isNotEmpty;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfInstitutionalColors.cardBorder, width: 0.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Horário
          pw.SizedBox(
            width: 42,
            child: pw.Text(time,
                style: pw.TextStyle(
                    font: fonts.bold, fontSize: 10, color: _identityColor)),
          ),
          // Dot
          pw.Container(
            width: 9,
            height: 9,
            margin: const pw.EdgeInsets.only(top: 2, right: 10),
            decoration: pw.BoxDecoration(
              color: _identityColor,
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: PdfColors.white, width: 1.5),
            ),
          ),
          // Content
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(event.title ?? event.category.label,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                if (event.description != null && event.description!.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(event.description!,
                        style: fonts.body(
                            color: PdfInstitutionalColors.textSecondary)),
                  ),
                if (hasPhotos)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      '${event.photoUrls.length} foto(s) anexada(s)',
                      style: fonts.caption(color: _identityColor),
                    ),
                  ),
                if (event.gpsLat != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      'GPS: ${event.gpsLat!.toStringAsFixed(5)}, ${event.gpsLng!.toStringAsFixed(5)}',
                      style: fonts.mono(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PÁGINA 5 — RELATO E RESULTADO
  // ═══════════════════════════════════════════════════════════════════

  pw.Page _buildReportPage(
    Occurrence occ,
    String docId,
    PdfFonts fonts,
  ) {
    final activeResults = occ.results
        .where((r) => r != OccurrenceResult.noOccurrence)
        .toList();

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfCommonWidgets.pageHeader(
              docType: _docType, docId: docId, fonts: fonts, color: _identityColor),
          PdfCommonWidgets.sectionTitle(
              title: 'Relato Institucional', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          // Relato card
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfInstitutionalColors.lightGray,
              border: pw.Border.all(color: PdfInstitutionalColors.cardBorder),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('TRANSCRIÇÃO DE ÁUDIO · REVISADA',
                        style: fonts.label(color: _identityColor)),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  height: 0.5,
                  color: PdfInstitutionalColors.divider,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  occ.finalReport ?? 'Relato não registrado.',
                  style: fonts.body(),
                  textAlign: pw.TextAlign.justify,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          if (activeResults.isNotEmpty) ...[
            PdfCommonWidgets.sectionTitle(
                title: 'Resultados da Ocorrência',
                fonts: fonts,
                color: PdfInstitutionalColors.greenInstitutional),
            pw.SizedBox(height: 8),
            ...activeResults.map((r) => _buildResultEntry(r, occ, fonts)),
          ] else ...[
            PdfCommonWidgets.sectionTitle(
                title: 'Resultado', fonts: fonts, color: _identityColor),
            pw.SizedBox(height: 8),
            pw.Text('Sem ocorrência policial registrada.', style: fonts.body()),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildResultEntry(
      OccurrenceResult result, Occurrence occ, PdfFonts fonts) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('E8F5ED'),
        border: pw.Border(
          left: pw.BorderSide(
              color: PdfInstitutionalColors.greenInstitutional, width: 3),
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(result.label,
          style: fonts.bodyBold(color: PdfInstitutionalColors.greenInstitutional)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PÁGINA 6 — AUDITORIA E ASSINATURA
  // ═══════════════════════════════════════════════════════════════════

  pw.Page _buildAuditPage(
    Occurrence occ,
    String handlerName,
    String docId,
    PdfFonts fonts,
  ) {
    final hash = occ.integrityHash ?? 'N/I';
    final verificationUrl = 'https://canilk9-limeira.web.app/v/${occ.id}';

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          PdfCommonWidgets.pageHeader(
              docType: _docType, docId: docId, fonts: fonts, color: _identityColor),
          PdfCommonWidgets.sectionTitle(
              title: 'Trilha de Auditoria', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          // Audit trail entries
          if (occ.auditTrail.isEmpty)
            pw.Text('Nenhuma alteração registrada após criação.', style: fonts.body())
          else
            ...occ.auditTrail.take(15).map((entry) => _buildAuditEntry(entry, fonts)),
          pw.SizedBox(height: 20),
          // Hash card
          PdfCommonWidgets.sectionTitle(
              title: 'Integridade do Documento', fonts: fonts, color: _identityColor),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfInstitutionalColors.lightGray,
              border: pw.Border.all(color: _identityColor),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('HASH DE INTEGRIDADE',
                    style: fonts.label(color: _identityColor)),
                pw.SizedBox(height: 6),
                pw.Text('SHA-256: $hash', style: fonts.mono(fontSize: 9)),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Este hash garante que o documento não foi alterado após a finalização.',
                  style: fonts.caption(),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // QR Code
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.BarcodeWidget(
                data: verificationUrl,
                barcode: pw.Barcode.qrCode(),
                width: 70,
                height: 70,
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('VERIFICAÇÃO ONLINE',
                        style: fonts.label(color: _identityColor)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Escaneie o QR Code para verificar a autenticidade deste documento.',
                      style: fonts.body(),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(verificationUrl, style: fonts.mono()),
                  ],
                ),
              ),
            ],
          ),
          pw.Spacer(),
          // Assinatura
          PdfCommonWidgets.divider(),
          pw.SizedBox(height: 30),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Container(
                  width: 250,
                  height: 0.5,
                  color: PdfInstitutionalColors.textPrimary,
                ),
                pw.SizedBox(height: 6),
                pw.Text(handlerName,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
                pw.Text('Condutor K9 · GCM Limeira', style: fonts.caption()),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text(
              'Documento gerado automaticamente pelo Sistema Canil K9 GCM',
              style: fonts.caption(),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAuditEntry(Map<String, dynamic> entry, PdfFonts fonts) {
    final action = entry['action'] as String? ?? '';
    final field = entry['field_name'] as String? ?? '';
    final at = entry['at'] as String? ?? '';
    final description = field.isNotEmpty ? '$action · $field' : action;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 60,
            child: pw.Text(at.length >= 16 ? at.substring(11, 16) : at,
                style: fonts.mono()),
          ),
          pw.Container(
            width: 6,
            height: 6,
            margin: const pw.EdgeInsets.only(top: 3, right: 8),
            decoration: pw.BoxDecoration(
              color: PdfInstitutionalColors.divider,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.Expanded(
            child: pw.Text(description, style: fonts.caption()),
          ),
        ],
      ),
    );
  }
}
