import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/core/services/integrity_verification_service.dart';
import 'package:canil_gcm/core/services/occurrence_location_service.dart';
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

import 'pdf_colors.dart';
import 'pdf_common_widgets.dart';
import 'template/report_branding_assets.dart';
import 'template/report_primitives.dart';
import 'template/report_template_builder.dart';
import 'template/report_tokens.dart';
import 'template/report_types.dart';

/// Gerador do PDF institucional de ocorrencia — F70 Reporting Design System V1.
///
/// F70 — MOB-DOC-01 — Forensic Presentation Migration V1
/// Fonte canónica migrada: `occurrence_pdf_generator.dart` em 38e2649.
/// Contratos forenses preservados integralmente; apenas a camada de
/// apresentação e paginação foi reconstruída sobre [ReportTemplateBuilder].
class OccurrencePdfGenerator {
  static const _photoRequestTimeout = Duration(seconds: 12);
  static const _pdfPhotoMaxDimension = 960;
  static const _pdfPhotoJpegQuality = 72;

  static final _paper = PdfInstitutionalColors.white;
  static final _ink = PdfInstitutionalColors.textInk;
  static final _inkSoft = PdfInstitutionalColors.textMuted;
  static final _inkFaint = PdfInstitutionalColors.textFaint;
  // ignore: unused_field — preserved for forensic parity (legacy palette anchor)
  static final _line = PdfInstitutionalColors.dividerStrong;
  static final _lineSoft = PdfInstitutionalColors.dividerSoft;
  static final _cyan = PdfInstitutionalColors.cyan;
  // ignore: unused_field — preserved for forensic parity
  static final _cyanDeep = PdfInstitutionalColors.cyanDeep;
  static final _green = PdfInstitutionalColors.green;
  // ignore: unused_field — preserved for forensic parity
  static final _greenBg = PdfInstitutionalColors.greenBackground;
  // ignore: unused_field — preserved for forensic parity
  static final _greenLine = PdfInstitutionalColors.greenBorder;
  static final _amber = PdfInstitutionalColors.amber;
  // ignore: unused_field — preserved for forensic parity
  static final _amberBg = PdfInstitutionalColors.amberBackground;
  // ignore: unused_field — preserved for forensic parity
  static final _amberLine = PdfInstitutionalColors.amberBorder;
  // ignore: unused_field — preserved for forensic parity
  static final _red = PdfInstitutionalColors.redAlert;
  // ignore: unused_field — preserved for forensic parity
  static final _headerBg = PdfInstitutionalColors.headerBackground;
  static final _mapBg = PdfInstitutionalColors.mapBackground;
  static final _mapRoad = PdfInstitutionalColors.dividerStrong;
  static final _mediaBg = PdfInstitutionalColors.mediaBackground;

  // ignore: unused_field — forensic label preserved (F70 title carries it)
  static const _docType = 'Registro de Ocorrencia';
  static const _systemName = 'Sistema Canil K9 GCM';
  static const _verificationBaseUrl = String.fromEnvironment(
    'K9_VERIFICATION_BASE_URL',
    defaultValue: 'https://canil-gcm.web.app/v',
  );

