import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/core/services/pdf_generator/pdf_common_widgets.dart';
import 'package:canil_gcm/core/services/pdf_generator/template/template.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F70 Design System V1 — Tokens', () {
    test('Cores canônicas estão em conformidade com o congelamento', () {
      expect(ReportColors.surface, PdfColor.fromHex('FFFFFF'));
      expect(ReportColors.surfaceSubtle, PdfColor.fromHex('F8FAFC'));
      expect(ReportColors.textPrimary, PdfColor.fromHex('0F172A'));
      expect(ReportColors.textSecondary, PdfColor.fromHex('334155'));
      expect(ReportColors.textMuted, PdfColor.fromHex('64748B'));
      expect(ReportColors.borderSoft, PdfColor.fromHex('E2E8F0'));
      expect(ReportColors.borderStrong, PdfColor.fromHex('94A3B8'));
      expect(ReportColors.accent, PdfColor.fromHex('0A8E9D'));
    });

    test('6 tons genéricos de status são expressos sem acoplamento de domínio', () {
      expect(ReportTone.values.length, 6);
      expect(ReportTone.values, containsAll([
        ReportTone.positive,
        ReportTone.attention,
        ReportTone.critical,
        ReportTone.neutral,
        ReportTone.info,
        ReportTone.unknown,
      ]));

      for (final tone in ReportTone.values) {
        final colors = ReportToneColors.of(tone);
        expect(colors.background, isNotNull);
        expect(colors.border, isNotNull);
        expect(colors.text, isNotNull);
        expect(colors.accent, isNotNull);
      }
    });

    test('Escala de espaçamento é estritamente crescente e em pt', () {
      expect(ReportSpacing.xxs, 2.0);
      expect(ReportSpacing.xs, 4.0);
      expect(ReportSpacing.sm, 8.0);
      expect(ReportSpacing.md, 12.0);
      expect(ReportSpacing.lg, 16.0);
      expect(ReportSpacing.xl, 24.0);
      expect(ReportSpacing.xxl, 32.0);
    });

    test('Métricas de página A4 e limites de slots respeitam requisitos de impressão', () {
      expect(ReportPageMetrics.portraitWidthMm, 210.0);
      expect(ReportPageMetrics.portraitHeightMm, 297.0);
      expect(ReportPageMetrics.portraitMarginLeftMm, 15.0);
      expect(ReportPageMetrics.portraitMarginTopMm, 12.0);
      expect(ReportPageMetrics.portraitMarginRightMm, 12.0);
      expect(ReportPageMetrics.portraitMarginBottomMm, 12.0);

      expect(ReportPageMetrics.landscapeWidthMm, 297.0);
      expect(ReportPageMetrics.landscapeHeightMm, 210.0);
      expect(ReportPageMetrics.landscapeMarginMm, 12.0);

      expect(ReportPageMetrics.productMarkMaxWidthMm, 28.0);
      expect(ReportPageMetrics.productMarkMaxHeightMm, 12.0);
      expect(ReportPageMetrics.productMarkSafeAreaMm, 2.0);

      expect(ReportPageMetrics.issuerMarkMaxWidthMm, 18.0);
      expect(ReportPageMetrics.issuerMarkMaxHeightMm, 18.0);
      expect(ReportPageMetrics.issuerMarkSafeAreaMm, 2.0);
    });
  });

  group('F70 Design System V1 — Branding Slots & Scenarios', () {
    test('Resolução correta dos 4 cenários de branding', () {
      final dummySlot = ReportImageSlot(bytes: Uint8List.fromList([1, 2, 3]));

      // 1. Both
      final both = ReportBranding(
        productMarkImage: dummySlot,
        institutionalIssuerMarkImage: dummySlot,
        showProductMark: true,
        showInstitutionalIssuerMark: true,
      );
      expect(both.scenario, BrandingScenario.both);

      // 2. ProductMark only
      final productOnly = ReportBranding(
        productMarkImage: dummySlot,
        institutionalIssuerMarkImage: null,
        showProductMark: true,
        showInstitutionalIssuerMark: false,
      );
      expect(productOnly.scenario, BrandingScenario.productMarkOnly);

      // 3. InstitutionalIssuerMark only
      final issuerOnly = ReportBranding(
        productMarkImage: null,
        institutionalIssuerMarkImage: dummySlot,
        showProductMark: false,
        showInstitutionalIssuerMark: true,
      );
      expect(issuerOnly.scenario, BrandingScenario.institutionalIssuerMarkOnly);

      // 4. Neither
      final neither = const ReportBranding(
        productMarkImage: null,
        institutionalIssuerMarkImage: null,
        showProductMark: false,
        showInstitutionalIssuerMark: false,
      );
      expect(neither.scenario, BrandingScenario.neither);
    });

    test('ProductMark usa fallback textual "K9 Ops" na ausência de imagem e não cria logo sintético', () {
      final branding = const ReportBranding(productMarkImage: null);
      expect(branding.textualFallback, 'K9 Ops');
    });
  });

  group('F70 Design System V1 — Metadata', () {
    test('GENERATED_AT é universalmente obrigatório e DOCUMENT_ID é condicional', () {
      final now = DateTime(2026, 10, 6, 12, 0);

      // Apenas obrigatório
      final minimal = ReportMetadata(generatedAt: now);
      expect(minimal.generatedAt, now);
      expect(minimal.documentId, isNull);
      expect(minimal.operatorName, isNull);

      // Com condicional e opcionais
      final complete = ReportMetadata(
        generatedAt: now,
        documentId: 'DOC-2026-001',
        operatorName: 'Inspetor Silva',
        callsign: 'K9-VTR-01',
      );
      expect(complete.documentId, 'DOC-2026-001');
      expect(complete.operatorName, 'Inspetor Silva');
      expect(complete.callsign, 'K9-VTR-01');
    });
  });

  group('F70 Design System V1 — Arquétipos', () {
    test('Suporte estruturado aos 5 arquétipos frozen', () {
      final institutional = ReportArchetypeConfig.institutional();
      expect(institutional.archetype, ReportArchetype.institutional);
      expect(institutional.headerVariant, HeaderVariant.institutional);
      expect(institutional.requiresAuditBlock, isTrue);
      expect(institutional.requiresSignatures, isTrue);

      final operational = ReportArchetypeConfig.operational();
      expect(operational.archetype, ReportArchetype.operational);
      expect(operational.supportsTimeline, isTrue);
      expect(operational.supportsIdentityBlock, isTrue);
      expect(operational.requiresAuditBlock, isTrue);

      final clinical = ReportArchetypeConfig.clinical();
      expect(clinical.archetype, ReportArchetype.clinical);
      expect(clinical.requiresSignatures, isTrue);
      expect(clinical.supportsIdentityBlock, isTrue);

      final analytical = ReportArchetypeConfig.analytical();
      expect(analytical.archetype, ReportArchetype.analytical);
      expect(analytical.supportsDataTable, isTrue);

      final tabular = ReportArchetypeConfig.tabular();
      expect(tabular.archetype, ReportArchetype.tabular);
      expect(tabular.orientation, PageOrientation.landscape);
      expect(tabular.supportsDataTable, isTrue);
    });
  });

  group('F70 Design System V1 — End-to-End PDF Builder & Primitives', () {
    test('Gera documento PDF válido com todas as primitivas acopladas', () async {
      final fonts = await PdfFonts.load();
      final now = DateTime(2026, 10, 6, 14, 30);

      final metadata = ReportMetadata(
        generatedAt: now,
        documentId: 'RO-K9-2026-0042',
        operatorName: 'GCM 1CL Silva',
        callsign: 'RO-02',
        dogIdentity: 'Kira (Pastor Alemão)',
      );

      // Imagem fictícia de 1x1 PNG válida
      final samplePng = Uint8List.fromList([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
        0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
      ]);

      final builder = ReportTemplateBuilder(
        title: 'Registro Operacional de Emprego K9',
        subtitle: 'Apoio tático em busca de entorpecentes',
        category: 'Operacional',
        metadata: metadata,
        disclaimer: 'Documento oficial gerado eletronicamente.',
      );

      // 1. EntityIdentityBlock
      builder.addWidget(
        ReportPrimitives.entityIdentityBlock(
          EntityIdentityData(
            title: 'Kira — Pastor Alemão',
            subtitle: 'K9 Titular de Patrulhamento',
            statusLabel: 'Operacional',
            statusTone: ReportTone.positive,
            fields: const [
              EntityIdentityField(label: 'Microchip', value: '981098102938475', isMonospace: true),
              EntityIdentityField(label: 'Condutor', value: 'GCM Silva - Matr. 1234'),
              EntityIdentityField(label: 'Nascimento', value: '14/03/2021', isMonospace: true),
            ],
          ),
          fonts,
        ),
      );

      // 2. SummaryCard
      builder.addWidget(
        ReportPrimitives.summaryCard(
          const SummaryCardData(
            title: 'Resumo da Operação',
            description: 'Emprego com indicação positiva e localização de substâncias ilícitas.',
            bulletItems: [
              'Área de busca: Terreno baldio perimetral',
              'Comportamento do K9: Foco imediato e indicação passiva (sentar)',
              'Apoio da guarnição RO-02 com preservação de cadeia de custódia',
            ],
            tone: ReportTone.positive,
          ),
          fonts,
        ),
      );

      // 3. MetricCard
      builder.addWidget(
        pw.Row(
          children: [
            pw.Expanded(
              child: ReportPrimitives.metricCard(
                const MetricCardData(
                  label: 'Tempo de Busca',
                  value: '14',
                  unit: 'min',
                  tone: ReportTone.info,
                ),
                fonts,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: ReportPrimitives.metricCard(
                const MetricCardData(
                  label: 'Apreensões',
                  value: '3',
                  unit: 'invólucros',
                  trend: '+100%',
                  tone: ReportTone.positive,
                ),
                fonts,
              ),
            ),
          ],
        ),
      );

      builder.addWidget(pw.SizedBox(height: ReportSpacing.md));

      // 4. TimelineSection
      builder.addWidget(
        ReportPrimitives.informationSection(
          'Cronologia dos Fatos',
          [
            ReportPrimitives.timelineSection(
              [
                TimelineNodeData(
                  timeLabel: '09:15',
                  title: 'Chegada ao local',
                  description: 'Isolamento da área pela guarnição de apoio.',
                  tone: ReportTone.info,
                ),
                TimelineNodeData(
                  timeLabel: '09:20',
                  title: 'Início da varredura olfativa',
                  description: 'Condutor libera K9 Kira com guia longa.',
                  tone: ReportTone.neutral,
                ),
                TimelineNodeData(
                  timeLabel: '09:34',
                  title: 'Alerta e indicação positiva',
                  description: 'K9 adota postura passiva junto ao muro dos fundos.',
                  tone: ReportTone.positive,
                ),
              ],
              fonts,
            ),
          ],
          fonts,
        ),
      );

      // 5. DataTable com zebra e alinhamento
      builder.addWidget(
        ReportPrimitives.informationSection(
          'Itens Localizados',
          [
            ReportPrimitives.dataTable(
              const DataTableData(
                columns: [
                  DataTableColumn(header: 'Item', alignment: DataTableCellAlignment.left, flex: 1.5),
                  DataTableColumn(header: 'Tipo', alignment: DataTableCellAlignment.left, flex: 1),
                  DataTableColumn(header: 'Hora', alignment: DataTableCellAlignment.center, isMonospace: true, flex: 0.8),
                  DataTableColumn(header: 'Peso Est. (g)', alignment: DataTableCellAlignment.right, isMonospace: true, flex: 1),
                ],
                rows: [
                  DataTableRow(cells: ['Invólucro 01', 'Maconha', '09:34', '142.5']),
                  DataTableRow(cells: ['Invólucro 02', 'Cocaína', '09:36', '48.0']),
                  DataTableRow(cells: ['Invólucro 03', 'Crack', '09:37', '22.0']),
                ],
              ),
              fonts,
            ),
          ],
          fonts,
        ),
      );

      // 6. EvidenceBlock (BoxFit.contain estrito)
      builder.addWidget(
        ReportPrimitives.evidenceBlock(
          EvidenceItemData(
            image: ReportImageSlot(bytes: samplePng),
            caption: 'Registro fotográfico da indicação passiva do K9 no ponto de ocultação.',
            timestamp: '06/10/2026 09:35',
            metadata: 'Câmera Corporal VTR-02',
          ),
          fonts,
        ),
      );

      // 7. ObservationBlock
      builder.addWidget(
        ReportPrimitives.observationBlock(
          const ObservationBlockData(
            text: 'O K9 apresentou excelente vigor físico e foco durante todo o trabalho.',
          ),
          fonts,
        ),
      );

      // 8. Signatures & CoSignatureBlock
      builder.addWidget(
        ReportPrimitives.coSignatureBlock(
          const [
            SignatureData(name: 'GCM Silva', role: 'Condutor K9', identifier: 'Matr. 1234'),
            SignatureData(name: 'Inspetor Santos', role: 'Encarregado de Equipe', identifier: 'Matr. 5678'),
          ],
          fonts,
        ),
      );

      // 9. AuditBlock (QR code + hash + URL agnóstica)
      builder.addWidget(
        ReportPrimitives.auditBlock(
          const AuditData(
            verificationUrl: 'https://k9ops.com/verificar?doc=RO-K9-2026-0042',
            hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            algorithm: 'SHA-256',
            documentId: 'RO-K9-2026-0042',
          ),
          fonts,
        ),
      );

      final pdfBytes = await builder.buildPdf(customFonts: fonts);

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
      // Início canônico do cabeçalho de arquivo PDF
      expect(pdfBytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Gera PDF para arquétipo Tabular em modo paisagem (landscape)', () async {
      final fonts = await PdfFonts.load();
      final builder = ReportTemplateBuilder.forArchetype(
        archetype: ReportArchetype.tabular,
        title: 'Inventário Geral de Efetivo K9',
        metadata: ReportMetadata(generatedAt: DateTime(2026, 10, 6)),
      );

      builder.addWidget(
        ReportPrimitives.dataTable(
          const DataTableData(
            columns: [
              DataTableColumn(header: 'Nome K9', alignment: DataTableCellAlignment.left),
              DataTableColumn(header: 'Raça', alignment: DataTableCellAlignment.left),
              DataTableColumn(header: 'Condutor Titular', alignment: DataTableCellAlignment.left),
            ],
            rows: [
              DataTableRow(cells: ['Kira', 'Pastor Alemão', 'GCM Silva']),
              DataTableRow(cells: ['Thor', 'Pastor Belga Malinois', 'GCM Souza']),
            ],
          ),
          fonts,
        ),
      );

      final pdfBytes = await builder.buildPdf(customFonts: fonts);
      expect(pdfBytes.take(4), orderedEquals('%PDF'.codeUnits));
    });

    test('Gera documento PDF com Header Tático Dark Navy, Gráfico Vetorial e Tabela Rica', () async {
      final fonts = await PdfFonts.load();
      final now = DateTime(2026, 10, 6, 15, 0);

      final builder = ReportTemplateBuilder(
        title: 'Histórico Bioestatístico e Ponderal K9',
        subtitle: 'Acompanhamento Físico Operacional',
        category: 'Saúde & Prontidão',
        organization: 'GCM Limeira',
        motto: 'DISCIPLINA · PROTEÇÃO · RESULTADO',
        statusLabel: 'DENTRO DA FAIXA IDEAL',
        statusTone: ReportTone.positive,
        useDarkFooter: true,
        metadata: ReportMetadata(
          generatedAt: now,
          documentId: 'BIO-K9-2026-0099',
          dogIdentity: 'Thor (Malinois)',
        ),
        archetypeConfig: ReportArchetypeConfig.clinicalTactical(),
      );

      // 1. Identity com tags operacionais
      builder.addWidget(
        ReportPrimitives.entityIdentityBlock(
          EntityIdentityData(
            title: 'Thor',
            subtitle: 'Pastor Belga Malinois',
            tags: const ['CÃO DE TRABALHO', 'INTERVENÇÃO'],
            statusLabel: 'ATIVO',
            statusTone: ReportTone.positive,
            fields: const [
              EntityIdentityField(label: 'Microchip', value: '981098102938499', isMonospace: true),
              EntityIdentityField(label: 'Faixa Ideal', value: '28.0 kg a 32.0 kg'),
            ],
          ),
          fonts,
        ),
      );

      // 2. Título de Seção Estilizado
      builder.addWidget(
        ReportPrimitives.styledSectionTitle(
          'Evolução Ponderal (Gráfico)',
          fonts,
          iconText: 'EVO',
        ),
      );

      // 3. Gráfico de Evolução de Peso Vetorial
      builder.addWidget(
        ReportPrimitives.weightTrendChart(
          points: [
            WeightChartPoint(date: DateTime(2026, 7, 1), weight: 29.5),
            WeightChartPoint(date: DateTime(2026, 8, 1), weight: 30.0),
            WeightChartPoint(date: DateTime(2026, 9, 1), weight: 30.4),
            WeightChartPoint(date: DateTime(2026, 10, 1), weight: 30.2),
          ],
          idealMin: 28.0,
          idealMax: 32.0,
          fonts: fonts,
        ),
      );

      // 4. Tabela Rica com Badges e Zebra
      builder.addWidget(
        ReportPrimitives.styledSectionTitle(
          'Registros de Pesagem',
          fonts,
          iconText: 'LOG',
        ),
      );

      builder.addWidget(
        ReportPrimitives.richDataTable(
          RichDataTableData(
            columns: const [
              DataTableColumn(header: 'Data', alignment: DataTableCellAlignment.center, isMonospace: true, flex: 1.2),
              DataTableColumn(header: 'Peso', alignment: DataTableCellAlignment.right, isMonospace: true, flex: 1.0),
              DataTableColumn(header: 'Variação', alignment: DataTableCellAlignment.right, isMonospace: true, flex: 1.0),
              DataTableColumn(header: 'Status', alignment: DataTableCellAlignment.center, flex: 1.0),
            ],
            rows: [
              RichDataTableRow(
                cells: [
                  const RichTableCell.text('01/10/2026', isMonospace: true),
                  const RichTableCell.text('30.2 kg', isBold: true, isMonospace: true),
                  const RichTableCell.text('-0.2 kg', isBold: true, isMonospace: true),
                  const RichTableCell.badge(badgeText: 'CONFORME', badgeTone: ReportTone.positive),
                ],
              ),
              RichDataTableRow(
                cells: [
                  const RichTableCell.text('01/09/2026', isMonospace: true),
                  const RichTableCell.text('30.4 kg', isBold: true, isMonospace: true),
                  const RichTableCell.text('+0.4 kg', isBold: true, isMonospace: true),
                  const RichTableCell.badge(badgeText: 'ATENÇÃO', badgeTone: ReportTone.attention),
                ],
              ),
            ],
          ),
          fonts,
        ),
      );

      // 5. Auditoria com trackingCode
      builder.addWidget(
        ReportPrimitives.auditBlock(
          const AuditData(
            verificationUrl: 'https://k9ops.com/v/BIO-K9-2026-0099',
            hash: 'abcd1234ef567890abcd1234ef567890abcd1234ef567890abcd1234ef567890',
            documentId: 'BIO-K9-2026-0099',
            trackingCode: 'AUDIT-THOR-99182',
            description: 'Documento assinado digitalmente e registrado em cadeia de custódia imutável.',
          ),
          fonts,
        ),
      );

      final pdfBytes = await builder.buildPdf(customFonts: fonts);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.take(4), orderedEquals('%PDF'.codeUnits));
    });
  });

  group('F70 Design System V1 — Tokens Táticos K9 Ops V2', () {
    test('Tokens Dark Navy e Ciano estão em conformidade canônica', () {
      expect(ReportColors.darkNavy, PdfColor.fromHex('0A1A24'));
      expect(ReportColors.darkNavySurface, PdfColor.fromHex('0E1F2C'));
      expect(ReportColors.darkNavyBorder, PdfColor.fromHex('1A3345'));
      expect(ReportColors.cyanAccent, PdfColor.fromHex('2BB6C4'));
      expect(ReportColors.goldAccent, PdfColor.fromHex('E5A93C'));
    });
  });
}
