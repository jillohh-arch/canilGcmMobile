import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';

class TeamAndSignaturesSection {
  static pw.Widget build(
    pw.Document _,
    List<OccurrenceTeamMember> team,
    List<OccurrenceSignature> signatures,
    bool hasPendingSignatures,
  ) {
    final signedSignatures =
        signatures
            .where((signature) => signature.status == SignatureStatus.signed)
            .toList()
          ..sort((a, b) => a.handlerId.compareTo(b.handlerId));
    final orderedTeam = List<OccurrenceTeamMember>.from(team)
      ..sort((a, b) => a.handlerId.compareTo(b.handlerId));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('EQUIPE RESPONSAVEL'),
        pw.SizedBox(height: 8),
        _teamTable(orderedTeam),
        pw.SizedBox(height: 16),
        _sectionTitle('ASSINATURAS'),
        pw.SizedBox(height: 8),
        pw.Text(
          'Este registro foi co-assinado pelos condutores abaixo. O K9 tem presenca atestada pela guarnicao.',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        _signatureTable(signedSignatures),
        if (hasPendingSignatures) ...[
          pw.SizedBox(height: 16),
          _pendingSection(),
        ],
        pw.SizedBox(height: 20),
      ],
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 1, color: PdfColors.grey300),
        ),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _teamTable(List<OccurrenceTeamMember> team) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
      },
      children: [
        _headerRow(['Nome', 'Funcao', 'RA/K9']),
        for (final member in team)
          pw.TableRow(
            children: [
              _cell(member.displayName ?? 'Condutor ${member.handlerId}'),
              _cell(
                member.role == TeamRole.titular ? 'Titular' : 'Integrante',
                bold: member.role == TeamRole.titular,
              ),
              _cell(_memberRaAndDog(member), bold: true),
            ],
          ),
      ],
    );
  }

  static pw.Widget _signatureTable(List<OccurrenceSignature> signatures) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(3),
      },
      children: [
        _headerRow([
          'Nome/RA',
          'Data/Hora UTC',
          'Método',
          'Hash da Assinatura',
        ]),
        for (final signature in signatures)
          pw.TableRow(
            children: [
              _cell('Condutor ${signature.handlerId}'),
              _cell(
                signature.signedAt == null
                    ? '-'
                    : '${DateFormat('dd/MM/yyyy HH:mm').format(signature.signedAt!.toUtc())} UTC',
              ),
              _cell(signature.signatureMethod.toMap().toUpperCase()),
              _cell(signature.signatureHash, monospace: true),
            ],
          ),
      ],
    );
  }

  static String _memberRaAndDog(OccurrenceTeamMember member) {
    final dogName = member.dogName?.trim();
    final dogMatricula = member.dogMatricula?.trim();
    return [
      'RA ${member.handlerId}',
      if (dogName != null && dogName.isNotEmpty)
        dogMatricula != null && dogMatricula.isNotEmpty
            ? 'K9 $dogName mat. $dogMatricula'
            : 'K9 $dogName',
    ].join('\n');
  }

  static pw.TableRow _headerRow(List<String> labels) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: labels.map((label) => _cell(label, bold: true)).toList(),
    );
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool monospace = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: monospace ? 8 : 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: monospace ? pw.Font.courier() : null,
        ),
      ),
    );
  }

  static pw.Widget _pendingSection() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.amber700, width: 2),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.amber50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PENDENCIAS DE ASSINATURA',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.amber900,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Convidado em data registrada na ocorrência; não assinou no prazo definido.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.amber900),
          ),
        ],
      ),
    );
  }
}