  /// Gera o PDF completo e retorna os bytes.
  ///
  /// Mantém a assinatura pública intacta (mock-safe nos testes).
  ///
  /// Parâmetros de teste/injeção (opcionais):
  /// - [amendmentsOverride] injeta aditamentos sintéticos sem tocar Firestore.
  /// - [syntheticImageBytesByItemNumber] injeta bytes de imagem sintética por
  ///   número do item de mídia (`_PdfMediaItem.number`), sem rede.
  Future<Uint8List> generate({
    required Occurrence occurrence,
    required List<OccurrenceEvent> events,
    Dog? dog,
    required String handlerName,
    required String handlerRa,
    IntegrityVerdict? integrityVerdict,
    @visibleForTesting List<Amendment>? amendmentsOverride,
    @visibleForTesting Map<int, Uint8List>? syntheticImageBytesByItemNumber,
  }) async {
    final fonts = await PdfFonts.load();
    final logoBytes = await ReportBrandingAssets.loadOfficialLogo();

    final docId = _buildDocId(occurrence);
    final sortedEvents = [...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final locations = OccurrenceLocationService.clusterEventsSync(sortedEvents);
    var media = await _buildMediaItems(sortedEvents);
    var finalizationMedia = await _buildFinalizationMediaItems(occurrence);
    if (syntheticImageBytesByItemNumber != null &&
        syntheticImageBytesByItemNumber.isNotEmpty) {
      media = media
          .map(
            (item) => syntheticImageBytesByItemNumber.containsKey(item.number)
                ? _PdfMediaItem(
                    number: item.number,
                    url: item.url,
                    image: pw.MemoryImage(
                      syntheticImageBytesByItemNumber[item.number]!,
                    ),
                    event: item.event,
                  )
                : item,
          )
          .toList();
      // Finalization items use 1-based numbering matching event items; offset to avoid collision
      // For simplicity, reuse same map for finalization when keys overlap (callers should avoid overlap by using disjoint ranges)
      finalizationMedia = finalizationMedia
          .map(
            (item) =>
                syntheticImageBytesByItemNumber.containsKey(1000 + item.number)
                ? _PdfFinalizationMediaItem(
                    number: item.number,
                    url: item.url,
                    image: pw.MemoryImage(
                      syntheticImageBytesByItemNumber[1000 + item.number]!,
                    ),
                  )
                : item,
          )
          .toList();
    }
    final amendments =
        amendmentsOverride ??
        await AmendmentRepository().listByOccurrence(occurrence.id);

    final ctx = _OccurrencePdfContext(
      occurrence: occurrence,
      events: sortedEvents,
      dog: dog,
      handlerName: handlerName,
      handlerRa: handlerRa,
      docId: docId,
      fonts: fonts,
      media: media,
      finalizationMedia: finalizationMedia,
      staticMapImage: null,
      displacementMapImage: null,
      locations: locations,
      amendments: amendments,
      integrityVerdict: integrityVerdict,
    );

    // ── F70 metadata / branding ────────────────────────────────────────
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    final duration = _durationLabel(start, end);
    final statusTone = _statusTone(ctx.occurrence.status);
    final statusLabel = _statusLabel(
      ctx.occurrence,
    ).replaceAll('\n', ' ').trim();

    final metadata = ReportMetadata(
      generatedAt: ctx.occurrence.updatedAt,
      documentId: ctx.docId,
      operatorName: ctx.handlerName,
      callsign: ctx.occurrence.vehicleLabel,
      period:
          '${_formatDate(start)}  ${_formatTime(start)} → ${_formatTime(end)}  ·  $duration',
      dogIdentity: ctx.dog?.name,
    );

    final builder = ReportTemplateBuilder(
      title: 'REGISTRO DE OCORRÊNCIA',
      subtitle: ctx.occurrence.typeName.toUpperCase(),
      category: 'OCORRÊNCIA K9',
      organization: 'GUARDA CIVIL MUNICIPAL DE LIMEIRA',
      motto: 'DISCIPLINA · PROTEÇÃO · RESULTADO',
      metadata: metadata,
      branding: ReportBranding(
        productMarkImage: logoBytes != null
            ? ReportImageSlot(bytes: logoBytes)
            : null,
      ),
      statusLabel: statusLabel,
      statusTone: statusTone,
      useDarkFooter: true,
      archetypeConfig: ReportArchetypeConfig(
        archetype: ReportArchetype.operational,
        name: 'Registro Operacional — Ocorrência K9',
        headerVariant: HeaderVariant.darkTactical,
        orientation: PageOrientation.portrait,
        requiresAuditBlock: true,
        requiresSignatures: true,
        supportsTimeline: true,
        supportsIdentityBlock: true,
        supportsDataTable: true,
      ),
      disclaimer: 'Documento gerado automaticamente pelo $_systemName',
    );

    // ── F70 section assembly (all paginable inside the single MultiPage) ──
    builder.addWidget(_buildHeroSection(ctx));
    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    builder.addWidget(_buildOperationalSummary(ctx));
    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    builder.addWidget(_buildLocationSection(ctx));
    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    builder.addWidget(_buildDisplacementSection(ctx));
    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    builder.addWidget(_buildTimelineSection(ctx));
    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    builder.addWidget(_buildMediaSection(ctx));
    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    builder.addWidget(_buildReportSection(ctx));
    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    builder.addWidget(_buildValidationSection(ctx));
    if (ctx.amendments.isNotEmpty) {
      builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
      builder.addWidget(_buildAmendmentsSection(ctx));
    }

    return builder.buildPdf(customFonts: fonts);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Data loading (unchanged forensic behavior)
  // ═══════════════════════════════════════════════════════════════════════

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

  Future<List<_PdfFinalizationMediaItem>> _buildFinalizationMediaItems(
    Occurrence occurrence,
  ) async {
    final client = http.Client();
    final media = <_PdfFinalizationMediaItem>[];
    try {
      for (var i = 0; i < occurrence.finalizationPhotos.length; i++) {
        final url = occurrence.finalizationPhotos[i];
        media.add(
          _PdfFinalizationMediaItem(
            number: i + 1,
            url: url,
            image: await _loadOptimizedPhoto(client, url),
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

  // ═══════════════════════════════════════════════════════════════════════
  // Pure helpers (F70-ported, forensic strings preserved)
  // ═══════════════════════════════════════════════════════════════════════

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

  // _timeWindow preserved only inside _operation window text (metadata period)
  // kept as inline in builder to avoid dead helper warning.

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

  ReportTone _statusTone(OccurrenceStatus status) => switch (status) {
    OccurrenceStatus.finalized => ReportTone.positive,
    OccurrenceStatus.finalizedWithPending => ReportTone.attention,
    OccurrenceStatus.awaitingSignatures => ReportTone.attention,
    OccurrenceStatus.finalizing => ReportTone.info,
    OccurrenceStatus.canceled => ReportTone.critical,
    OccurrenceStatus.inProgress => ReportTone.info,
  };

  int _boCount(Occurrence occurrence) =>
      occurrence.results.contains(OccurrenceResult.boCreated) ? 1 : 0;

  String _locationMain(Occurrence occurrence) {
    final raw = occurrence.locationAddress?.trim();
    if (raw == null || raw.isEmpty) return 'Endereço não informado';
    final parts = raw.split(',').map((part) => part.trim()).toList();
    return parts.firstWhere((part) => part.isNotEmpty, orElse: () => raw);
  }

  String _locationSub(Occurrence occurrence) {
    final raw = occurrence.locationAddress?.trim();
    if (raw == null || raw.isEmpty) return 'Limeira/SP';
    final parts = raw.split(',').map((part) => part.trim()).toList();
    if (parts.length <= 1) return 'Limeira/SP';
    return parts.skip(1).where((part) => part.isNotEmpty).take(2).join(' — ');
  }

  String _gpsText(double? lat, double? lng, {int precision = 6}) {
    if (lat == null || lng == null) return 'GPS indisponível';
    return '${lat.toStringAsFixed(precision)}, ${lng.toStringAsFixed(precision)}';
  }

  String _accuracyText(double? accuracy) {
    if (accuracy == null) return 'N/I';
    return '±${accuracy.toStringAsFixed(0)}m';
  }

  String _shortId(String value) {
    if (value.trim().isEmpty) return 'N/I';
    return value.length > 8 ? value.substring(0, 8) : value;
  }

  // ── Color / font shorthands ──────────────────────────────────────────

  pw.TextStyle _mono(PdfFonts fonts, {double size = 9, PdfColor? color}) {
    return pw.TextStyle(
      font: fonts.monoRegular,
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

  pw.Widget _emptyBox(String message, PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(message, style: _body(fonts, size: 9, color: _inkSoft)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // F70 sections (each is paginable inside the single MultiPage)
  // ═══════════════════════════════════════════════════════════════════════

  // ── Hero / binômio ───────────────────────────────────────────────────

  bool _hasK9(_OccurrencePdfContext ctx) =>
      ctx.dog != null && ctx.dog!.name.trim().isNotEmpty;

  pw.Widget _buildHeroSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final hasK9 = _hasK9(ctx);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          hasK9 ? 'BINÔMIO RESPONSÁVEL' : 'GUARNIÇÃO RESPONSÁVEL',
          f,
          iconText: hasK9 ? 'K9' : 'GR',
          subtitle: hasK9
              ? 'Dupla operacional responsável pelo registro'
              : 'Condutor responsável pelo registro — sem emprego de cão K9',
        ),
        _binomioF70(ctx),
        pw.SizedBox(height: 6),
        pw.Text(
          hasK9
              ? 'O cão K9 não assina; sua presença é atestada pelos condutores da guarnição.'
              : 'Nenhum cão K9 empregado nesta ocorrência; registro sob responsabilidade do condutor.',
          style: pw.TextStyle(
            font: f.regular,
            fontSize: 7,
            color: ReportColors.textMuted,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    );
  }

  pw.Widget _binomioF70(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final hasK9 = _hasK9(ctx);
    // No-K9 contract: never invent dog identity when canonical record has no service dog
    if (!hasK9) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: ReportColors.surface,
          border: pw.Border.all(color: ReportColors.borderSoft, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        padding: const pw.EdgeInsets.all(12),
        child: pw.Row(
          children: [
            pw.Container(
              width: 46,
              height: 46,
              decoration: pw.BoxDecoration(
                color: ReportColors.surfaceSubtle,
                shape: pw.BoxShape.circle,
                border: pw.Border.all(
                  color: ReportColors.borderSoft,
                  width: 1.2,
                ),
              ),
              child: pw.Center(
                child: pw.Text(
                  'SEM\nK9',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: f.bold,
                    fontSize: 7,
                    lineSpacing: 1,
                    color: ReportColors.textMuted,
                  ),
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _tinyLabel(
                    'Atuação sem K9',
                    f,
                    color: ReportColors.textMuted,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Sem cão K9 vinculado',
                    style: _bodyBold(
                      f,
                      size: 11,
                      color: ReportColors.textMuted,
                    ),
                  ),
                  pw.Text(
                    'Cão não empregado nesta ocorrência (sem dog_id de serviço).',
                    style: _body(f, size: 8, color: _inkSoft),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.Expanded(
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _tinyLabel('Condutor', f, color: ReportColors.accent),
                        pw.SizedBox(height: 2),
                        pw.Text(ctx.handlerName, style: _bodyBold(f, size: 11)),
                        pw.Text(
                          'RA: ${ctx.handlerRa}\nUnidade: Canil K9 — Limeira',
                          textAlign: pw.TextAlign.right,
                          style: _body(f, size: 8, color: _inkSoft),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  _avatarF70('FOTO\nGCM', f),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final dog = ctx.dog!;
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(12),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Row(
              children: [
                _avatarF70('FOTO\nK9', f),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _tinyLabel('Cão K9', f, color: ReportColors.accent),
                      pw.SizedBox(height: 2),
                      pw.Text(dog.name, style: _bodyBold(f, size: 11)),
                      pw.Text(
                        'Raça: ${dog.breed}\nMatrícula: ${dog.registrationNumber ?? 'N/I'}',
                        style: _body(f, size: 8, color: _inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: 18,
            alignment: pw.Alignment.center,
            child: pw.Container(
              width: 4,
              height: 4,
              decoration: pw.BoxDecoration(
                color: ReportColors.borderSoft,
                shape: pw.BoxShape.circle,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _tinyLabel('Condutor', f, color: ReportColors.accent),
                      pw.SizedBox(height: 2),
                      pw.Text(ctx.handlerName, style: _bodyBold(f, size: 11)),
                      pw.Text(
                        'RA: ${ctx.handlerRa}\nUnidade: Canil K9 — Limeira',
                        textAlign: pw.TextAlign.right,
                        style: _body(f, size: 8, color: _inkSoft),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                _avatarF70('FOTO\nGCM', f),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _avatarF70(String label, PdfFonts fonts) {
    return pw.Container(
      width: 46,
      height: 46,
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: ReportColors.accent, width: 1.2),
      ),
      child: pw.Center(
        child: pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 7,
            lineSpacing: 1,
            color: ReportColors.accent,
          ),
        ),
      ),
    );
  }

  // ── Operational summary ──────────────────────────────────────────────

  pw.Widget _buildOperationalSummary(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'RESUMO OPERACIONAL',
          f,
          iconText: 'OPS',
          subtitle: 'Síntese factual da atuação',
        ),
        pw.Row(
          children: [
            pw.Expanded(
              child: _metricF70(
                'TEMPO',
                _durationLabel(start, end),
                'Duração',
                f,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricF70('EV', '${ctx.events.length}', 'Eventos', f),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricF70(
                'MID',
                '${ctx.media.length + ctx.finalizationMedia.length}',
                'Mídias',
                f,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricF70('BO', '${_boCount(ctx.occurrence)}', 'BO', f),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(
            color: ReportColors.surfaceSubtle,
            border: pw.Border.all(color: ReportColors.borderSoft),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _tinyLabel('Natureza', f),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      ctx.occurrence.typeName,
                      style: _bodyBold(f, size: 9),
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _tinyLabel('Janela operacional', f),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      '${_formatTime(start)} → ${_formatTime(end)}',
                      style: _mono(f, size: 9),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _tinyLabel('Status', f),
                  pw.SizedBox(height: 2),
                  ReportPrimitives.statusBadge(
                    _statusLabel(ctx.occurrence).replaceAll('\n', ' '),
                    _statusTone(ctx.occurrence.status),
                    f,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _metricF70(
    String label,
    String value,
    String caption,
    PdfFonts fonts,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: _bodyBold(fonts, size: 8, color: ReportColors.accent),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(font: fonts.bold, fontSize: 18, color: _ink),
          ),
          pw.SizedBox(height: 2),
          pw.Text(caption, style: _body(fonts, size: 7, color: _inkSoft)),
        ],
      ),
    );
  }

  // ── Location ─────────────────────────────────────────────────────────

  bool _hasLocation(_OccurrencePdfContext ctx) {
    final hasAddress =
        ctx.occurrence.locationAddress?.trim().isNotEmpty == true;
    final hasGps =
        ctx.occurrence.gpsLat != null && ctx.occurrence.gpsLng != null;
    final hasEventGps = ctx.events.any(
      (e) => e.gpsLat != null && e.gpsLng != null,
    );
    return hasAddress || hasGps || hasEventGps;
  }

  pw.Widget _buildLocationSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    final hasLoc = _hasLocation(ctx);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'LOCALIZAÇÃO E DADOS OPERACIONAIS',
          f,
          iconText: 'LOC',
          subtitle: hasLoc
              ? 'Endereço, coordenadas e contexto administrativo'
              : 'Sem localização registrada — ocorrência sem coordenadas',
        ),
        if (!hasLoc)
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: ReportColors.surfaceSubtle,
              border: pw.Border.all(color: ReportColors.borderSoft),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 36,
                  height: 36,
                  decoration: pw.BoxDecoration(
                    color: ReportColors.surface,
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: ReportColors.borderSoft),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      '!',
                      style: _bodyBold(
                        f,
                        size: 14,
                        color: ReportColors.textMuted,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LOCALIZAÇÃO NÃO INFORMADA',
                        style: _bodyBold(
                          f,
                          size: 9,
                          color: ReportColors.textMuted,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Endereço e coordenadas GPS não foram registrados nesta ocorrência. O mapa permanece indisponível até que o condutor informe a localização.',
                        style: _body(f, size: 7.5, color: _inkSoft),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'GPS indisponível  ·  Mapa esquemático indisponível',
                        style: _mono(f, size: 7, color: _inkFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 7,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: ReportColors.borderSoft),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(6),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: pw.BoxDecoration(
                          color: ReportColors.surfaceSubtle,
                          border: pw.Border(
                            bottom: pw.BorderSide(
                              color: ReportColors.borderSoft,
                            ),
                          ),
                        ),
                        child: pw.Row(
                          children: [
                            pw.Text(
                              'O',
                              style: _bodyBold(
                                f,
                                size: 8,
                                color: ReportColors.accent,
                              ),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              'MAPA DA OCORRÊNCIA',
                              style: _bodyBold(
                                f,
                                size: 7.5,
                                color: ReportColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _mapCanvasF70(ctx, height: 170),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: pw.BoxDecoration(
                          color: ReportColors.surfaceSubtle,
                          border: pw.Border(
                            top: pw.BorderSide(color: ReportColors.borderSoft),
                          ),
                        ),
                        child: pw.Row(
                          children: [
                            pw.Text(
                              'P',
                              style: _bodyBold(
                                f,
                                size: 8,
                                color: ReportColors.accent,
                              ),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    _locationMain(ctx.occurrence),
                                    style: _bodyBold(f, size: 9.5),
                                  ),
                                  pw.Text(
                                    _locationSub(ctx.occurrence),
                                    style: _body(f, size: 7.5, color: _inkSoft),
                                  ),
                                ],
                              ),
                            ),
                            pw.Text(
                              _gpsText(
                                ctx.occurrence.gpsLat,
                                ctx.occurrence.gpsLng,
                                precision: 5,
                              ),
                              style: _mono(
                                f,
                                size: 7.5,
                                color: ReportColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  children: [
                    _infoBoxF70('Endereço', [
                      _locationMain(ctx.occurrence),
                      _locationSub(ctx.occurrence),
                      'Limeira/SP',
                    ], f),
                    pw.SizedBox(height: 8),
                    _coordinateBoxF70(ctx),
                    pw.SizedBox(height: 8),
                    _gpsSignalF70(ctx),
                  ],
                ),
              ),
            ],
          ),
        pw.SizedBox(height: 10),
        // Dados administrativos — F70 dataTable-friendly grid
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: ReportColors.borderSoft),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _adminCellF70(
                      'Turno / Plantão',
                      _shortId(ctx.occurrence.shiftId),
                      f,
                      mono: true,
                    ),
                  ),
                  _vDivider(),
                  pw.Expanded(
                    child: _adminCellF70(
                      'Data',
                      _formatDate(start),
                      f,
                      mono: true,
                    ),
                  ),
                  _vDivider(),
                  pw.Expanded(
                    child: _adminCellF70(
                      'Início',
                      _formatTime(start),
                      f,
                      mono: true,
                    ),
                  ),
                  _vDivider(),
                  pw.Expanded(
                    child: _adminCellF70(
                      'Término',
                      _formatTime(end),
                      f,
                      mono: true,
                    ),
                  ),
                  _vDivider(),
                  pw.Expanded(
                    child: _adminCellF70(
                      'Duração',
                      _durationLabel(start, end),
                      f,
                      mono: true,
                    ),
                  ),
                ],
              ),
              pw.Container(height: 0.5, color: ReportColors.borderSoft),
              pw.Row(
                children: [
                  pw.Expanded(child: _adminCellF70('Prioridade', 'Normal', f)),
                  _vDivider(),
                  pw.Expanded(
                    flex: 4,
                    child: _adminCellF70(
                      'Status do registro',
                      '${_statusLabel(ctx.occurrence).replaceAll('\n', ' ')} · sincronizado ${_formatTime(ctx.occurrence.updatedAt)}',
                      f,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _vDivider() =>
      pw.Container(width: 0.5, height: 36, color: ReportColors.borderSoft);

  pw.Widget _infoBoxF70(String title, List<String> lines, PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: _bodyBold(fonts, size: 7.5, color: ReportColors.accent),
          ),
          pw.SizedBox(height: 6),
          for (var i = 0; i < lines.length; i++)
            pw.Text(
              lines[i],
              style: i == 0
                  ? _bodyBold(fonts, size: 9)
                  : _body(fonts, size: 8, color: _inkSoft),
            ),
        ],
      ),
    );
  }

  pw.Widget _coordinateBoxF70(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'COORDENADAS GPS',
            style: _bodyBold(f, size: 7.5, color: ReportColors.accent),
          ),
          pw.SizedBox(height: 6),
          _coordRowF70(
            'Latitude',
            ctx.occurrence.gpsLat?.toStringAsFixed(6) ?? 'N/I',
            f,
          ),
          _coordRowF70(
            'Longitude',
            ctx.occurrence.gpsLng?.toStringAsFixed(6) ?? 'N/I',
            f,
          ),
          _coordRowF70(
            'Precisão',
            _accuracyText(ctx.occurrence.gpsAccuracy),
            f,
          ),
        ],
      ),
    );
  }

  pw.Widget _coordRowF70(String key, String value, PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: ReportColors.borderSoft, width: 0.4),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: _tinyLabel(key, fonts)),
          pw.Text(value, style: _mono(fonts, size: 8)),
        ],
      ),
    );
  }

  pw.Widget _gpsSignalF70(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final strong =
        ctx.occurrence.gpsAccuracy != null && ctx.occurrence.gpsAccuracy! <= 50;
    final tone = strong ? ReportTone.positive : ReportTone.attention;
    final colors = ReportToneColors.of(tone);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: colors.background,
        border: pw.Border.all(color: colors.border),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        children: [
          pw.Text('GPS', style: _bodyBold(f, size: 8, color: colors.accent)),
          pw.SizedBox(width: 8),
          pw.Text(
            strong ? 'SINAL FORTE' : 'PRECISÃO LIMITADA',
            style: _bodyBold(f, size: 7.5, color: colors.text),
          ),
          pw.Spacer(),
          for (var i = 0; i < 4; i++)
            pw.Container(
              width: 3,
              height: 5.0 + (i * 3),
              margin: const pw.EdgeInsets.only(left: 2),
              color: colors.accent,
            ),
        ],
      ),
    );
  }

  pw.Widget _adminCellF70(
    String label,
    String value,
    PdfFonts fonts, {
    bool mono = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tinyLabel(label, fonts),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            maxLines: 2,
            style: pw.TextStyle(
              font: mono ? fonts.monoRegular : fonts.bold,
              fontSize: 8,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _mapCanvasF70(_OccurrencePdfContext ctx, {required double height}) {
    final f = ctx.fonts;
    return pw.Container(
      height: height,
      color: _mapBg,
      child: pw.Stack(
        children: [
          _mapRoadLineF70(left: 0, top: height * .18, width: 535, height: 4),
          _mapRoadLineF70(left: 0, top: height * .44, width: 535, height: 6),
          _mapRoadLineF70(left: 0, top: height * .72, width: 535, height: 4),
          _mapRoadLineF70(left: 125, top: 0, width: 4, height: height),
          _mapRoadLineF70(left: 255, top: 0, width: 6, height: height),
          _mapRoadLineF70(left: 385, top: 0, width: 4, height: height),
          _roadLabelF70(
            'R. Frederico Rotulo',
            left: 18,
            top: height * .39,
            fonts: f,
          ),
          _roadLabelF70(
            'R. Guido Orsi',
            left: 280,
            top: height * .13,
            fonts: f,
          ),
          _roadLabelF70(
            'R. Jose Brunatti',
            left: 42,
            top: height * .8,
            fonts: f,
          ),
          _roadLabelF70(
            'E. E. Jd. Ouro Verde',
            left: 365,
            top: height * .56,
            fonts: f,
          ),
          pw.Positioned(
            top: 8,
            right: 10,
            child: pw.Column(
              children: [
                pw.Text('N', style: _mono(f, size: 7, color: _inkSoft)),
                pw.Text('↑', style: _mono(f, size: 10, color: _cyan)),
              ],
            ),
          ),
          pw.Positioned(
            left: 258,
            top: height * .45,
            child: pw.Column(
              children: [
                pw.Container(
                  width: 14,
                  height: 14,
                  decoration: pw.BoxDecoration(
                    color: _cyan,
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(
                      color: PdfInstitutionalColors.white,
                      width: 2,
                    ),
                  ),
                ),
                pw.Container(
                  width: 32,
                  height: 6,
                  decoration: pw.BoxDecoration(
                    color: PdfInstitutionalColors.cyanOverlay,
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

  pw.Widget _mapRoadLineF70({
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

  pw.Widget _roadLabelF70(
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
        style: _body(fonts, size: 6, color: PdfInstitutionalColors.textSubtle),
      ),
    );
  }

  // ── Displacement ─────────────────────────────────────────────────────

  pw.Widget _buildDisplacementSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final locations = ctx.locations;
    if (locations.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'MAPA DE DESLOCAMENTO',
          f,
          iconText: 'MAP',
          subtitle:
              '${locations.length} ${locations.length == 1 ? 'local' : 'locais'} · ordem cronológica de paradas',
        ),
        _displacementMapFrameF70(ctx, height: 190),
        pw.SizedBox(height: 10),
        ...locations.map((loc) {
          final isFirst = loc.index == 1;
          final pinColor = isFirst
              ? PdfInstitutionalColors.greenBright
              : PdfInstitutionalColors.cyanAccent;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Row(
              children: [
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
                      color: PdfInstitutionalColors.darkSurfaceDeep,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Text(
                    loc.label,
                    style: _bodyBold(f, size: 9, color: _ink),
                  ),
                ),
                pw.Text(
                  _formatTime(loc.arrivedAt),
                  style: _body(f, size: 8, color: _inkSoft),
                ),
              ],
            ),
          );
        }),
        pw.SizedBox(height: 4),
        pw.Text(
          'Cada parada marca o local onde uma ou mais ações foram registradas, na ordem em que aconteceram.',
          style: _body(f, size: 7, color: _inkSoft),
        ),
      ],
    );
  }

  pw.Widget _displacementMapFrameF70(
    _OccurrencePdfContext ctx, {
    required double height,
  }) {
    final f = ctx.fonts;
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints?.maxWidth ?? 535.0;
        final width = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 535.0;
        final points = _buildDisplacementPoints(ctx.locations, width, height);
        final hasRasterMap = ctx.displacementMapImage != null;

        return pw.Container(
          height: height,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: ReportColors.borderSoft),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Stack(
              children: [
                if (hasRasterMap)
                  pw.Positioned.fill(
                    child: pw.Image(
                      ctx.displacementMapImage!,
                      fit: pw.BoxFit.cover,
                    ),
                  )
                else
                  pw.Positioned.fill(child: pw.Container(color: _mapBg)),
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    painter: (canvas, size) => _paintDisplacementMap(
                      canvas,
                      size,
                      points,
                      drawBaseMap: !hasRasterMap,
                    ),
                  ),
                ),
                for (final point in points)
                  _displacementPinF70(point, f, width: width, height: height),
                pw.Positioned(
                  right: 10,
                  top: 10,
                  child: pw.Column(
                    children: [
                      pw.Text('N', style: _mono(f, size: 7, color: _inkSoft)),
                      pw.Text('↑', style: _mono(f, size: 10, color: _cyan)),
                    ],
                  ),
                ),
                if (!hasRasterMap)
                  pw.Positioned(
                    left: 10,
                    bottom: 8,
                    child: pw.Text(
                      'Mapa esquemático gerado a partir dos pontos GPS registrados',
                      style: _body(f, size: 6.5, color: _inkSoft),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_PdfDisplacementPoint> _buildDisplacementPoints(
    List<OccurrenceLocation> locations,
    double width,
    double height,
  ) {
    if (locations.isEmpty) return const [];
    if (locations.length == 1) {
      return [
        _PdfDisplacementPoint(
          location: locations.first,
          x: width / 2,
          y: height / 2,
        ),
      ];
    }

    final minLat = locations.map((l) => l.lat).reduce(math.min);
    final maxLat = locations.map((l) => l.lat).reduce(math.max);
    final minLng = locations.map((l) => l.lng).reduce(math.min);
    final maxLng = locations.map((l) => l.lng).reduce(math.max);
    final latSpan = maxLat - minLat;
    final lngSpan = maxLng - minLng;
    final paddingX = math.min(width * .12, 42.0);
    final paddingY = math.min(height * .18, 30.0);
    final usableWidth = math.max(1.0, width - (paddingX * 2));
    final usableHeight = math.max(1.0, height - (paddingY * 2));

    return locations.map((location) {
      final x = lngSpan.abs() < 0.000001
          ? width / 2
          : paddingX + ((location.lng - minLng) / lngSpan) * usableWidth;
      final y = latSpan.abs() < 0.000001
          ? height / 2
          : paddingY + ((location.lat - minLat) / latSpan) * usableHeight;
      return _PdfDisplacementPoint(location: location, x: x, y: y);
    }).toList();
  }

  void _paintDisplacementMap(
    PdfGraphics canvas,
    PdfPoint size,
    List<_PdfDisplacementPoint> points, {
    required bool drawBaseMap,
  }) {
    final width = size.x;
    final height = size.y;

    if (drawBaseMap) {
      canvas
        ..setFillColor(_mapBg)
        ..drawRect(0, 0, width, height)
        ..fillPath()
        ..setLineWidth(.45)
        ..setStrokeColor(_lineSoft);

      for (var i = 1; i < 5; i++) {
        final x = width * i / 5;
        canvas.drawLine(x, 0, x, height);
      }
      for (var i = 1; i < 4; i++) {
        final y = height * i / 4;
        canvas.drawLine(0, y, width, y);
      }
      canvas.strokePath();

      canvas
        ..setLineCap(PdfLineCap.round)
        ..setLineWidth(7)
        ..setStrokeColor(PdfInstitutionalColors.dividerStrong)
        ..drawLine(0, height * .23, width, height * .32)
        ..drawLine(width * .12, 0, width * .48, height)
        ..drawLine(width * .52, 0, width * .92, height * .72)
        ..strokePath()
        ..setLineWidth(3)
        ..setStrokeColor(PdfInstitutionalColors.white)
        ..drawLine(0, height * .23, width, height * .32)
        ..drawLine(width * .12, 0, width * .48, height)
        ..drawLine(width * .52, 0, width * .92, height * .72)
        ..strokePath();
    }

    if (points.length < 2) return;

    canvas
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round)
      ..setLineWidth(7)
      ..setStrokeColor(PdfInstitutionalColors.white)
      ..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      canvas.lineTo(point.x, point.y);
    }
    canvas.strokePath();

    canvas
      ..setLineWidth(3)
      ..setStrokeColor(_cyan)
      ..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      canvas.lineTo(point.x, point.y);
    }
    canvas.strokePath();
  }

  pw.Widget _displacementPinF70(
    _PdfDisplacementPoint point,
    PdfFonts fonts, {
    required double width,
    required double height,
  }) {
    final radius = point.location.index == 1 ? 10.0 : 9.0;
    final color = point.location.index == 1
        ? PdfInstitutionalColors.greenBright
        : PdfInstitutionalColors.cyanAccent;
    final left = (point.x - radius)
        .clamp(3.0, math.max(3.0, width - (radius * 2) - 3))
        .toDouble();
    final top = (height - point.y - radius)
        .clamp(3.0, math.max(3.0, height - (radius * 2) - 3))
        .toDouble();

    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Container(
        width: radius * 2,
        height: radius * 2,
        decoration: pw.BoxDecoration(
          color: color,
          shape: pw.BoxShape.circle,
          border: pw.Border.all(color: PdfInstitutionalColors.white, width: 2),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text(
          '${point.location.index}',
          style: _bodyBold(
            fonts,
            size: 8,
            color: PdfInstitutionalColors.darkSurfaceDeep,
          ),
        ),
      ),
    );
  }

  // ── Timeline ─────────────────────────────────────────────────────────

  String _eventCountLabel(int n) => n == 1 ? '1 ação' : '$n ações';

  pw.Widget _buildTimelineSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final start = _operationStart(ctx);
    final end = _operationEnd(ctx);
    final entries = ctx.events;
    // Keep heading + summary + first event atomically (avoid orphan heading)
    final headerGroup = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'LINHA DO TEMPO OPERACIONAL',
          f,
          iconText: 'TL',
          subtitle: 'Sequência cronológica dos eventos registrados',
        ),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: ReportColors.borderSoft),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: _timelineSummaryF70('Início', _formatTime(start), f),
              ),
              _vDivider(),
              pw.Expanded(
                child: _timelineSummaryF70(
                  'Eventos',
                  _eventCountLabel(ctx.events.length),
                  f,
                ),
              ),
              _vDivider(),
              pw.Expanded(
                child: _timelineSummaryF70(
                  'Duração',
                  '${_durationLabel(start, end)}  ${_formatTime(start)} → ${_formatTime(end)}',
                  f,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        if (entries.isEmpty)
          _emptyBox('Nenhum evento registrado na ocorrência.', f)
        else
          _timelineEventF70(entries.first, f, last: entries.length == 1),
      ],
    );
    final remaining = entries.length <= 1
        ? <pw.Widget>[]
        : entries
              .sublist(1)
              .asMap()
              .entries
              .map(
                (e) => _timelineEventF70(
                  e.value,
                  f,
                  last: e.key == entries.length - 2,
                ),
              )
              .toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        headerGroup,
        ...remaining,
        pw.SizedBox(height: 8),
        _timelineLegendF70(f),
      ],
    );
  }

  pw.Widget _timelineSummaryF70(String key, String value, PdfFonts fonts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tinyLabel(key, fonts),
          pw.SizedBox(height: 3),
          pw.Text(value, style: _mono(fonts, size: 9)),
        ],
      ),
    );
  }

  pw.Widget _timelineEventF70(
    OccurrenceEvent event,
    PdfFonts fonts, {
    required bool last,
  }) {
    final color = _eventColor(event.category);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 46,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                _formatTime(event.timestamp),
                style: _mono(fonts, size: 9.5),
              ),
              pw.Text(
                _formatShortDate(event.timestamp),
                style: _mono(fonts, size: 6.5, color: _inkFaint),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Container(
          width: 20,
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
                    style: _bodyBold(fonts, size: 6.5, color: color),
                  ),
                ),
              ),
              if (!last)
                pw.Container(
                  width: 1.2,
                  height: 44,
                  color: ReportColors.borderSoft,
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: ReportColors.surface,
              border: pw.Border(
                left: pw.BorderSide(color: color, width: 2.5),
                top: pw.BorderSide(color: ReportColors.borderSoft),
                right: pw.BorderSide(color: ReportColors.borderSoft),
                bottom: pw.BorderSide(color: ReportColors.borderSoft),
              ),
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
                        style: _bodyBold(fonts, size: 9, color: color),
                      ),
                      if ((event.description ?? '').trim().isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          event.description!,
                          maxLines: 4,
                          style: _body(fonts, size: 8, color: _inkSoft),
                        ),
                      ],
                      if (event.category == OccurrenceEventCategory.dogWork &&
                          (event.dogHandlerId ?? '').trim().isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Emprego do K9 conduzido por RA ${event.dogHandlerId!.trim()}',
                          style: _bodyBold(fonts, size: 7.5, color: _green),
                        ),
                      ],
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _gpsText(event.gpsLat, event.gpsLng, precision: 5),
                        style: _mono(
                          fonts,
                          size: 7,
                          color: ReportColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.photoUrls.isNotEmpty) ...[
                  pw.SizedBox(width: 8),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        width: 86,
                        height: 44,
                        decoration: pw.BoxDecoration(
                          color: _mediaBg,
                          border: pw.Border.all(color: ReportColors.borderSoft),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            '${event.photoUrls.length} foto(s)',
                            style: _body(fonts, size: 7, color: _inkFaint),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'SINC ${_formatTime(event.updatedAt)}',
                        style: _bodyBold(fonts, size: 6.5, color: _green),
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

  pw.Widget _timelineLegendF70(PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: ReportColors.borderSoft)),
      ),
      child: pw.Row(
        children: [
          _legendDotF70('Busca / Investigação', _amber, fonts),
          pw.SizedBox(width: 14),
          _legendDotF70('Registro / Abordagem', _cyan, fonts),
          pw.SizedBox(width: 14),
          _legendDotF70('Emprego / Resultado', _green, fonts),
        ],
      ),
    );
  }

  pw.Widget _legendDotF70(String label, PdfColor color, PdfFonts fonts) {
    return pw.Row(
      children: [
        pw.Container(
          width: 6,
          height: 6,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: _body(fonts, size: 7, color: _inkSoft)),
      ],
    );
  }

  // ── Media ────────────────────────────────────────────────────────────

  pw.Widget _buildMediaSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final visibleMedia = ctx.media;
    final finalizationMedia = ctx.finalizationMedia;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'MÍDIAS OPERACIONAIS',
          f,
          iconText: 'MID',
          subtitle:
              'Registros fotográficos com geolocalização quando disponível',
        ),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: ReportColors.borderSoft),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Row(
            children: [
              _mediaCountCellF70('Fotos', visibleMedia.length.toString(), f),
              _mediaCountCellF70(
                'Final',
                finalizationMedia.length.toString(),
                f,
              ),
              _mediaCountCellF70('Vídeo', '0', f),
              _mediaCountCellF70('Áudios', '0', f),
              _mediaCountCellF70(
                'Outros',
                _boCount(ctx.occurrence).toString(),
                f,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        if (visibleMedia.isEmpty && finalizationMedia.isEmpty)
          _emptyBox('Nenhuma mídia anexada aos eventos desta ocorrência.', f)
        else ...[
          if (visibleMedia.isNotEmpty) ..._buildMediaGridF70(visibleMedia, ctx),
          if (finalizationMedia.isNotEmpty) ...[
            if (visibleMedia.isNotEmpty) pw.SizedBox(height: 10),
            ReportPrimitives.styledSectionTitle(
              'FOTOS DA FINALIZAÇÃO',
              f,
              iconText: 'FIN',
            ),
            ..._buildFinalizationMediaGridF70(finalizationMedia, ctx),
          ],
        ],
        pw.SizedBox(height: 10),
        ReportPrimitives.styledSectionTitle('ANEXOS', f, iconText: 'ANX'),
        _attachmentCardF70(ctx),
      ],
    );
  }

  List<pw.Widget> _buildMediaGridF70(
    List<_PdfMediaItem> items,
    _OccurrencePdfContext ctx,
  ) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final first = items[i];
      final second = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _mediaCardF70(first, ctx)),
              if (second != null) ...[
                pw.SizedBox(width: 10),
                pw.Expanded(child: _mediaCardF70(second, ctx)),
              ] else
                pw.Spacer(),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  List<pw.Widget> _buildFinalizationMediaGridF70(
    List<_PdfFinalizationMediaItem> items,
    _OccurrencePdfContext ctx,
  ) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final first = items[i];
      final second = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _finalizationMediaCardF70(first, ctx)),
              if (second != null) ...[
                pw.SizedBox(width: 10),
                pw.Expanded(child: _finalizationMediaCardF70(second, ctx)),
              ] else
                pw.Spacer(),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  pw.Widget _mediaCountCellF70(String label, String value, PdfFonts fonts) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: _ink),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              label.toUpperCase(),
              style: _body(fonts, size: 6, color: _inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _mediaCardF70(_PdfMediaItem item, _OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final event = item.event;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: pw.Row(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: ReportColors.borderSoft),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(3),
                    ),
                  ),
                  child: pw.Text(
                    item.number.toString().padLeft(2, '0'),
                    style: _mono(f, size: 7.5, color: ReportColors.accent),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    _eventTitle(event),
                    maxLines: 1,
                    style: _bodyBold(f, size: 8.5),
                  ),
                ),
                pw.Text(
                  _formatTime(event.timestamp),
                  style: _mono(f, size: 7.5, color: _inkSoft),
                ),
              ],
            ),
          ),
          pw.Container(
            height: 108,
            color: _mediaBg,
            child: pw.Stack(
              children: [
                if (item.image != null)
                  pw.Positioned.fill(
                    child: pw.Image(item.image!, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Center(
                    child: pw.Text(
                      'imagem indisponível',
                      style: _body(f, size: 7.5, color: _inkFaint),
                    ),
                  ),
                pw.Positioned(
                  right: 6,
                  top: 6,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _green,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(3),
                      ),
                    ),
                    child: pw.Text(
                      'SINC',
                      style: _bodyBold(
                        f,
                        size: 6,
                        color: PdfInstitutionalColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: ReportColors.borderSoft, width: 0.5),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${_locationMain(ctx.occurrence)}\n${_gpsText(event.gpsLat, event.gpsLng, precision: 5)}',
                    style: _body(f, size: 6.5, color: _inkSoft),
                  ),
                ),
                pw.Text(
                  _accuracyText(ctx.occurrence.gpsAccuracy),
                  style: _mono(f, size: 6.5, color: _inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _finalizationMediaCardF70(
    _PdfFinalizationMediaItem item,
    _OccurrencePdfContext ctx,
  ) {
    final f = ctx.fonts;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: pw.Row(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: ReportColors.borderSoft),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(3),
                    ),
                  ),
                  child: pw.Text(
                    item.number.toString().padLeft(2, '0'),
                    style: _mono(f, size: 7.5, color: ReportColors.accent),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FINALIZAÇÃO',
                        maxLines: 1,
                        style: _bodyBold(f, size: 8.5),
                      ),
                      pw.Text(
                        'FOTO DO ENCERRAMENTO',
                        style: _body(f, size: 6, color: _inkFaint),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  _formatTime(
                    ctx.occurrence.finalizedAt ?? ctx.occurrence.updatedAt,
                  ),
                  style: _mono(f, size: 7.5, color: _inkSoft),
                ),
              ],
            ),
          ),
          pw.Container(
            height: 108,
            color: _mediaBg,
            child: pw.Stack(
              children: [
                if (item.image != null)
                  pw.Positioned.fill(
                    child: pw.Image(item.image!, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Center(
                    child: pw.Text(
                      'imagem indisponível',
                      style: _body(f, size: 7.5, color: _inkFaint),
                    ),
                  ),
                pw.Positioned(
                  right: 6,
                  top: 6,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: pw.BoxDecoration(
                      color: ReportColors.accent,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(3),
                      ),
                    ),
                    child: pw.Text(
                      'FINAL',
                      style: _bodyBold(
                        f,
                        size: 6,
                        color: PdfInstitutionalColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: ReportColors.borderSoft, width: 0.5),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${_locationMain(ctx.occurrence)}\n${_gpsText(ctx.occurrence.gpsLat, ctx.occurrence.gpsLng, precision: 5)}',
                    style: _body(f, size: 6.5, color: _inkSoft),
                  ),
                ),
                pw.Text(
                  _accuracyText(ctx.occurrence.gpsAccuracy),
                  style: _mono(f, size: 6.5, color: _inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _attachmentCardF70(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final boDetails = _detailsMap(
      ctx.occurrence.details,
      OccurrenceResult.boCreated,
    );
    final boNumber = boDetails?['bo_number']?.toString();
    final label = boNumber?.trim().isNotEmpty == true
        ? 'BO_$boNumber.pdf'
        : (_boCount(ctx.occurrence) > 0
              ? 'BO registrado — número não informado'
              : 'Sem anexos administrativos registrados');
    final meta = _boCount(ctx.occurrence) > 0
        ? 'Boletim de Ocorrência — documento relacionado'
        : 'Nenhum arquivo anexado no modelo atual';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 30,
            height: 30,
            decoration: pw.BoxDecoration(
              color: ReportColors.surface,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              border: pw.Border.all(color: ReportColors.borderSoft),
            ),
            child: pw.Center(
              child: pw.Text(
                'PDF',
                style: _bodyBold(f, size: 7.5, color: ReportColors.accent),
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: _bodyBold(f, size: 9)),
                pw.Text(meta, style: _body(f, size: 7, color: _inkFaint)),
              ],
            ),
          ),
          pw.Text(
            _boCount(ctx.occurrence) > 0 ? 'anexo lógico' : 'N/I',
            style: _mono(f, size: 7.5, color: _inkSoft),
          ),
        ],
      ),
    );
  }

  // ── Report / narrative ───────────────────────────────────────────────

  pw.Widget _buildReportSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final activeResults = ctx.occurrence.results
        .where((r) => r != OccurrenceResult.noOccurrence)
        .toList();
    final report = ctx.occurrence.finalReport?.trim();
    final resultCards = <pw.Widget>[
      if (activeResults.isEmpty)
        _resultCardF70(OccurrenceResult.noOccurrence, ctx)
      else
        ...activeResults.map((result) => _resultCardF70(result, ctx)),
      if (ctx.media.isNotEmpty) _resultCardF70(null, ctx),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'RESULTADOS',
          f,
          iconText: 'RES',
          subtitle: 'Desfechos formais registrados na finalização',
        ),
        ..._buildResultCardsGridF70(resultCards),
        pw.SizedBox(height: 10),
        ReportPrimitives.styledSectionTitle(
          'RELATO INSTITUCIONAL',
          f,
          iconText: 'REL',
          subtitle: 'Transcrição revisada pelo condutor',
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('ECFEFF'),
            border: pw.Border.all(color: PdfColor.fromHex('A5F3FC')),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            'TRANSCRIÇÃO DE ÁUDIO — REVISADA PELO CONDUTOR',
            style: _bodyBold(f, size: 7, color: ReportColors.accent),
          ),
        ),
        pw.SizedBox(height: 8),
        ..._buildReportParagraphsF70(report, f),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: ReportColors.surfaceSubtle,
            border: pw.Border.all(color: ReportColors.borderSoft, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            'Relato transcrito de áudio gravado em campo, quando aplicável, e revisado pelo condutor responsável antes da finalização.',
            style: _body(f, size: 7, color: _inkSoft),
          ),
        ),
      ],
    );
  }

  List<pw.Widget> _buildResultCardsGridF70(List<pw.Widget> cards) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final first = cards[i];
      final second = i + 1 < cards.length ? cards[i + 1] : null;
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: first),
              if (second != null) ...[
                pw.SizedBox(width: 10),
                pw.Expanded(child: second),
              ] else
                pw.Spacer(),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  List<pw.Widget> _buildReportParagraphsF70(String? report, PdfFonts f) {
    final paragraphs = _splitReportIntoParagraphs(report);
    return paragraphs.map((paragraph) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Container(
          padding: const pw.EdgeInsets.only(left: 10, top: 2, bottom: 2),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: ReportColors.accent, width: 2),
            ),
          ),
          child: pw.Text(
            paragraph,
            textAlign: pw.TextAlign.justify,
            style: _body(
              f,
              size: 9,
              color: PdfInstitutionalColors.timelineDark,
            ),
          ),
        ),
      );
    }).toList();
  }

  List<String> _splitReportIntoParagraphs(String? report) {
    if (report == null || report.trim().isEmpty) {
      return const ['Relato institucional não registrado na finalização.'];
    }
    final rawParagraphs = report.split(RegExp(r'\r?\n+'));
    final chunks = <String>[];
    for (final raw in rawParagraphs) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length <= 800) {
        chunks.add(trimmed);
      } else {
        var remaining = trimmed;
        while (remaining.length > 800) {
          var splitIndex = remaining.lastIndexOf('. ', 800);
          if (splitIndex == -1 || splitIndex < 200) {
            splitIndex = remaining.lastIndexOf(' ', 800);
          }
          if (splitIndex == -1 || splitIndex < 200) {
            splitIndex = 800;
          } else {
            splitIndex += 1;
          }
          chunks.add(remaining.substring(0, splitIndex).trim());
          remaining = remaining.substring(splitIndex).trim();
        }
        if (remaining.isNotEmpty) {
          chunks.add(remaining);
        }
      }
    }
    return chunks.isEmpty
        ? const ['Relato institucional não registrado na finalização.']
        : chunks;
  }

  pw.Widget _resultCardF70(
    OccurrenceResult? result,
    _OccurrencePdfContext ctx,
  ) {
    final f = ctx.fonts;
    final title = result == null ? 'Mídias registradas' : result.label;
    final desc = result == null
        ? '${ctx.media.length} foto(s) anexada(s) ao registro.'
        : _resultDescription(result, ctx.occurrence);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 22,
            height: 22,
            decoration: pw.BoxDecoration(
              color: ReportToneColors.of(ReportTone.positive).background,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Center(
              child: pw.Text(
                result == null ? 'M' : _resultMark(result),
                style: _bodyBold(
                  f,
                  size: 7.5,
                  color: ReportToneColors.of(ReportTone.positive).accent,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title.toUpperCase(), style: _bodyBold(f, size: 8)),
                pw.SizedBox(height: 2),
                pw.Text(desc, style: _body(f, size: 7.5, color: _inkSoft)),
              ],
            ),
          ),
          pw.Text(
            'OK',
            style: _bodyBold(
              f,
              size: 7,
              color: ReportToneColors.of(ReportTone.positive).accent,
            ),
          ),
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
        'Nada foi localizado ou constatado durante a atuação.',
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

  static String formatDrugDescription(dynamic raw) {
    if (raw is Map &&
        (raw.containsKey('type') ||
            raw.containsKey('tipo') ||
            raw.containsKey('weight_grams') ||
            raw.containsKey('quantidade'))) {
      raw = [raw];
    }
    if (raw is List && raw.isNotEmpty) {
      final entries = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((e) {
            final type = (e['type'] ?? e['tipo'] ?? 'substancia').toString();
            final hasWeight = e['weight_grams'] != null;
            final amount = (e['weight_grams'] ?? e['quantidade'] ?? '')
                .toString();
            if (amount.isEmpty) return type;
            return hasWeight ? '$type - $amount g' : '$type - $amount';
          })
          .join('; ');
      if (entries.isNotEmpty) return entries;
    }
    return 'Substancia analoga a entorpecente apreendida e registrada na ocorrencia.';
  }

  @visibleForTesting
  static String formatDrugDescriptionForTest(dynamic raw) =>
      formatDrugDescription(raw);

  String _drugDescription(dynamic raw) => formatDrugDescription(raw);

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

  // ── Validation / integrity / team / signatures ───────────────────────

  pw.Widget _buildValidationSection(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final createdAt = ctx.occurrence.finalizedAt ?? ctx.occurrence.updatedAt;
    // Keep integrity hash+QR together with admin metadata (avoid near-empty final page)
    final adminBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(height: 0.5, color: ReportColors.borderSoft),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _docInfoF70('ID do documento', ctx.docId, f, mono: true),
            _docInfoF70('Tipo', 'Registro Operacional K9', f),
            _docInfoF70(
              'Versão',
              'hash v${ctx.occurrence.hashVersion ?? 2}',
              f,
              mono: true,
            ),
            _docInfoF70('Criado em', _formatDateTime(createdAt), f, mono: true),
            _docInfoF70(
              'Sincronizado',
              _formatDateTime(ctx.occurrence.updatedAt),
              f,
              mono: true,
            ),
            _docInfoF70('Sistema', 'Canil K9 — GCM Limeira', f),
          ],
        ),
      ],
    );
    final hashRow = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _hashBoxF70(ctx)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _verificationBoxF70(ctx)),
      ],
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'INTEGRIDADE DO DOCUMENTO',
          f,
          iconText: 'INT',
          subtitle: 'Selo SHA-256 e verificação online',
        ),
        // Keep hash verification QR grouped with admin metadata below
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            hashRow,
            if (_shouldShowTeamAndSignatures(ctx)) ...[
              pw.SizedBox(height: 12),
              _buildTeamAndSignaturesSectionF70(ctx),
            ],
            pw.SizedBox(height: 10),
            adminBlock,
          ],
        ),
      ],
    );
  }

  bool _shouldShowTeamAndSignatures(_OccurrencePdfContext ctx) {
    return ctx.occurrence.team.length > 1 ||
        ctx.occurrence.team.any((member) => member.hasServiceDog) ||
        ctx.occurrence.hasVehicleCrew ||
        ctx.occurrence.signatures.isNotEmpty ||
        ctx.occurrence.status == OccurrenceStatus.finalizedWithPending;
  }

  pw.Widget _buildTeamAndSignaturesSectionF70(_OccurrencePdfContext ctx) {
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
        ReportPrimitives.styledSectionTitle(
          'EQUIPE E ASSINATURAS',
          f,
          iconText: 'EQ',
          subtitle: 'Guarnição da viatura e condutores responsáveis',
        ),
        if (ctx.occurrence.vehicleLabel?.trim().isNotEmpty == true) ...[
          _vehicleInfoLineF70(ctx),
          pw.SizedBox(height: 8),
        ],
        _teamTableF70(ctx, team),
        if (_serviceDogLabel(team).isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _serviceDogPresenceBoxF70(ctx, team),
        ],
        pw.SizedBox(height: 8),
        if (signedSignatures.isEmpty)
          _emptyBox('Nenhuma co-assinatura registrada para esta ocorrência.', f)
        else
          _signatureTableF70(ctx, signedSignatures),
        if (hasPending) ...[
          pw.SizedBox(height: 8),
          _pendingSignaturesBlockF70(ctx, pendingItems),
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

  pw.Widget _vehicleInfoLineF70(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final parts = <String>[
      ctx.occurrence.vehicleLabel?.trim() ?? '',
      ctx.occurrence.vehicleModel?.trim() ?? '',
      ctx.occurrence.vehicleUnit?.trim() ?? '',
    ].where((part) => part.isNotEmpty).toList();
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        'Viatura: ${parts.join(' — ')}',
        style: _bodyBold(f, size: 7.5, color: ReportColors.accent),
      ),
    );
  }

  String _serviceDogLabel(List<OccurrenceTeamMember> team) {
    for (final member in team) {
      final dogName = member.dogName?.trim();
      if (dogName == null || dogName.isEmpty) continue;
      final matricula = member.dogMatricula?.trim();
      final breed = member.dogBreed?.trim();
      return [
        'K9 $dogName',
        if (matricula != null && matricula.isNotEmpty) 'matrícula $matricula',
        if (breed != null && breed.isNotEmpty) breed,
      ].join(' — ');
    }
    return '';
  }

  pw.Widget _serviceDogPresenceBoxF70(
    _OccurrencePdfContext ctx,
    List<OccurrenceTeamMember> team,
  ) {
    final f = ctx.fonts;
    final serviceDog = _serviceDogLabel(team);
    final colors = ReportToneColors.of(ReportTone.positive);
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: colors.background,
        border: pw.Border.all(color: colors.border),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        '$serviceDog — membro K9 com presença atestada pela guarnição. O cão não assina; a presença é atestada pelos condutores.',
        style: _body(f, size: 7.5, color: colors.text),
      ),
    );
  }

  pw.Widget _teamTableF70(
    _OccurrencePdfContext ctx,
    List<OccurrenceTeamMember> team,
  ) {
    final f = ctx.fonts;
    return pw.Table(
      border: pw.TableBorder.all(color: ReportColors.borderSoft, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.3),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(2.2),
      },
      children: [
        _pdfTableHeaderF70(ctx, ['Condutor', 'Papel', 'RA', 'K9']),
        for (final member in team)
          pw.TableRow(
            children: [
              _pdfTableCellF70(
                _memberName(member, fallbackName: ctx.handlerName),
                f,
                bold: member.role == TeamRole.titular,
              ),
              _pdfTableCellF70(
                member.role == TeamRole.titular ? 'Titular' : 'Integrante',
                f,
              ),
              _pdfTableCellF70(member.handlerId, f, mono: true),
              _pdfTableCellF70(_memberDogLabel(member), f),
            ],
          ),
      ],
    );
  }

  String _memberDogLabel(OccurrenceTeamMember member) {
    final dogName = member.dogName?.trim();
    if (dogName == null || dogName.isEmpty) return 'Sem K9 vinculado';
    final matricula = member.dogMatricula?.trim();
    return matricula != null && matricula.isNotEmpty
        ? 'K9 $dogName — mat. $matricula'
        : 'K9 $dogName';
  }

  pw.Widget _signatureTableF70(
    _OccurrencePdfContext ctx,
    List<OccurrenceSignature> signatures,
  ) {
    final f = ctx.fonts;
    return pw.Table(
      border: pw.TableBorder.all(color: ReportColors.borderSoft, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.0),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.8),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(2.4),
      },
      children: [
        _pdfTableHeaderF70(ctx, [
          'Nome',
          'RA',
          'Data/hora UTC',
          'Método',
          'Hash da assinatura',
        ]),
        for (final signature in signatures)
          pw.TableRow(
            children: [
              _pdfTableCellF70(_signatureMemberName(ctx, signature), f),
              _pdfTableCellF70(signature.handlerId, f, mono: true),
              _pdfTableCellF70(_formatUtc(signature.signedAt), f, mono: true),
              _pdfTableCellF70(
                _signatureMethodLabel(signature.signatureMethod),
                f,
              ),
              _pdfTableCellF70(signature.signatureHash, f, mono: true, size: 6),
            ],
          ),
      ],
    );
  }

  pw.Widget _pendingSignaturesBlockF70(
    _OccurrencePdfContext ctx,
    List<_PendingSignaturePdfItem> items,
  ) {
    final f = ctx.fonts;
    final colors = ReportToneColors.of(ReportTone.attention);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: colors.background,
        border: pw.Border.all(color: colors.border),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PENDÊNCIAS DE ASSINATURA',
            style: _bodyBold(f, size: 8, color: colors.text),
          ),
          pw.SizedBox(height: 6),
          for (final item in items) ...[
            pw.Text(
              '${_memberName(item.member)} (RA ${item.member.handlerId})',
              style: _bodyBold(f, size: 8, color: _ink),
            ),
            pw.Text(
              item.reason,
              style: _body(f, size: 7.5, color: colors.text),
            ),
            if (item.signature?.reason?.trim().isNotEmpty == true)
              pw.Text(
                'Registro: ${item.signature!.reason}',
                style: _body(f, size: 7, color: _inkSoft),
              ),
            pw.SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  pw.TableRow _pdfTableHeaderF70(
    _OccurrencePdfContext ctx,
    List<String> labels,
  ) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: ReportColors.surfaceSubtle),
      children: labels
          .map(
            (label) => _pdfTableCellF70(
              label,
              ctx.fonts,
              bold: true,
              color: ReportColors.textSecondary,
            ),
          )
          .toList(),
    );
  }

  pw.Widget _pdfTableCellF70(
    String text,
    PdfFonts fonts, {
    bool bold = false,
    bool mono = false,
    double size = 7.2,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
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
    return 'Convidado em ${_formatUtc(ctx.occurrence.signatureRequestAt)}; não assinou no prazo de ${_formatUtc(ctx.occurrence.signatureDeadline)}.';
  }

  String _formatUtc(DateTime? value) {
    if (value == null) return 'data não registrada';
    return '${DateFormat('dd/MM/yyyy HH:mm').format(value.toUtc())} UTC';
  }

  pw.Widget _hashBoxF70(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final storedHash = ctx.occurrence.integrityHash?.trim();
    final hasHash = storedHash != null && storedHash.isNotEmpty;
    final hash = hasHash ? storedHash : 'Hash ainda não calculado';
    final verdict = ctx.integrityVerdict;
    final isBroken = verdict?.status == IntegrityStatus.broken;
    final isIntact = verdict?.status == IntegrityStatus.intact;
    final stateColor = isBroken
        ? ReportToneColors.of(ReportTone.critical).text
        : isIntact
        ? ReportToneColors.of(ReportTone.positive).text
        : ReportToneColors.of(ReportTone.attention).text;
    final stateBg = isIntact
        ? ReportToneColors.of(ReportTone.positive).background
        : ReportToneColors.of(ReportTone.attention).background;
    final stateBorder = isIntact
        ? ReportToneColors.of(ReportTone.positive).border
        : ReportToneColors.of(ReportTone.attention).border;
    final stateSymbol = isBroken
        ? '!'
        : isIntact
        ? 'OK'
        : '!';
    final stateText = _integrityStateText(hasHash: hasHash, verdict: verdict);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'HASH DE INTEGRIDADE',
            style: _bodyBold(f, size: 7.5, color: ReportColors.accent),
          ),
          pw.SizedBox(height: 8),
          _tinyLabel('SHA-256 — conteúdo operacional', f),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: ReportColors.surfaceSubtle,
              border: pw.Border.all(color: ReportColors.borderSoft, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(hash, style: _mono(f, size: 7.5, color: _ink)),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: stateBg,
              border: pw.Border.all(color: stateBorder),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  stateSymbol,
                  style: _bodyBold(f, size: 8, color: stateColor),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    stateText,
                    style: _body(
                      f,
                      size: 7.5,
                      color: isIntact ? _inkSoft : stateColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isBroken && verdict?.recomputedHash?.isNotEmpty == true) ...[
            pw.SizedBox(height: 6),
            _tinyLabel('SHA-256 recalculado pelo verificador local', f),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: ReportColors.surfaceSubtle,
                border: pw.Border.all(
                  color: ReportToneColors.of(ReportTone.attention).border,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                verdict!.recomputedHash!,
                style: _mono(
                  f,
                  size: 7,
                  color: ReportToneColors.of(ReportTone.critical).text,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @visibleForTesting
  static String integrityStateTextForTest({
    required bool hasHash,
    required IntegrityVerdict? verdict,
  }) => OccurrencePdfGenerator()._integrityStateText(
    hasHash: hasHash,
    verdict: verdict,
  );

  @visibleForTesting
  static int totalMediaCountForTest({
    required int eventMediaCount,
    required int finalizationMediaCount,
  }) => eventMediaCount + finalizationMediaCount;

  @visibleForTesting
  static bool isEmptyMediaStateForTest({
    required bool visibleMediaEmpty,
    required bool finalizationMediaEmpty,
  }) => visibleMediaEmpty && finalizationMediaEmpty;

  String _integrityStateText({
    required bool hasHash,
    required IntegrityVerdict? verdict,
  }) {
    if (!hasHash) {
      return 'PENDENTE\nFinalize a ocorrência para cristalizar o hash.';
    }
    if (verdict == null) {
      return 'SELO ARMAZENADO\nVerificação local indisponível neste PDF. Confirme pelo QR Code.';
    }
    return switch (verdict.status) {
      IntegrityStatus.intact =>
        'ÍNTEGRO\nIntegridade documental confirmada pelo verificador oficial.',
      IntegrityStatus.broken =>
        'SELO QUEBRADO\nHash recalculado não confere com o selo armazenado.',
      IntegrityStatus.legacy =>
        'SELO LEGADO\nVersão de hash não recalculável pelo verificador atual.',
      IntegrityStatus.unsealed =>
        'PENDENTE\nOcorrência sem selo de integridade armazenado.',
      IntegrityStatus.unverified =>
        'VERIFICAÇÃO NÃO DISPONÍVEL\nNão foi possível consultar o verificador oficial neste momento. Tente novamente com conexão.',
    };
  }

  pw.Widget _verificationBoxF70(_OccurrencePdfContext ctx) {
    final f = ctx.fonts;
    final code = _verificationCode(ctx);
    final url = _verificationUrl(ctx);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'VERIFICAÇÃO ONLINE',
            style: _bodyBold(f, size: 7.5, color: ReportColors.accent),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.BarcodeWidget(
                data: url,
                barcode: pw.Barcode.qrCode(),
                width: 62,
                height: 62,
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Escaneie para recalcular o hash documental no servidor. A página também permite verificar fotos no Storage sob demanda.',
                      style: _body(f, size: 7, color: _inkSoft),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      code,
                      style: _mono(f, size: 7.5, color: ReportColors.accent),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      url,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: _mono(f, size: 6.5, color: _inkFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: ReportToneColors.of(ReportTone.positive).background,
              border: pw.Border.all(
                color: ReportToneColors.of(ReportTone.positive).border,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'Consulta rápida: hash documental. Verificação profunda: baixa as mídias do Storage e compara os SHA-256 registrados.',
              style: _body(
                f,
                size: 6.5,
                color: ReportToneColors.of(ReportTone.positive).text,
              ),
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

  pw.Widget _docInfoF70(
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
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            maxLines: 2,
            style: pw.TextStyle(
              font: mono ? fonts.monoRegular : fonts.bold,
              fontSize: 8,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  // ── Amendments ───────────────────────────────────────────────────────

  pw.Widget _buildAmendmentsSection(_OccurrencePdfContext ctx) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    // Keep heading + intro + first amendment together to avoid orphan heading
    final first = ctx.amendments.isNotEmpty ? ctx.amendments.first : null;
    final rest = ctx.amendments.length > 1
        ? ctx.amendments.sublist(1)
        : const <Amendment>[];
    final headerGroup = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ReportPrimitives.styledSectionTitle(
          'ADITAMENTOS / RETIFICAÇÕES',
          ctx.fonts,
          iconText: 'ADI',
          subtitle:
              'Retificações registradas após o selamento — registro original permanece íntegro',
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: pw.BoxDecoration(
            color: ReportToneColors.of(ReportTone.attention).background,
            border: pw.Border.all(
              color: ReportToneColors.of(ReportTone.attention).border,
            ),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            'As retificações abaixo foram registradas após o selamento do documento original. O registro original permanece íntegro e inalterado — cada aditamento possui hash de integridade próprio.',
            style: pw.TextStyle(
              font: ctx.fonts.regular,
              fontSize: 7.5,
              color: ReportToneColors.of(ReportTone.attention).text,
              lineSpacing: 1.8,
            ),
          ),
        ),
        pw.SizedBox(height: 10),
        if (first != null) _buildAmendmentEntryF70(ctx, first, dateFmt),
      ],
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        headerGroup,
        ...rest.map(
          (amendment) => _buildAmendmentEntryF70(ctx, amendment, dateFmt),
        ),
      ],
    );
  }

  pw.Widget _buildAmendmentEntryF70(
    _OccurrencePdfContext ctx,
    Amendment amendment,
    DateFormat dateFmt,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: ReportToneColors.of(ReportTone.attention).border,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Retificação #${amendment.sequenceNumber}',
                style: pw.TextStyle(
                  font: ctx.fonts.bold,
                  fontSize: 9.5,
                  color: ReportToneColors.of(ReportTone.attention).text,
                ),
              ),
              pw.Text(
                dateFmt.format(amendment.createdAt),
                style: pw.TextStyle(
                  font: ctx.fonts.monoRegular,
                  fontSize: 7.5,
                  color: ReportColors.textMuted,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            '${amendment.createdByName} (RA: ${amendment.createdByRa})',
            style: pw.TextStyle(
              font: ctx.fonts.regular,
              fontSize: 8,
              color: ReportColors.textSecondary,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: ReportColors.surfaceSubtle,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MOTIVO',
                  style: pw.TextStyle(
                    font: ctx.fonts.bold,
                    fontSize: 7,
                    color: ReportColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  amendment.reason,
                  style: pw.TextStyle(
                    font: ctx.fonts.regular,
                    fontSize: 9,
                    color: ReportColors.textPrimary,
                    lineSpacing: 1.8,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          ...amendment.corrections.entries.map(
            (entry) => _buildCorrectionRowF70(ctx, entry.key, entry.value),
          ),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: pw.BoxDecoration(
              color: ReportColors.surfaceSubtle,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'HASH SHA-256: ',
                  style: pw.TextStyle(
                    font: ctx.fonts.bold,
                    fontSize: 6.5,
                    color: ReportColors.textMuted,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    amendment.integrityHash,
                    style: pw.TextStyle(
                      font: ctx.fonts.monoRegular,
                      fontSize: 6,
                      color: ReportColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data:
                  '$_verificationBaseUrl/${amendment.occurrenceId}?a=${amendment.id}&h=${amendment.integrityHash.substring(0, 16)}',
              width: 58,
              height: 58,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCorrectionRowF70(
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
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              font: ctx.fonts.bold,
              fontSize: 7,
              color: ReportToneColors.of(ReportTone.attention).text,
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
                  fontSize: 7.5,
                  color: ReportColors.textMuted,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  '${correction.oldValue ?? '(vazio)'}',
                  style: pw.TextStyle(
                    font: ctx.fonts.regular,
                    fontSize: 7.5,
                    color: ReportColors.textSecondary,
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
                  fontSize: 7.5,
                  color: ReportColors.textMuted,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  '${correction.newValue}',
                  style: pw.TextStyle(
                    font: ctx.fonts.bold,
                    fontSize: 7.5,
                    color: ReportColors.textPrimary,
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
                fontSize: 7,
                color: ReportColors.textMuted,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PdfDisplacementPoint {
  final OccurrenceLocation location;
  final double x;
  final double y;

  const _PdfDisplacementPoint({
    required this.location,
    required this.x,
    required this.y,
  });
}

class _OccurrencePdfContext {
  final Occurrence occurrence;
  final List<OccurrenceEvent> events;
  final Dog? dog;
  final String handlerName;
  final String handlerRa;
  final String docId;
  final PdfFonts fonts;
  final List<_PdfMediaItem> media;
  final List<_PdfFinalizationMediaItem> finalizationMedia;
  final pw.ImageProvider? staticMapImage;
  final pw.ImageProvider? displacementMapImage;
  final List<OccurrenceLocation> locations;
  final List<Amendment> amendments;
  final IntegrityVerdict? integrityVerdict;

  const _OccurrencePdfContext({
    required this.occurrence,
    required this.events,
    this.dog,
    required this.handlerName,
    required this.handlerRa,
    required this.docId,
    required this.fonts,
    required this.media,
    required this.finalizationMedia,
    required this.staticMapImage,
    required this.displacementMapImage,
    required this.locations,
    this.amendments = const [],
    this.integrityVerdict,
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

class _PdfFinalizationMediaItem {
  final int number;
  final String url;
  final pw.ImageProvider? image;

  const _PdfFinalizationMediaItem({
    required this.number,
    required this.url,
    required this.image,
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
