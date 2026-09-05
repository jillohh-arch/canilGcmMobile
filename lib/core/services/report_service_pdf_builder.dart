part of 'report_service.dart';

class _ReportFonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font black;

  const _ReportFonts({
    required this.regular,
    required this.bold,
    required this.black,
  });
}

class _ActivityReportPdfBuilder {
  final Dog dog;
  final String conductorCallsign;
  final List<ReportEntry> entries;
  final String institution;
  final String period;

  const _ActivityReportPdfBuilder({
    required this.dog,
    required this.conductorCallsign,
    required this.entries,
    required this.institution,
    required this.period,
  });

  Future<Uint8List> build() async {
    final fonts = await _loadFonts();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    final sortedEntries = [...entries]
      ..sort((a, b) => a.date.compareTo(b.date));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        header: (context) =>
            _buildReportHeader(institution, fonts.black, fonts.bold),
        footer: (context) => _buildReportFooter(context, fonts.regular),
        build: (context) => _buildPage(sortedEntries, fonts),
      ),
    );

    return pdf.save();
  }

  Future<_ReportFonts> _loadFonts() async {
    return _ReportFonts(
      regular: await PdfGoogleFonts.interRegular(),
      bold: await PdfGoogleFonts.interBold(),
      black: await PdfGoogleFonts.interExtraBold(),
    );
  }

  List<pw.Widget> _buildPage(
    List<ReportEntry> sortedEntries,
    _ReportFonts fonts,
  ) {
    return [
      _sectionDivider(),
      pw.SizedBox(height: 12),
      _buildDogConductorBlock(fonts),
      pw.SizedBox(height: 20),
      _buildReportTitle(fonts),
      pw.SizedBox(height: 10),
      _buildActivityTable(sortedEntries, fonts),
      pw.SizedBox(height: 20),
      _buildTotalLabel(sortedEntries.length, fonts),
      pw.SizedBox(height: 48),
      _buildSignatureBlock(fonts),
    ];
  }

  pw.Widget _buildDogConductorBlock(_ReportFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfInstitutionalColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfInstitutionalColors.grey300),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _infoBlock(
            'CÃO K9',
            dog.name.toUpperCase(),
            fonts.bold,
            fonts.regular,
          ),
          pw.SizedBox(width: 24),
          _infoBlock(
            'MATRÍCULA',
            dog.registrationNumber ?? 'N/A',
            fonts.bold,
            fonts.regular,
          ),
          pw.SizedBox(width: 24),
          _infoBlock('RAÇA', dog.breed, fonts.bold, fonts.regular),
          pw.SizedBox(width: 24),
          _infoBlock('CONDUTOR', conductorCallsign, fonts.bold, fonts.regular),
          pw.Spacer(),
          _infoBlock(
            'PERÍODO',
            period.isNotEmpty ? period : _formatReportDate(DateTime.now()),
            fonts.bold,
            fonts.regular,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildReportTitle(_ReportFonts fonts) {
    return pw.Text(
      'RELATÓRIO DE ATIVIDADES TÁTICAS',
      style: pw.TextStyle(
        font: fonts.black,
        fontSize: 13,
        color: PdfInstitutionalColors.grey800,
        letterSpacing: 1.5,
      ),
    );
  }

  pw.Widget _buildActivityTable(
    List<ReportEntry> sortedEntries,
    _ReportFonts fonts,
  ) {
    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(72),
        1: pw.FixedColumnWidth(42),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FlexColumnWidth(2.5),
      },
      border: pw.TableBorder.all(
        color: PdfInstitutionalColors.grey300,
        width: 0.5,
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfInstitutionalColors.grey800),
          children: [
            'DATA',
            'HORA',
            'TIPO',
            'LOCAL',
            'OBSERVAÇÕES',
          ].map((header) => _tableHeader(header, fonts.bold)).toList(),
        ),
        ...sortedEntries.asMap().entries.map((entry) {
          final odd = entry.key.isOdd;
          final reportEntry = entry.value;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: odd
                  ? PdfInstitutionalColors.grey50
                  : PdfInstitutionalColors.white,
            ),
            children: [
              _tableCell(_formatReportDate(reportEntry.date), fonts.regular),
              _tableCell(_formatReportTime(reportEntry.date), fonts.regular),
              _tableCell(reportEntry.type, fonts.regular),
              _tableCell(reportEntry.location, fonts.regular),
              _tableCell(reportEntry.observations, fonts.regular),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildTotalLabel(int total, _ReportFonts fonts) {
    return pw.Text(
      'Total de registros: $total',
      style: pw.TextStyle(
        font: fonts.bold,
        fontSize: 10,
        color: PdfInstitutionalColors.grey600,
      ),
    );
  }

  pw.Widget _buildSignatureBlock(_ReportFonts fonts) {
    return pw.Row(
      children: [
        _signatureColumn(
          label: 'Assinatura do GCM Responsável',
          value: conductorCallsign.toUpperCase(),
          fonts: fonts,
        ),
        pw.SizedBox(width: 40),
        _signatureColumn(
          label: 'Data / Hora do Relatório',
          value: _formatReportDate(DateTime.now()),
          fonts: fonts,
        ),
      ],
    );
  }

  pw.Widget _signatureColumn({
    required String label,
    required String value,
    required _ReportFonts fonts,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(height: 1, color: PdfInstitutionalColors.grey700),
          pw.SizedBox(height: 6),
          pw.Text(
            label,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 10,
              color: PdfInstitutionalColors.grey600,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
        ],
      ),
    );
  }
}
