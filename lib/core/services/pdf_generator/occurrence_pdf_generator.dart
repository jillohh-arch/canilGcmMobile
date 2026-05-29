import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/core/services/occurrence_location_service.dart';
import 'package:canil_gcm/core/services/osm_static_map_generator.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/domain/amendment.dart';
import 'package:canil_gcm/features/occurrences/data/amendment_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

import 'pdf_common_widgets.dart';

/// Gerador do PDF institucional de ocorrencia baseado nos mockups V2.
class OccurrencePdfGenerator {
  static const _photoRequestTimeout = Duration(seconds: 12);
  static const _pdfPhotoMaxDimension = 960;
  static const _pdfPhotoJpegQuality = 72;

  static final _paper = PdfColors.white;
  static final _ink = PdfColor.fromHex('14202B');
  static final _inkSoft = PdfColor.fromHex('46586A');
  static final _inkFaint = PdfColor.fromHex('8493A1');
  static final _line = PdfColor.fromHex('DDE4EA');
  static final _lineSoft = PdfColor.fromHex('EAEFF3');
  static final _cyan = PdfColor.fromHex('0A8E9D');
  static final _cyanDeep = PdfColor.fromHex('07707C');
  static final _green = PdfColor.fromHex('1F9D52');
  static final _greenBg = PdfColor.fromHex('F1FAF4');
  static final _greenLine = PdfColor.fromHex('BFE6CF');
  static final _amber = PdfColor.fromHex('B07D0A');
  static final _amberBg = PdfColor.fromHex('FDF8EC');
  static final _amberLine = PdfColor.fromHex('ECDCA8');
  static final _headerBg = PdfColor.fromHex('0E1A24');
  static final _headerAccent = PdfColor.fromHex('2BB6C4');
  static final _mapBg = PdfColor.fromHex('F3F6F8');
  static final _mapRoad = PdfColor.fromHex('DDE4EA');
  static final _mediaBg = PdfColor.fromHex('D5E0E6');

  static const _docType = 'Registro de Ocorrencia';
  static const _systemName = 'Sistema Canil K9 GCM';
  static const _verificationBaseUrl = String.fromEnvironment(
    'K9_VERIFICATION_BASE_URL',
    defaultValue: 'https://canilk9.limeira.sp.gov.br/v',
  );
  static const _pagePadding = 30.0;
  static const _contentGap = 18.0;

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
      title: 'Registro de Ocorrencia - ${occurrence.typeName}',
    );
    final fonts = await PdfFonts.load();
    final docId = _buildDocId(occurrence);
    final sortedEvents = [...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Agrupar eventos por local
    final locations = OccurrenceLocationService.clusterEventsSync(sortedEvents);

    // Download de mídia em paralelo (fotos são leves individualmente)
    final media = await _buildMediaItems(sortedEvents);

    // Mapas sequenciais para evitar pico de memória (tiles + composição)
    final staticMapImage = await _buildStaticMapImage(occurrence);
    final displacementMapImage = await _buildDisplacementMapImage(locations);

    // Carregar aditamentos (se houver)
    final amendments = await AmendmentRepository().listByOccurrence(
      occurrence.id,
    );

    final context = _OccurrencePdfContext(
      occurrence: occurrence,
      events: sortedEvents,
      dog: dog,
      handlerName: handlerName,
      handlerRa: handlerRa,
      docId: docId,
      fonts: fonts,
      media: media,
      staticMapImage: staticMapImage,
      displacementMapImage: displacementMapImage,
      locations: locations,
      amendments: amendments,
    );

    pdf
      ..addPage(_page(context, 1, _buildCoverPage))
      ..addPage(_page(context, 2, _buildLocationPage));

    // Conteúdo fluido — timeline, mídias, relatório e validação paginam automaticamente
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(top: 0, left: 0, right: 0, bottom: 0),
        header: (_) => _header(context, 0),
        footer: (_) => _footer(false),
        build: (_) => [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(
              _pagePadding,
              21,
              _pagePadding,
              0,
            ),
            child: _buildDisplacementSection(context),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(
              _pagePadding,
              21,
              _pagePadding,
              0,
            ),
            child: _buildTimelinePage(context),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(
              _pagePadding,
              21,
              _pagePadding,
              0,
            ),
            child: _buildMediaPage(context),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(
              _pagePadding,
              21,
              _pagePadding,
              0,
            ),
            child: _buildReportPage(context),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(
              _pagePadding,
              21,
              _pagePadding,
              0,
            ),
            child: _buildValidationPage(context),
          ),
          if (context.amendments.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(
                _pagePadding,
                21,
                _pagePadding,
                0,
              ),
              child: _buildAmendmentsSection(context),
            ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Page _page(
    _OccurrencePdfContext ctx,
    int pageNumber,
    pw.Widget Function(_OccurrencePdfContext ctx) bodyBuilder,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Container(
        color: _paper,
        child: pw.Column(
          children: [
            _header(ctx, pageNumber),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(
                  _pagePadding,
                  21,
                  _pagePadding,
                  0,
                ),
                child: bodyBuilder(ctx),
              ),
            ),
            _footer(pageNumber == 1),
          ],
        ),
      ),
    );
  }

  Future<List<_PdfMediaItem>> _buildMediaItems(
    List<OccurrenceEvent> events,
  ) async {
    final rawItems = <({int index, String url, OccurrenceEvent event})>[];
    var index = 1;
    for (final event in events) {
      for (final url in event.photoUrls) {
        rawItems.add((index: index++, url: url, event: event));
      }
    }

    final client = http.Client();
    final media = <_PdfMediaItem>[];
    try {
      for (final item in rawItems) {
        media.add(
          _PdfMediaItem(
            number: item.index,
            url: item.url,
            image: await _loadOptimizedPhoto(client, item.url),
            event: item.event,
          ),
        );
      }
    } finally {
      client.close();
    }

    return media;
  }

  Future<pw.ImageProvider?> _loadOptimizedPhoto(
    http.Client client,
    String url,
  ) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !trimmedUrl.startsWith('http')) return null;

    try {
      final response = await client
          .get(Uri.parse(trimmedUrl))
          .timeout(_photoRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final optimized = _optimizePhotoForPdf(response.bodyBytes);
      if (optimized == null) return null;
      return pw.MemoryImage(optimized);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _optimizePhotoForPdf(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final oriented = img.bakeOrientation(decoded);
    final longestSide = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    final output = longestSide > _pdfPhotoMaxDimension
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? _pdfPhotoMaxDimension
                : null,
            height: oriented.height > oriented.width
                ? _pdfPhotoMaxDimension
                : null,
            interpolation: img.Interpolation.average,
          )
        : oriented;

    return Uint8List.fromList(
      img.encodeJpg(output, quality: _pdfPhotoJpegQuality),
    );
  }

  /// Gera mapa estático OSM para a página de localização (ponto único).
  Future<pw.ImageProvider?> _buildStaticMapImage(Occurrence occurrence) async {
    final lat = occurrence.gpsLat;
    final lng = occurrence.gpsLng;
    if (lat == null || lng == null) return null;

    final generator = OsmStaticMapGenerator();
    try {
      final bytes = await generator.generateSinglePointMap(lat, lng);
      if (bytes == null) return null;
      return pw.MemoryImage(bytes);
    } finally {
      generator.dispose();
    }
  }

  /// Gera mapa estático OSM com múltiplos pinos numerados para o deslocamento.
  Future<pw.ImageProvider?> _buildDisplacementMapImage(
    List<OccurrenceLocation> locations,
  ) async {
    if (locations.isEmpty) return null;

    final generator = OsmStaticMapGenerator();
    try {
      final bytes = await generator.generateDisplacementMap(locations);
      if (bytes == null) return null;
      return pw.MemoryImage(bytes);
    } finally {
      generator.dispose();
    }
  }

  String _buildDocId(Occurrence occ) {
    final seq = occ.id.length >= 4
        ? occ.id.substring(0, 4).toUpperCase()
        : occ.id.toUpperCase().padRight(4, '0');
    return 'REG ${occ.startedAt.year}/${_two(occ.startedAt.month)}/$seq-K9';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
  String _formatDate(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
  String _formatShortDate(DateTime value) => DateFormat('dd/MM').format(value);
  String _formatTime(DateTime value) => DateFormat('HH:mm').format(value);
  String _formatDateTime(DateTime value) =>
      DateFormat('dd/MM/yyyy HH:mm').format(value);

  DateTime _operationStart(_OccurrencePdfContext ctx) {
    if (ctx.events.isEmpty) return ctx.occurrence.startedAt;
    final sorted = List<OccurrenceEvent>.from(ctx.events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return sorted.first.timestamp;
  }

  DateTime _operationEnd(_OccurrencePdfContext ctx) {
    if (ctx.occurrence.finalizedAt != null) return ctx.occurrence.finalizedAt!;
    if (ctx.events.isEmpty) return ctx.occurrence.updatedAt;
    final sorted = List<OccurrenceEvent>.from(ctx.events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return sorted.last.timestamp;
  }

  String _durationLabel(DateTime start, DateTime end) {
    final diff = end.difference(start);
    final totalMinutes = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${_two(minutes)}min';
    return '$totalMinutes min';
  }

  String _timeWindow(_OccurrencePdfContext ctx) {
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    return '${_formatTime(start)} -> ${_formatTime(end)}';
  }

  String _eventTitle(OccurrenceEvent event) {
    if (event.title?.trim().isNotEmpty ?? false) {
      return event.title!.toUpperCase();
    }
    return switch (event.category) {
      OccurrenceEventCategory.opening => 'REGISTRO DE OCORRÊNCIA ABERTO',
      OccurrenceEventCategory.arrival => 'BUSCA / INVESTIGAÇÃO',
      _ => event.category.label.toUpperCase(),
    };
  }

  String _statusLabel(Occurrence occurrence) => switch (occurrence.status) {
    OccurrenceStatus.finalized =>
      occurrence.team.length > 1 ? 'Finalizado\nco-assinado' : 'Finalizado',
    OccurrenceStatus.finalizedWithPending => 'Finalizado\ncom pendência',
    OccurrenceStatus.awaitingSignatures => 'Aguardando\nassinaturas',
    OccurrenceStatus.finalizing => 'Em finalização',
    OccurrenceStatus.canceled => 'Cancelado',
    OccurrenceStatus.inProgress => 'Em andamento',
  };

  int _boCount(Occurrence occurrence) =>
      occurrence.results.contains(OccurrenceResult.boCreated) ? 1 : 0;

  String _locationMain(Occurrence occurrence) {
    final raw = occurrence.locationAddress?.trim();
    if (raw == null || raw.isEmpty) return 'Endereco nao informado';
    final parts = raw.split(',').map((part) => part.trim()).toList();
    return parts.firstWhere((part) => part.isNotEmpty, orElse: () => raw);
  }

  String _locationSub(Occurrence occurrence) {
    final raw = occurrence.locationAddress?.trim();
    if (raw == null || raw.isEmpty) return 'Limeira/SP';
    final parts = raw.split(',').map((part) => part.trim()).toList();
    if (parts.length <= 1) return 'Limeira/SP';
    return parts.skip(1).where((part) => part.isNotEmpty).take(2).join(' - ');
  }

  String _gpsText(double? lat, double? lng, {int precision = 6}) {
    if (lat == null || lng == null) return 'GPS indisponivel';
    return '${lat.toStringAsFixed(precision)}, ${lng.toStringAsFixed(precision)}';
  }

  String _accuracyText(double? accuracy) {
    if (accuracy == null) return 'N/I';
    return '+/-${accuracy.toStringAsFixed(0)}m';
  }

  // ---------------------------------------------------------------------------
  // Shared visual primitives
  // ---------------------------------------------------------------------------

  pw.Widget _header(_OccurrencePdfContext ctx, int pageNumber) {
    final f = ctx.fonts;
    return pw.Column(
      children: [
        pw.Container(
          height: 72,
          padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          color: _headerBg,
          child: pw.Row(
            children: [
              _crest(f),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'GUARDA CIVIL MUNICIPAL DE LIMEIRA',
                      style: pw.TextStyle(
                        font: f.bold,
                        color: PdfColors.white,
                        fontSize: 13.5,
                        letterSpacing: 0.3,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'CANIL K9 - SECAO OPERACIONAL',
                      style: pw.TextStyle(
                        font: f.medium,
                        color: _headerAccent,
                        fontSize: 8,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    ctx.docId,
                    style: pw.TextStyle(
                      font: f.bold,
                      color: PdfColors.white,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    pageNumber > 0 ? 'PAGINA $pageNumber' : '',
                    style: pw.TextStyle(
                      font: f.medium,
                      color: PdfColor.fromHex('8AA0AD'),
                      fontSize: 7.5,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.Row(
          children: [
            pw.Container(width: 260, height: 2.3, color: _cyan),
            pw.Container(width: 180, height: 2.3, color: _green),
            pw.Expanded(child: pw.Container(height: 2.3, color: _headerBg)),
          ],
        ),
      ],
    );
  }

  pw.Widget _footer(bool cover) {
    return pw.Container(
      height: 38,
      padding: const pw.EdgeInsets.symmetric(horizontal: 30),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8)),
      ),
      child: pw.Row(
        children: [
          _smallShield(_inkFaint),
          pw.SizedBox(width: 7),
          pw.Text(
            'Documento gerado automaticamente pelo $_systemName',
            style: pw.TextStyle(fontSize: 7.5, color: _inkFaint),
          ),
          pw.Spacer(),
          pw.Text(
            cover
                ? 'DOCUMENTO DIGITAL - assinatura e integridade na ultima pagina'
                : 'DOCUMENTO DIGITAL - nao impresso',
            style: pw.TextStyle(
              fontSize: 7.5,
              color: _inkFaint,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _crest(PdfFonts fonts) {
    return pw.Container(
      width: 32,
      height: 38,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('13242F'),
        border: pw.Border.all(color: _headerAccent, width: 1.1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Container(
            width: 14,
            height: 14,
            decoration: pw.BoxDecoration(
              color: _headerAccent,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                'K',
                style: pw.TextStyle(
                  font: fonts.black,
                  fontSize: 8,
                  color: PdfColor.fromHex('13242F'),
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'K9',
            style: pw.TextStyle(
              font: fonts.black,
              color: PdfColors.white,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _smallShield(PdfColor color) {
    return pw.Container(
      width: 11,
      height: 12,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
    );
  }

  pw.Widget _sectionLabel(String label, PdfFonts fonts) {
    return pw.Row(
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            font: fonts.bold,
            color: _inkSoft,
            fontSize: 8.2,
            letterSpacing: 1.5,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(child: pw.Container(height: 0.8, color: _line)),
      ],
    );
  }

  pw.Widget _contextBar(_OccurrencePdfContext ctx, {bool status = false}) {
    final start = _operationStart(ctx);
    final cells = <_KeyValue>[
      _KeyValue('Natureza', ctx.occurrence.typeName),
      _KeyValue('Data', _formatDate(start), mono: true),
      _KeyValue('Horario', _timeWindow(ctx), mono: true),
      _KeyValue(
        status ? 'Status' : 'Duracao',
        status
            ? _statusLabel(ctx.occurrence)
            : _durationLabel(start, _operationEnd(ctx)),
        mono: !status,
        green: status && ctx.occurrence.status.isClosed,
      ),
    ];
    return _gridBox(
      columns: [2.0, 1.0, 1.25, 1.0],
      children: cells.map((cell) => _contextCell(cell, ctx.fonts)).toList(),
    );
  }

  pw.Widget _contextCell(_KeyValue value, PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tinyLabel(value.label, fonts),
          pw.SizedBox(height: 4),
          pw.Text(
            value.value,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              font: value.mono ? fonts.regular : fonts.bold,
              fontSize: 9.8,
              color: value.green ? _green : _ink,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tinyLabel(String text, PdfFonts fonts, {PdfColor? color}) {
    return pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        font: fonts.bold,
        fontSize: 6.7,
        letterSpacing: 0.9,
        color: color ?? _inkFaint,
      ),
    );
  }

  pw.TextStyle _mono(PdfFonts fonts, {double size = 9, PdfColor? color}) {
    return pw.TextStyle(
      font: fonts.regular,
      fontSize: size,
      color: color ?? _ink,
    );
  }

  pw.TextStyle _body(PdfFonts fonts, {double size = 9, PdfColor? color}) {
    return pw.TextStyle(
      font: fonts.regular,
      fontSize: size,
      color: color ?? _ink,
      lineSpacing: 2,
    );
  }

  pw.TextStyle _bodyBold(PdfFonts fonts, {double size = 9, PdfColor? color}) {
    return pw.TextStyle(font: fonts.bold, fontSize: size, color: color ?? _ink);
  }

  pw.Widget _gridBox({
    required List<double> columns,
    required List<pw.Widget> children,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            pw.Expanded(flex: (columns[i] * 100).round(), child: children[i]),
            if (i < children.length - 1)
              pw.Container(width: 0.8, height: 48, color: _line),
          ],
        ],
      ),
    );
  }

  pw.Widget _roundedCard({
    required pw.Widget child,
    PdfColor? border,
    PdfColor? background,
    double radius = 8,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(12),
  }) {
    return pw.Container(
      padding: padding,
      decoration: pw.BoxDecoration(
        color: background ?? _paper,
        border: pw.Border.all(color: border ?? _line),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(radius)),
      ),
      child: child,
    );
  }

  pw.Widget _avatar(String top, PdfFonts fonts, {PdfColor? color}) {
    final c = color ?? _cyan;
    return pw.Container(
      width: 48,
      height: 48,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('EEF2F5'),
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: c, width: 1.4),
      ),
      child: pw.Center(
        child: pw.Text(
          top,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 7,
            lineSpacing: 1,
            color: c == _cyan ? _cyanDeep : _inkFaint,
          ),
        ),
      ),
    );
  }

  pw.Widget _binomio(_OccurrencePdfContext ctx, {bool compact = false}) {
    final f = ctx.fonts;
    return _roundedCard(
      padding: pw.EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 12 : 15,
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Row(
              children: [
                _avatar('FOTO\nK9', f),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _tinyLabel('Cao K9', f, color: _cyanDeep),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      ctx.dog.name,
                      style: _bodyBold(f, size: compact ? 11 : 12),
                    ),
                    pw.Text(
                      'Raca: ${ctx.dog.breed}\nMatricula: ${ctx.dog.registrationNumber ?? 'N/I'}',
                      style: _body(f, size: 8, color: _inkSoft),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.Container(
            width: 20,
            alignment: pw.Alignment.center,
            child: pw.Text('<>', style: _mono(f, color: _inkFaint)),
          ),
          pw.Expanded(
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _tinyLabel('Condutor', f, color: _cyanDeep),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      ctx.handlerName,
                      style: _bodyBold(f, size: compact ? 11 : 12),
                    ),
                    pw.Text(
                      'RA: ${ctx.handlerRa}\nUnidade: Canil K9 - Limeira',
                      textAlign: pw.TextAlign.right,
                      style: _body(f, size: 8, color: _inkSoft),
                    ),
                  ],
                ),
                pw.SizedBox(width: 10),
                _avatar('FOTO\nGCM', f),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _mapCanvas(
    _OccurrencePdfContext ctx, {
    required double height,
    bool detailed = false,
  }) {
    final f = ctx.fonts;
    return pw.Container(
      height: height,
      color: _mapBg,
      child: pw.Stack(
        children: [
          if (ctx.staticMapImage != null)
            pw.Positioned.fill(
              child: pw.Image(ctx.staticMapImage!, fit: pw.BoxFit.cover),
            )
          else ...[
            _mapRoadLine(left: 0, top: height * .18, width: 535, height: 5),
            _mapRoadLine(left: 0, top: height * .44, width: 535, height: 7),
            _mapRoadLine(left: 0, top: height * .72, width: 535, height: 5),
            _mapRoadLine(left: 125, top: 0, width: 5, height: height),
            _mapRoadLine(left: 255, top: 0, width: 7, height: height),
            _mapRoadLine(left: 385, top: 0, width: 5, height: height),
            _roadLabel(
              'R. Frederico Rotulo',
              left: 18,
              top: height * .39,
              fonts: f,
            ),
            _roadLabel('R. Guido Orsi', left: 280, top: height * .13, fonts: f),
            _roadLabel(
              'R. Jose Brunatti',
              left: 42,
              top: height * .8,
              fonts: f,
            ),
            _roadLabel(
              'E. E. Jd. Ouro Verde',
              left: 365,
              top: height * .56,
              fonts: f,
            ),
          ],
          pw.Positioned(
            top: 10,
            right: 12,
            child: pw.Column(
              children: [
                pw.Text('N', style: _mono(f, size: 8, color: _inkSoft)),
                pw.Text('^', style: _mono(f, size: 11, color: _cyan)),
              ],
            ),
          ),
          if (detailed)
            pw.Positioned(
              bottom: 12,
              left: 12,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '0 ---- 100m',
                    style: _mono(f, size: 7, color: _inkSoft),
                  ),
                  pw.Container(
                    width: 60,
                    height: 3,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: _inkSoft),
                        left: pw.BorderSide(color: _inkSoft),
                        right: pw.BorderSide(color: _inkSoft),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (ctx.staticMapImage == null)
            pw.Positioned(
              left: 260,
              top: height * .45,
              child: pw.Column(
                children: [
                  pw.Container(
                    width: 16,
                    height: 16,
                    decoration: pw.BoxDecoration(
                      color: _cyan,
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: PdfColors.white, width: 2),
                    ),
                  ),
                  pw.Container(
                    width: 36,
                    height: 7,
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0x330A8E9D),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _mapRoadLine({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Container(width: width, height: height, color: _mapRoad),
    );
  }

  pw.Widget _roadLabel(
    String text, {
    required double left,
    required double top,
    required PdfFonts fonts,
  }) {
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Text(
        text,
        style: _body(fonts, size: 6.5, color: PdfColor.fromHex('97A6B2')),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page 1
  // ---------------------------------------------------------------------------

  pw.Widget _buildCoverPage(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.only(left: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(color: _cyan, width: 2.5),
                      ),
                    ),
                    child: pw.Text(
                      _docType.toUpperCase(),
                      style: pw.TextStyle(
                        font: f.bold,
                        fontSize: 8,
                        letterSpacing: 1.8,
                        color: _cyanDeep,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    ctx.occurrence.typeName,
                    maxLines: 2,
                    style: pw.TextStyle(
                      font: f.black,
                      color: _ink,
                      fontSize: 26,
                      lineSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            _statusChip(ctx),
          ],
        ),
        pw.SizedBox(height: _contentGap),
        _gridBox(
          columns: [1, 1, 1],
          children: [
            _metaCell('Data', _formatDate(start), f),
            _metaCell(
              'Janela da operacao',
              '${_formatTime(start)} -> ${_formatTime(end)}',
              f,
              note: 'do 1o evento a finalizacao',
            ),
            _metaCell('Duracao', _durationLabel(start, end), f),
          ],
        ),
        pw.SizedBox(height: _contentGap),
        _mapCard(ctx, height: 178),
        pw.SizedBox(height: _contentGap),
        _sectionLabel('Resumo operacional', f),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            _statCard(
              'TEMPO',
              _durationLabel(start, end),
              'Duracao da operacao',
              f,
            ),
            pw.SizedBox(width: 9),
            _statCard('EV', '${ctx.events.length}', 'Eventos registrados', f),
            pw.SizedBox(width: 9),
            _statCard('MID', '${ctx.media.length}', 'Midias anexadas', f),
            pw.SizedBox(width: 9),
            _statCard('BO', '${_boCount(ctx.occurrence)}', 'BO registrado', f),
          ],
        ),
        pw.SizedBox(height: _contentGap),
        _sectionLabel('Binomio responsavel', f),
        pw.SizedBox(height: 10),
        _binomio(ctx),
      ],
    );
  }

  pw.Widget _statusChip(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final label = _statusLabel(ctx.occurrence).toUpperCase();
    return pw.Container(
      width: 126,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _greenBg,
        border: pw.Border.all(color: _greenLine),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(
                  color: _green,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Text(label, style: _bodyBold(f, size: 9, color: _green)),
            ],
          ),
          pw.SizedBox(height: 5),
          _tinyLabel('Sincronizado', f),
          pw.SizedBox(height: 2),
          pw.Text(
            _formatDateTime(ctx.occurrence.updatedAt),
            style: _mono(f, size: 7.5, color: _inkSoft),
          ),
        ],
      ),
    );
  }

  pw.Widget _metaCell(
    String label,
    String value,
    PdfFonts fonts, {
    String? note,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tinyLabel(label, fonts),
          pw.SizedBox(height: 5),
          pw.Text(value, style: _mono(fonts, size: 12.5)),
          if (note != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(note, style: _body(fonts, size: 7.5, color: _inkFaint)),
          ],
        ],
      ),
    );
  }

  pw.Widget _mapCard(_OccurrencePdfContext ctx, {required double height}) {
    final f = ctx.fonts;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              children: [
                pw.Text('P', style: _bodyBold(f, size: 9, color: _cyanDeep)),
                pw.SizedBox(width: 6),
                pw.Text(
                  'LOCAL DA OCORRENCIA',
                  style: _bodyBold(f, size: 8, color: _cyanDeep),
                ),
              ],
            ),
          ),
          _mapCanvas(ctx, height: height),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('FAFCFD'),
              border: pw.Border(top: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              children: [
                pw.Text('P', style: _bodyBold(f, size: 10, color: _cyan)),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _locationMain(ctx.occurrence),
                        style: _bodyBold(f, size: 10.5),
                      ),
                      pw.Text(
                        _locationSub(ctx.occurrence),
                        style: _body(f, size: 8, color: _inkSoft),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  _gpsText(ctx.occurrence.gpsLat, ctx.occurrence.gpsLng),
                  style: _mono(f, size: 8, color: _cyanDeep),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _statCard(
    String icon,
    String number,
    String caption,
    PdfFonts fonts,
  ) {
    return pw.Expanded(
      child: _roundedCard(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: pw.Column(
          children: [
            pw.Text(icon, style: _bodyBold(fonts, size: 9, color: _cyan)),
            pw.SizedBox(height: 6),
            pw.Text(
              number,
              style: pw.TextStyle(font: fonts.black, fontSize: 20, color: _ink),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              caption,
              textAlign: pw.TextAlign.center,
              style: _body(fonts, size: 7.5, color: _inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page 2
  // ---------------------------------------------------------------------------

  pw.Widget _buildLocationPage(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _contextBar(ctx),
        pw.SizedBox(height: 18),
        _sectionLabel('Localizacao e dados operacionais', f),
        pw.SizedBox(height: 11),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 7,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                ),
                child: pw.Column(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: _line)),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Text(
                            'P',
                            style: _bodyBold(f, size: 9, color: _cyanDeep),
                          ),
                          pw.SizedBox(width: 6),
                          pw.Text(
                            'MAPA DA OCORRENCIA',
                            style: _bodyBold(f, size: 8, color: _cyanDeep),
                          ),
                        ],
                      ),
                    ),
                    _mapCanvas(ctx, height: 230, detailed: true),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                children: [
                  _infoBox('Endereco', [
                    _locationMain(ctx.occurrence),
                    _locationSub(ctx.occurrence),
                    'Limeira/SP',
                  ], f),
                  pw.SizedBox(height: 10),
                  _coordinateBox(ctx),
                  pw.SizedBox(height: 10),
                  _gpsSignal(ctx),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        _sectionLabel('Dados administrativos', f),
        pw.SizedBox(height: 10),
        _gridBox(
          columns: [1, 1, 1, 1, 1],
          children: [
            _adminCell(
              'Turno / Plantao',
              _shortId(ctx.occurrence.shiftId),
              f,
              mono: true,
            ),
            _adminCell('Data', _formatDate(start), f, mono: true),
            _adminCell('Inicio', _formatTime(start), f, mono: true),
            _adminCell('Termino', _formatTime(end), f, mono: true),
            _adminCell(
              'Duracao reg.',
              _durationLabel(start, end),
              f,
              mono: true,
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        _gridBox(
          columns: [1, 1],
          children: [
            _adminCell('Prioridade', 'Normal', f, green: true),
            _adminCell(
              'Status do registro - sincronizacao',
              '${_statusLabel(ctx.occurrence)} - sincronizado ${_formatTime(ctx.occurrence.updatedAt)}',
              f,
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        _sectionLabel('Binomio responsavel', f),
        pw.SizedBox(height: 10),
        _binomio(ctx, compact: true),
      ],
    );
  }

  /// Seção de mapa de deslocamento com legenda numerada.
  /// Se não houver imagem (sem API key ou sem coordenadas), retorna vazio.
  pw.Widget _buildDisplacementSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final locations = ctx.locations;

    // Se não há locais com coordenada, omitir seção
    if (locations.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header da seção
        pw.Row(
          children: [
            _sectionLabel('Mapa de deslocamento', f),
            pw.Spacer(),
            pw.Text(
              '${locations.length} ${locations.length == 1 ? 'local' : 'locais'}',
              style: _body(f, size: 8, color: _inkSoft),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        // Mapa estático (se disponível)
        if (ctx.displacementMapImage != null)
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.ClipRRect(
              horizontalRadius: 8,
              verticalRadius: 8,
              child: pw.Image(
                ctx.displacementMapImage!,
                width: double.infinity,
                height: 200,
                fit: pw.BoxFit.cover,
              ),
            ),
          ),
        if (ctx.displacementMapImage == null)
          pw.Container(
            height: 60,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              color: PdfColor.fromHex('#0A1A20'),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              'Mapa indisponivel (sem conexao ao gerar o PDF)',
              style: _body(f, size: 8, color: _inkSoft),
            ),
          ),
        pw.SizedBox(height: 12),
        // Legenda numerada
        ...locations.map((loc) {
          final isFirst = loc.index == 1;
          final pinColor = isFirst
              ? PdfColor.fromHex('#2ECC71')
              : PdfColor.fromHex('#4DD0E1');
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: [
                // Pino numerado
                pw.Container(
                  width: 18,
                  height: 18,
                  decoration: pw.BoxDecoration(
                    color: pinColor,
                    shape: pw.BoxShape.circle,
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    '${loc.index}',
                    style: _bodyBold(
                      f,
                      size: 8,
                      color: PdfColor.fromHex('#04181D'),
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                // Label do local
                pw.Expanded(
                  child: pw.Text(
                    loc.label,
                    style: _bodyBold(f, size: 9, color: _ink),
                  ),
                ),
                // Horário de chegada
                pw.Text(
                  _formatTime(loc.arrivedAt),
                  style: _body(f, size: 8, color: _inkSoft),
                ),
              ],
            ),
          );
        }),
        pw.SizedBox(height: 6),
        pw.Text(
          'Cada parada marca o local onde uma ou mais acoes foram registradas, na ordem em que aconteceram.',
          style: _body(f, size: 7.5, color: _inkSoft),
        ),
      ],
    );
  }

  pw.Widget _infoBox(String title, List<String> lines, PdfFonts fonts) {
    return _roundedCard(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: _bodyBold(fonts, size: 8, color: _cyanDeep),
          ),
          pw.SizedBox(height: 8),
          for (var i = 0; i < lines.length; i++)
            pw.Text(
              lines[i],
              style: i == 0
                  ? _bodyBold(fonts, size: 10)
                  : _body(fonts, size: 9, color: _inkSoft),
            ),
        ],
      ),
    );
  }

  pw.Widget _coordinateBox(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    return _roundedCard(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'COORDENADAS GPS',
            style: _bodyBold(f, size: 8, color: _cyanDeep),
          ),
          pw.SizedBox(height: 8),
          _coordRow(
            'Latitude',
            ctx.occurrence.gpsLat?.toStringAsFixed(6) ?? 'N/I',
            f,
          ),
          _coordRow(
            'Longitude',
            ctx.occurrence.gpsLng?.toStringAsFixed(6) ?? 'N/I',
            f,
          ),
          _coordRow('Precisao', _accuracyText(ctx.occurrence.gpsAccuracy), f),
        ],
      ),
    );
  }

  pw.Widget _coordRow(String key, String value, PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _lineSoft, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: _tinyLabel(key, fonts)),
          pw.Text(value, style: _mono(fonts, size: 8.4)),
        ],
      ),
    );
  }

  pw.Widget _gpsSignal(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final accuracy = ctx.occurrence.gpsAccuracy;
    final strong = accuracy != null && accuracy <= 50;
    final color = strong ? _green : _amber;
    final bg = strong ? _greenBg : _amberBg;
    final line = strong ? _greenLine : _amberLine;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border.all(color: line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
      ),
      child: pw.Row(
        children: [
          pw.Text('GPS', style: _bodyBold(f, size: 9, color: color)),
          pw.SizedBox(width: 8),
          pw.Text(
            'Sinal GPS - ${strong ? 'FORTE' : 'PRECISAO LIMITADA'}',
            style: _bodyBold(f, size: 8, color: color),
          ),
          pw.Spacer(),
          for (var i = 0; i < 4; i++)
            pw.Container(
              width: 3,
              height: 5.0 + (i * 3),
              margin: const pw.EdgeInsets.only(left: 2),
              color: color,
            ),
        ],
      ),
    );
  }

  pw.Widget _adminCell(
    String label,
    String value,
    PdfFonts fonts, {
    bool mono = false,
    bool green = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tinyLabel(label, fonts),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            maxLines: 2,
            style: pw.TextStyle(
              font: mono ? fonts.regular : fonts.bold,
              fontSize: 8.5,
              color: green ? _green : _ink,
            ),
          ),
        ],
      ),
    );
  }

  String _shortId(String value) {
    if (value.trim().isEmpty) return 'N/I';
    return value.length > 8 ? value.substring(0, 8) : value;
  }

  // ---------------------------------------------------------------------------
  // Page 3
  // ---------------------------------------------------------------------------

  pw.Widget _buildTimelinePage(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    final entries = ctx.events;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Linha do tempo operacional',
          style: pw.TextStyle(font: f.black, fontSize: 16, color: _ink),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Sequencia cronologica dos eventos registrados na ocorrencia',
          style: _body(f, size: 8.8, color: _inkSoft),
        ),
        pw.SizedBox(height: 16),
        _gridBox(
          columns: [1, 1, 1],
          children: [
            _timelineSummary('Inicio da atividade', _formatTime(start), f),
            _timelineSummary(
              'Eventos registrados',
              '${ctx.events.length} acoes',
              f,
            ),
            _timelineSummary(
              'Duracao total',
              '${_durationLabel(start, end)}  ${_formatTime(start)} -> ${_formatTime(end)}',
              f,
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        if (entries.isEmpty)
          _emptyBox('Nenhum evento registrado na ocorrencia.', f)
        else
          ...entries.asMap().entries.map(
            (entry) => _timelineEvent(
              entry.value,
              f,
              first: entry.key == 0,
              last: entry.key == entries.length - 1,
            ),
          ),
        pw.SizedBox(height: 12),
        _timelineLegend(f),
      ],
    );
  }

  pw.Widget _timelineSummary(String key, String value, PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tinyLabel(key, fonts),
          pw.SizedBox(height: 5),
          pw.Text(value, style: _mono(fonts, size: 11.5)),
        ],
      ),
    );
  }

  pw.Widget _timelineEvent(
    OccurrenceEvent event,
    PdfFonts fonts, {
    required bool first,
    required bool last,
  }) {
    final color = _eventColor(event.category);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 48,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                _formatTime(event.timestamp),
                style: _mono(fonts, size: 10.5),
              ),
              pw.Text(
                _formatShortDate(event.timestamp),
                style: _mono(fonts, size: 7, color: _inkFaint),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Container(
          width: 22,
          child: pw.Column(
            children: [
              pw.Container(
                width: 20,
                height: 20,
                decoration: pw.BoxDecoration(
                  color: _paper,
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: color, width: 1.5),
                ),
                child: pw.Center(
                  child: pw.Text(
                    _eventMark(event.category),
                    style: _bodyBold(fonts, size: 7, color: color),
                  ),
                ),
              ),
              if (!last) pw.Container(width: 1.4, height: 50, color: _line),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.all(11),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: color, width: 2.5),
                top: pw.BorderSide(color: _line),
                right: pw.BorderSide(color: _line),
                bottom: pw.BorderSide(color: _line),
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _eventTitle(event),
                        style: _bodyBold(fonts, size: 10, color: color),
                      ),
                      if ((event.description ?? '').trim().isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          event.description!,
                          maxLines: 3,
                          style: _body(fonts, size: 8.7, color: _inkSoft),
                        ),
                      ],
                      pw.SizedBox(height: 5),
                      pw.Text(
                        _gpsText(event.gpsLat, event.gpsLng, precision: 5),
                        style: _mono(fonts, size: 7.5, color: _cyanDeep),
                      ),
                    ],
                  ),
                ),
                if (event.photoUrls.isNotEmpty) ...[
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        width: 90,
                        height: 50,
                        decoration: pw.BoxDecoration(
                          color: _mediaBg,
                          border: pw.Border.all(color: _line),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(6),
                          ),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            '${event.photoUrls.length} foto(s)',
                            style: _body(fonts, size: 7.5, color: _inkFaint),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'SINC ${_formatTime(event.updatedAt)}',
                        style: _bodyBold(fonts, size: 7, color: _green),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  PdfColor _eventColor(OccurrenceEventCategory category) => switch (category) {
    OccurrenceEventCategory.arrival => _amber,
    OccurrenceEventCategory.dogWork => _green,
    OccurrenceEventCategory.positiveIndication => _green,
    OccurrenceEventCategory.seizure => _green,
    OccurrenceEventCategory.closure => _green,
    _ => _cyan,
  };

  String _eventMark(OccurrenceEventCategory category) => switch (category) {
    OccurrenceEventCategory.opening => 'A',
    OccurrenceEventCategory.arrival => 'B',
    OccurrenceEventCategory.approach => 'AB',
    OccurrenceEventCategory.dogWork => 'K9',
    OccurrenceEventCategory.positiveIndication => 'IP',
    OccurrenceEventCategory.seizure => 'AP',
    OccurrenceEventCategory.closure => 'FN',
    _ => 'O',
  };

  pw.Widget _timelineLegend(PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line)),
      ),
      child: pw.Row(
        children: [
          _legendDot('Busca / Investigação', _amber, fonts),
          pw.SizedBox(width: 18),
          _legendDot('Registro / Abordagem', _cyan, fonts),
          pw.SizedBox(width: 18),
          _legendDot('Emprego / Resultado', _green, fonts),
        ],
      ),
    );
  }

  pw.Widget _legendDot(String label, PdfColor color, PdfFonts fonts) {
    return pw.Row(
      children: [
        pw.Container(
          width: 7,
          height: 7,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 5),
        pw.Text(label, style: _body(fonts, size: 7.8, color: _inkSoft)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Page 4
  // ---------------------------------------------------------------------------

  pw.Widget _buildMediaPage(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final visibleMedia = ctx.media;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Midias operacionais',
                    style: pw.TextStyle(
                      font: f.black,
                      fontSize: 16,
                      color: _ink,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Registros fotograficos e documentos relacionados a ocorrencia, com geolocalizacao quando disponivel.',
                    style: _body(f, size: 8.8, color: _inkSoft),
                  ),
                ],
              ),
            ),
            _mediaCount(ctx),
          ],
        ),
        pw.SizedBox(height: 18),
        if (visibleMedia.isEmpty)
          _emptyBox('Nenhuma midia anexada aos eventos desta ocorrencia.', f)
        else
          pw.Wrap(
            spacing: 12,
            runSpacing: 12,
            children: visibleMedia
                .map((item) => _mediaCard(item, ctx))
                .toList(),
          ),
        pw.SizedBox(height: 16),
        _sectionLabel('Anexos', f),
        pw.SizedBox(height: 10),
        _attachmentCard(ctx),
      ],
    );
  }

  pw.Widget _mediaCount(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        children: [
          _mediaCountCell('Fotos', ctx.media.length.toString(), f),
          _mediaCountCell('Video', '0', f),
          _mediaCountCell('Audios', '0', f),
          _mediaCountCell('Outros', _boCount(ctx.occurrence).toString(), f),
        ],
      ),
    );
  }

  pw.Widget _mediaCountCell(String label, String value, PdfFonts fonts) {
    return pw.Container(
      width: 47,
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(
            color: label == 'Fotos' ? PdfColors.white : _line,
          ),
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(font: fonts.black, fontSize: 13, color: _ink),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            label.toUpperCase(),
            style: _body(fonts, size: 6.3, color: _inkSoft),
          ),
        ],
      ),
    );
  }

  pw.Widget _mediaCard(_PdfMediaItem item, _OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final event = item.event;
    return pw.Container(
      width: 258,
      height: 198,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: pw.Row(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _line),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Text(
                    item.number.toString().padLeft(2, '0'),
                    style: _mono(f, size: 8, color: _cyanDeep),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _eventTitle(event),
                        maxLines: 1,
                        style: _bodyBold(f, size: 9.3),
                      ),
                      pw.Text(
                        'FOTO',
                        style: _body(f, size: 6.8, color: _inkFaint),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  _formatTime(event.timestamp),
                  style: _mono(f, size: 8.2, color: _inkSoft),
                ),
              ],
            ),
          ),
          pw.Container(
            height: 110,
            color: _mediaBg,
            child: pw.Stack(
              children: [
                if (item.image != null)
                  pw.Positioned.fill(
                    child: pw.Image(item.image!, fit: pw.BoxFit.cover),
                  )
                else
                  pw.Center(
                    child: pw.Text(
                      'imagem indisponivel',
                      style: _body(f, size: 8, color: _inkFaint),
                    ),
                  ),
                pw.Positioned(
                  right: 8,
                  top: 8,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _green,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      'SINC',
                      style: _bodyBold(f, size: 6.3, color: PdfColors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _lineSoft)),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${_locationMain(ctx.occurrence)}\n${_gpsText(event.gpsLat, event.gpsLng, precision: 5)}',
                    style: _body(f, size: 7.2, color: _inkSoft),
                  ),
                ),
                pw.Text(
                  _accuracyText(ctx.occurrence.gpsAccuracy),
                  style: _mono(f, size: 7, color: _inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _attachmentCard(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final boDetails = _detailsMap(
      ctx.occurrence.details,
      OccurrenceResult.boCreated,
    );
    final boNumber = boDetails?['bo_number']?.toString();
    final label = boNumber?.trim().isNotEmpty == true
        ? 'BO_$boNumber.pdf'
        : (_boCount(ctx.occurrence) > 0
              ? 'BO registrado - numero nao informado'
              : 'Sem anexos administrativos registrados');
    final meta = _boCount(ctx.occurrence) > 0
        ? 'Boletim de Ocorrencia - documento relacionado'
        : 'Nenhum arquivo anexado no modelo atual';

    return _roundedCard(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: pw.Row(
        children: [
          pw.Container(
            width: 32,
            height: 32,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('EEF2F5'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
            ),
            child: pw.Center(
              child: pw.Text(
                'PDF',
                style: _bodyBold(f, size: 8, color: _cyanDeep),
              ),
            ),
          ),
          pw.SizedBox(width: 11),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: _bodyBold(f, size: 9.4)),
                pw.Text(meta, style: _body(f, size: 7.5, color: _inkFaint)),
              ],
            ),
          ),
          pw.Text(
            _boCount(ctx.occurrence) > 0 ? 'anexo logico' : 'N/I',
            style: _mono(f, size: 8, color: _inkSoft),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Page 5
  // ---------------------------------------------------------------------------

  pw.Widget _buildReportPage(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final activeResults = ctx.occurrence.results
        .where((r) => r != OccurrenceResult.noOccurrence)
        .toList();
    final report = ctx.occurrence.finalReport?.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _contextBar(ctx, status: true),
        pw.SizedBox(height: 20),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Relato institucional', f),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('EEF9FB'),
                      border: pw.Border.all(color: PdfColor.fromHex('B8E3E8')),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(7),
                      ),
                    ),
                    child: pw.Text(
                      'TRANSCRICAO DE AUDIO - REVISADA PELO CONDUTOR',
                      style: _bodyBold(f, size: 7.8, color: _cyanDeep),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    padding: const pw.EdgeInsets.only(left: 11),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(color: _cyan, width: 2.4),
                      ),
                    ),
                    child: pw.Text(
                      report == null || report.isEmpty
                          ? 'Relato institucional nao registrado na finalizacao.'
                          : report,
                      textAlign: pw.TextAlign.justify,
                      style: _body(
                        f,
                        size: 9.5,
                        color: PdfColor.fromHex('26313C'),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('F7F9FB'),
                      border: pw.Border.all(color: _lineSoft),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(7),
                      ),
                    ),
                    child: pw.Text(
                      'Relato transcrito de audio gravado em campo, quando aplicavel, e revisado pelo condutor responsavel antes da finalizacao.',
                      style: _body(f, size: 7.8, color: _inkSoft),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Resultados', f),
                  pw.SizedBox(height: 12),
                  if (activeResults.isEmpty)
                    _resultCard(OccurrenceResult.noOccurrence, ctx)
                  else
                    ...activeResults.map((result) => _resultCard(result, ctx)),
                  if (ctx.media.isNotEmpty) _resultCard(null, ctx),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _resultCard(OccurrenceResult? result, _OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final title = result == null ? 'Midias registradas' : result.label;
    final desc = result == null
        ? '${ctx.media.length} foto(s) anexada(s) ao registro.'
        : _resultDescription(result, ctx.occurrence);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 9),
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 24,
            height: 24,
            decoration: pw.BoxDecoration(
              color: _greenBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Center(
              child: pw.Text(
                result == null ? 'M' : _resultMark(result),
                style: _bodyBold(f, size: 8, color: _green),
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title.toUpperCase(), style: _bodyBold(f, size: 8.8)),
                pw.SizedBox(height: 2),
                pw.Text(desc, style: _body(f, size: 7.8, color: _inkSoft)),
              ],
            ),
          ),
          pw.Text('OK', style: _bodyBold(f, size: 7.8, color: _green)),
        ],
      ),
    );
  }

  String _resultMark(OccurrenceResult result) => switch (result) {
    OccurrenceResult.drugSeized => 'D',
    OccurrenceResult.weaponSeized => 'A',
    OccurrenceResult.personDetained => 'P',
    OccurrenceResult.boCreated => 'BO',
    OccurrenceResult.supportProvided => 'AP',
    OccurrenceResult.noOccurrence => '0',
  };

  String _resultDescription(OccurrenceResult result, Occurrence occurrence) {
    final raw = _detailsValue(occurrence.details, result);
    final details = raw is Map ? Map<String, dynamic>.from(raw) : null;
    return switch (result) {
      OccurrenceResult.drugSeized => _drugDescription(raw),
      OccurrenceResult.weaponSeized => _weaponDescription(details),
      OccurrenceResult.personDetained => _personDescription(details),
      OccurrenceResult.boCreated => _boDescription(details),
      OccurrenceResult.supportProvided =>
        'Apoio prestado e registrado pela equipe.',
      OccurrenceResult.noOccurrence =>
        'Nada foi localizado ou constatado durante a atuacao.',
    };
  }

  dynamic _detailsValue(
    Map<String, dynamic>? details,
    OccurrenceResult result,
  ) {
    if (details == null) return null;
    final primary = details[result.toMap()];
    if (primary != null) return primary;
    return switch (result) {
      OccurrenceResult.drugSeized =>
        details['drogasApreendidas'] ?? details['drogas'],
      OccurrenceResult.weaponSeized => details['objetosApreendidos'],
      OccurrenceResult.personDetained => details['individuosDetidos'],
      OccurrenceResult.boCreated => details['bo'],
      OccurrenceResult.noOccurrence || OccurrenceResult.supportProvided => null,
    };
  }

  Map<String, dynamic>? _detailsMap(
    Map<String, dynamic>? details,
    OccurrenceResult result,
  ) {
    final raw = _detailsValue(details, result);
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  String _drugDescription(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      final entries = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((e) {
            final type = (e['type'] ?? e['tipo'] ?? 'substancia').toString();
            final amount = (e['weight_grams'] ?? e['quantidade'] ?? '')
                .toString();
            return amount.isEmpty ? type : '$type - $amount';
          })
          .join('; ');
      if (entries.isNotEmpty) return entries;
    }
    return 'Substancia analoga a entorpecente apreendida e registrada na ocorrencia.';
  }

  String _weaponDescription(Map<String, dynamic>? details) {
    final type = details?['type']?.toString();
    final quantity = details?['quantity']?.toString();
    if ((type ?? '').isEmpty && (quantity ?? '').isEmpty) {
      return 'Arma apreendida e registrada na ocorrencia.';
    }
    return [
      if ((type ?? '').isNotEmpty) type,
      if ((quantity ?? '').isNotEmpty) 'Quantidade: $quantity',
    ].join(' - ');
  }

  String _personDescription(Map<String, dynamic>? details) {
    final count = details?['count']?.toString();
    final referral = details?['referral']?.toString();
    if ((count ?? '').isEmpty && (referral ?? '').isEmpty) {
      return 'Pessoa conduzida a autoridade competente.';
    }
    return [
      if ((count ?? '').isNotEmpty) '$count pessoa(s)',
      if ((referral ?? '').isNotEmpty) referral,
    ].join(' - ');
  }

  String _boDescription(Map<String, dynamic>? details) {
    final number = details?['bo_number']?.toString();
    final type = details?['bo_type']?.toString();
    if ((number ?? '').isEmpty && (type ?? '').isEmpty) {
      return 'Boletim de ocorrencia registrado.';
    }
    return [
      if ((number ?? '').isNotEmpty) 'Numero: $number',
      if ((type ?? '').isNotEmpty) type,
    ].join(' - ');
  }

  // ---------------------------------------------------------------------------
  // Page 6
  // ---------------------------------------------------------------------------

  pw.Widget _buildValidationPage(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final createdAt = ctx.occurrence.finalizedAt ?? ctx.occurrence.updatedAt;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _contextBar(ctx, status: true),
        pw.SizedBox(height: 14),
        _sectionLabel('Integridade do documento', f),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _hashBox(ctx)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _verificationBox(ctx)),
          ],
        ),
        if (_shouldShowTeamAndSignatures(ctx)) ...[
          pw.SizedBox(height: 16),
          _buildTeamAndSignaturesSection(ctx),
        ],
        pw.SizedBox(height: 14),
        pw.Container(height: 1, color: _line),
        pw.SizedBox(height: 11),
        pw.Wrap(
          spacing: 24,
          runSpacing: 10,
          children: [
            _docInfo('ID do documento', ctx.docId, f, mono: true),
            _docInfo('Tipo', 'Registro Operacional K9', f),
            _docInfo(
              'Versão',
              'hash v${ctx.occurrence.hashVersion ?? 2}',
              f,
              mono: true,
            ),
            _docInfo('Criado em', _formatDateTime(createdAt), f, mono: true),
            _docInfo(
              'Sincronizado',
              _formatDateTime(ctx.occurrence.updatedAt),
              f,
              mono: true,
            ),
            _docInfo('Sistema', 'Canil K9 - GCM Limeira', f),
          ],
        ),
      ],
    );
  }

  bool _shouldShowTeamAndSignatures(_OccurrencePdfContext ctx) {
    return ctx.occurrence.team.length > 1 ||
        ctx.occurrence.signatures.isNotEmpty ||
        ctx.occurrence.status == OccurrenceStatus.finalizedWithPending;
  }

  pw.Widget _buildTeamAndSignaturesSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final team = _orderedTeam(ctx);
    final signedSignatures = _signedSignatures(ctx);
    final pendingItems = _pendingSignatureItems(ctx, team);
    final hasPending =
        ctx.occurrence.status == OccurrenceStatus.finalizedWithPending &&
        pendingItems.isNotEmpty;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionLabel('Equipe e assinaturas', f),
        pw.SizedBox(height: 5),
        pw.Text(
          'Este registro foi co-assinado pelos integrantes abaixo, atestando presença no fato narrado.',
          style: _body(f, size: 8, color: _inkFaint),
        ),
        pw.SizedBox(height: 10),
        _teamTable(ctx, team),
        pw.SizedBox(height: 10),
        if (signedSignatures.isEmpty)
          _emptyBox('Nenhuma co-assinatura registrada para esta ocorrência.', f)
        else
          _signatureTable(ctx, signedSignatures),
        if (hasPending) ...[
          pw.SizedBox(height: 10),
          _pendingSignaturesBlock(ctx, pendingItems),
        ],
      ],
    );
  }

  List<OccurrenceTeamMember> _orderedTeam(_OccurrencePdfContext ctx) {
    final team = ctx.occurrence.team.isNotEmpty
        ? List<OccurrenceTeamMember>.from(ctx.occurrence.team)
        : <OccurrenceTeamMember>[
            OccurrenceTeamMember(
              handlerId: ctx.handlerRa,
              displayName: ctx.handlerName,
              role: TeamRole.titular,
              addedAt: ctx.occurrence.startedAt,
              addedBy: ctx.handlerRa,
            ),
          ];
    team.sort((a, b) {
      if (a.role != b.role) {
        return a.role == TeamRole.titular ? -1 : 1;
      }
      return a.handlerId.compareTo(b.handlerId);
    });
    return team;
  }

  List<OccurrenceSignature> _signedSignatures(_OccurrencePdfContext ctx) {
    final signatures = ctx.occurrence.signatures
        .where((signature) => signature.status == SignatureStatus.signed)
        .toList();
    signatures.sort((a, b) => a.handlerId.compareTo(b.handlerId));
    return signatures;
  }

  List<_PendingSignaturePdfItem> _pendingSignatureItems(
    _OccurrencePdfContext ctx,
    List<OccurrenceTeamMember> team,
  ) {
    final signaturesByHandler = {
      for (final signature in ctx.occurrence.signatures)
        signature.handlerId: signature,
    };
    final items = <_PendingSignaturePdfItem>[];
    for (final member in team) {
      if (member.role == TeamRole.titular) continue;
      final signature = signaturesByHandler[member.handlerId];
      if (signature?.status == SignatureStatus.signed) continue;
      items.add(
        _PendingSignaturePdfItem(
          member: member,
          signature: signature,
          reason: _pendingSignatureReason(ctx),
        ),
      );
    }
    return items;
  }

  pw.Widget _teamTable(
    _OccurrencePdfContext ctx,
    List<OccurrenceTeamMember> team,
  ) {
    final f = ctx.fonts;
    return pw.Table(
      border: pw.TableBorder.all(color: _line),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.5),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.6),
      },
      children: [
        _pdfTableHeader(ctx, ['Nome', 'Papel', 'RA', 'Incluído em']),
        for (final member in team)
          pw.TableRow(
            children: [
              _pdfTableCell(
                _memberName(member, fallbackName: ctx.handlerName),
                f,
                bold: member.role == TeamRole.titular,
              ),
              _pdfTableCell(
                member.role == TeamRole.titular ? 'Titular' : 'Integrante',
                f,
              ),
              _pdfTableCell(member.handlerId, f, mono: true),
              _pdfTableCell(_formatUtc(member.addedAt), f, mono: true),
            ],
          ),
      ],
    );
  }

  pw.Widget _signatureTable(
    _OccurrencePdfContext ctx,
    List<OccurrenceSignature> signatures,
  ) {
    final f = ctx.fonts;
    return pw.Table(
      border: pw.TableBorder.all(color: _line),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.0),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.8),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(2.4),
      },
      children: [
        _pdfTableHeader(ctx, [
          'Nome',
          'RA',
          'Data/hora UTC',
          'Método',
          'Hash da assinatura',
        ]),
        for (final signature in signatures)
          pw.TableRow(
            children: [
              _pdfTableCell(_signatureMemberName(ctx, signature), f),
              _pdfTableCell(signature.handlerId, f, mono: true),
              _pdfTableCell(_formatUtc(signature.signedAt), f, mono: true),
              _pdfTableCell(
                _signatureMethodLabel(signature.signatureMethod),
                f,
              ),
              _pdfTableCell(signature.signatureHash, f, mono: true, size: 6.2),
            ],
          ),
      ],
    );
  }

  pw.Widget _pendingSignaturesBlock(
    _OccurrencePdfContext ctx,
    List<_PendingSignaturePdfItem> items,
  ) {
    final f = ctx.fonts;
    return _roundedCard(
      background: _amberBg,
      border: _amberLine,
      padding: const pw.EdgeInsets.all(11),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PENDÊNCIAS DE ASSINATURA',
            style: _bodyBold(f, size: 8.7, color: _amber),
          ),
          pw.SizedBox(height: 6),
          for (final item in items) ...[
            pw.Text(
              '${_memberName(item.member)} (RA ${item.member.handlerId})',
              style: _bodyBold(f, size: 8, color: _ink),
            ),
            pw.Text(item.reason, style: _body(f, size: 7.6, color: _amber)),
            if (item.signature?.reason?.trim().isNotEmpty == true)
              pw.Text(
                'Registro: ${item.signature!.reason}',
                style: _body(f, size: 7.2, color: _inkSoft),
              ),
            pw.SizedBox(height: 5),
          ],
        ],
      ),
    );
  }

  pw.TableRow _pdfTableHeader(_OccurrencePdfContext ctx, List<String> labels) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('F7F9FB')),
      children: labels
          .map(
            (label) =>
                _pdfTableCell(label, ctx.fonts, bold: true, color: _inkSoft),
          )
          .toList(),
    );
  }

  pw.Widget _pdfTableCell(
    String text,
    PdfFonts fonts, {
    bool bold = false,
    bool mono = false,
    double size = 7.4,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: mono ? fonts.monoRegular : (bold ? fonts.bold : fonts.regular),
          fontSize: size,
          color: color ?? _ink,
          lineSpacing: 1.4,
        ),
      ),
    );
  }

  String _memberName(OccurrenceTeamMember member, {String? fallbackName}) {
    final displayName = member.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    if (member.role == TeamRole.titular &&
        fallbackName != null &&
        fallbackName.trim().isNotEmpty) {
      return fallbackName.trim();
    }
    return 'Condutor ${member.handlerId}';
  }

  String _signatureMemberName(
    _OccurrencePdfContext ctx,
    OccurrenceSignature signature,
  ) {
    for (final member in ctx.occurrence.team) {
      if (member.handlerId == signature.handlerId) {
        return _memberName(member);
      }
    }
    return 'Condutor ${signature.handlerId}';
  }

  String _signatureMethodLabel(SignatureMethod method) {
    return switch (method) {
      SignatureMethod.biometric => 'Biometria',
      SignatureMethod.password => 'Senha',
    };
  }

  String _pendingSignatureReason(_OccurrencePdfContext ctx) {
    return 'Convidado em ${_formatUtc(ctx.occurrence.signatureRequestAt)}; '
        'não assinou no prazo de ${_formatUtc(ctx.occurrence.signatureDeadline)}.';
  }

  String _formatUtc(DateTime? value) {
    if (value == null) return 'data não registrada';
    return '${DateFormat('dd/MM/yyyy HH:mm').format(value.toUtc())} UTC';
  }

  pw.Widget _hashBox(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final storedHash = ctx.occurrence.integrityHash?.trim();
    final hasHash = storedHash != null && storedHash.isNotEmpty;
    final hash = hasHash ? storedHash : 'Hash ainda nao calculado';
    final stateColor = hasHash ? _green : _amber;
    final stateBg = hasHash ? _greenBg : _amberBg;
    final stateLine = hasHash ? _greenLine : _amberLine;
    return _roundedCard(
      padding: const pw.EdgeInsets.all(13),
      radius: 9,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'HASH DE INTEGRIDADE',
            style: _bodyBold(f, size: 8.2, color: _cyanDeep),
          ),
          pw.SizedBox(height: 10),
          _tinyLabel('SHA-256 - conteudo operacional', f),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F6F8FA'),
              border: pw.Border.all(color: _lineSoft),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(hash, style: _mono(f, size: 7.9, color: _ink)),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              color: stateBg,
              border: pw.Border.all(color: stateLine),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  hasHash ? 'OK' : '!',
                  style: _bodyBold(f, size: 8, color: stateColor),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Text(
                    hasHash
                        ? 'INTEGRO\nConteudo nao alterado apos a finalizacao.'
                        : 'PENDENTE\nFinalize a ocorrencia para cristalizar o hash.',
                    style: _body(
                      f,
                      size: 7.7,
                      color: hasHash ? _inkSoft : _amber,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _verificationBox(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final code = _verificationCode(ctx);
    final url = _verificationUrl(ctx);
    return _roundedCard(
      padding: const pw.EdgeInsets.all(12),
      radius: 9,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'VERIFICAÇÃO ONLINE',
            style: _bodyBold(f, size: 8.2, color: _cyanDeep),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.BarcodeWidget(
                data: url,
                barcode: pw.Barcode.qrCode(),
                width: 64,
                height: 64,
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Escaneie para verificar a integridade e autenticidade do documento.',
                      style: _body(f, size: 7.8, color: _inkSoft),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(code, style: _mono(f, size: 8, color: _cyanDeep)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      url,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: _mono(f, size: 7, color: _inkFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
              color: _amberBg,
              border: pw.Border.all(color: _amberLine),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 1),
                  child: pw.Text(
                    '!',
                    style: _bodyBold(f, size: 7.5, color: _amber),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    'Atenção: A consulta online deste registro pelo QR Code acima estará disponível em breve no portal da Prefeitura Municipal de Limeira.',
                    style: _body(f, size: 7, color: _amber),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _verificationCode(_OccurrencePdfContext ctx) {
    final seq = ctx.occurrence.id.length >= 4
        ? ctx.occurrence.id.substring(0, 4).toUpperCase()
        : ctx.occurrence.id.toUpperCase();
    final start = _operationStart(ctx);
    return '$seq-K9-${start.year}-${_two(start.month)}-${_two(start.day)}-${_two(start.hour)}${_two(start.minute)}';
  }

  String _verificationUrl(_OccurrencePdfContext ctx) {
    final base = _verificationBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return '$base/${Uri.encodeComponent(ctx.occurrence.id)}';
  }

  pw.Widget _docInfo(
    String key,
    String value,
    PdfFonts fonts, {
    bool mono = false,
  }) {
    return pw.SizedBox(
      width: 145,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tinyLabel(key, fonts),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            maxLines: 2,
            style: pw.TextStyle(
              font: mono ? fonts.regular : fonts.bold,
              fontSize: 8.2,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _emptyBox(String message, PdfFonts fonts) {
    return _roundedCard(
      background: PdfColor.fromHex('F7F9FB'),
      padding: const pw.EdgeInsets.all(14),
      child: pw.Text(message, style: _body(fonts, size: 9, color: _inkSoft)),
    );
  }
  // ─── Seção de Aditamentos / Retificações ─────────────────────────────────

  pw.Widget _buildAmendmentsSection(_OccurrencePdfContext ctx) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Título da seção
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: pw.BoxDecoration(
            color: _amberBg,
            border: pw.Border.all(color: _amberLine),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'ADITAMENTOS / RETIFICAÇÕES',
                style: pw.TextStyle(
                  font: ctx.fonts.bold,
                  fontSize: 11,
                  color: _amber,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'As retificações abaixo foram registradas após o selamento '
                'do documento original. O registro original permanece íntegro '
                'e inalterado — cada aditamento possui hash de integridade próprio.',
                style: pw.TextStyle(
                  font: ctx.fonts.regular,
                  fontSize: 8.5,
                  color: _amber,
                  lineSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),

        // Cada aditamento
        ...ctx.amendments.map(
          (amendment) => _buildAmendmentEntry(ctx, amendment, dateFmt),
        ),
      ],
    );
  }

  pw.Widget _buildAmendmentEntry(
    _OccurrencePdfContext ctx,
    Amendment amendment,
    DateFormat dateFmt,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _amberLine),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header: número + data + autor
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Retificação #${amendment.sequenceNumber}',
                style: pw.TextStyle(
                  font: ctx.fonts.bold,
                  fontSize: 10,
                  color: _amber,
                ),
              ),
              pw.Text(
                dateFmt.format(amendment.createdAt),
                style: pw.TextStyle(
                  font: ctx.fonts.regular,
                  fontSize: 8.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${amendment.createdByName} (RA: ${amendment.createdByRa})',
            style: pw.TextStyle(
              font: ctx.fonts.regular,
              fontSize: 8.5,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 8),

          // Motivo
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F9F9F9'),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MOTIVO',
                  style: pw.TextStyle(
                    font: ctx.fonts.bold,
                    fontSize: 7.5,
                    color: PdfColors.grey600,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  amendment.reason,
                  style: pw.TextStyle(
                    font: ctx.fonts.regular,
                    fontSize: 9,
                    color: PdfColors.grey900,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // Correções
          ...amendment.corrections.entries.map(
            (entry) => _buildCorrectionRow(ctx, entry.key, entry.value),
          ),

          // Hash do aditamento
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F5F5F5'),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'HASH SHA-256: ',
                  style: pw.TextStyle(
                    font: ctx.fonts.bold,
                    fontSize: 7,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    amendment.integrityHash,
                    style: pw.TextStyle(
                      font: ctx.fonts.monoRegular,
                      fontSize: 6.5,
                      color: PdfColors.grey800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // QR do aditamento
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data:
                  '$_verificationBaseUrl/${amendment.occurrenceId}'
                  '?a=${amendment.id}&h=${amendment.integrityHash.substring(0, 16)}',
              width: 60,
              height: 60,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCorrectionRow(
    _OccurrencePdfContext ctx,
    String fieldKey,
    AmendmentCorrection correction,
  ) {
    const fieldLabels = {
      'type_name': 'Natureza',
      'location_address': 'Endereço',
      'dog_name': 'Cão',
      'handler_name': 'Condutor',
      'final_report': 'Relatório final',
      'initial_observation': 'Observação inicial',
    };
    final label = fieldLabels[fieldKey] ?? fieldKey;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('E0E0E0')),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              font: ctx.fonts.bold,
              fontSize: 7.5,
              color: _amber,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Antes: ',
                style: pw.TextStyle(
                  font: ctx.fonts.bold,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  '${correction.oldValue ?? '(vazio)'}',
                  style: pw.TextStyle(
                    font: ctx.fonts.regular,
                    fontSize: 8,
                    color: PdfColors.grey700,
                    decoration: pw.TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Depois: ',
                style: pw.TextStyle(
                  font: ctx.fonts.bold,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  '${correction.newValue}',
                  style: pw.TextStyle(
                    font: ctx.fonts.bold,
                    fontSize: 8,
                    color: PdfColors.grey900,
                  ),
                ),
              ),
            ],
          ),
          if (correction.description != null) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              correction.description!,
              style: pw.TextStyle(
                font: ctx.fonts.regular,
                fontSize: 7.5,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OccurrencePdfContext {
  final Occurrence occurrence;
  final List<OccurrenceEvent> events;
  final Dog dog;
  final String handlerName;
  final String handlerRa;
  final String docId;
  final PdfFonts fonts;
  final List<_PdfMediaItem> media;
  final pw.ImageProvider? staticMapImage;
  final pw.ImageProvider? displacementMapImage;
  final List<OccurrenceLocation> locations;
  final List<Amendment> amendments;

  const _OccurrencePdfContext({
    required this.occurrence,
    required this.events,
    required this.dog,
    required this.handlerName,
    required this.handlerRa,
    required this.docId,
    required this.fonts,
    required this.media,
    required this.staticMapImage,
    required this.displacementMapImage,
    required this.locations,
    this.amendments = const [],
  });
}

class _PdfMediaItem {
  final int number;
  final String url;
  final pw.ImageProvider? image;
  final OccurrenceEvent event;

  const _PdfMediaItem({
    required this.number,
    required this.url,
    required this.image,
    required this.event,
  });
}

class _PendingSignaturePdfItem {
  final OccurrenceTeamMember member;
  final OccurrenceSignature? signature;
  final String reason;

  const _PendingSignaturePdfItem({
    required this.member,
    required this.signature,
    required this.reason,
  });
}

class _KeyValue {
  final String label;
  final String value;
  final bool mono;
  final bool green;

  const _KeyValue(
    this.label,
    this.value, {
    this.mono = false,
    this.green = false,
  });
}
