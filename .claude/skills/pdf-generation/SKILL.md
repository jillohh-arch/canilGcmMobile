---
name: pdf-generation
description: Padrão de geração de PDFs institucionais do app Canil K9 (Ocorrência, Carteira de Vacinação, Histórico de Peso, Relatório Nutricional, Histórico Mensal). Use quando implementar qualquer geração de PDF do app. Define estrutura visual formal light mode, hash de integridade SHA-256, QR code de verificação, identidade institucional e linguagem formal.
---

# Geração de PDFs · Padrão Institucional

## Filosofia

PDFs são o **produto institucional final** do app. Saem do tema dark do app e entram 
em **light mode formal**. Vão pra:

- Auditor da Controladoria
- Comandante da GCM
- Promotor (se virar processo)
- Defesa do condutor
- Gestor no painel React
- Veterinário (histórico do cão)

Todos esses cenários pedem formato institucional formal.

## Pacotes Flutter necessários

```yaml
dependencies:
  pdf: ^3.x.x           # geração de PDF
  printing: ^5.x.x      # preview e share
  qr_flutter: ^4.x.x    # QR codes
  crypto: ^3.x.x        # SHA-256
```

## Os 5 PDFs do app

| PDF | Cor identidade | Uso |
|-----|----------------|-----|
| Ocorrência | Ciano #0A8E9D | Documento institucional formal |
| Carteira de Vacinação | Ciano #0A8E9D | Pra veterinário ou auditoria |
| Histórico de Peso | Azul #2C6E91 | Acompanhamento clínico |
| Relatório Nutricional | Laranja #C25E1F | **Defesa profissional crítica** |
| Histórico Mensal | Roxo #5A4080 | Prestação de contas mensal |

## Paleta de PDFs (light mode)

```dart
class PdfColors {
  // Fundo e textos
  static final background = PdfColor.fromHex('FFFFFF');
  static final textPrimary = PdfColor.fromHex('1A1A1A');
  static final textSecondary = PdfColor.fromHex('4A5560');
  static final textTertiary = PdfColor.fromHex('6C7A83');
  
  // Cor identidade (varia por tipo)
  static final cyan = PdfColor.fromHex('0A8E9D');     // Ocorrência, Vacinação
  static final blue = PdfColor.fromHex('2C6E91');     // Peso
  static final orange = PdfColor.fromHex('C25E1F');   // Nutrição
  static final purple = PdfColor.fromHex('5A4080');   // Histórico
  
  // Auxiliares
  static final greenInstitutional = PdfColor.fromHex('2A9D52');
  static final amberWarning = PdfColor.fromHex('B88A0C');
  static final lightGray = PdfColor.fromHex('F8FAFB');
  static final divider = PdfColor.fromHex('D8E0E5');
}
```

## Estrutura padrão

### Capa (sempre)

```
┌────────────────────────────┐
│                            │
│       [Brasão GCM]         │ ← placeholder até ter real
│                            │
│  GUARDA CIVIL MUNICIPAL    │
│       DE LIMEIRA           │
│                            │
│  CANIL K9 · [SUBTÍTULO]    │
│                            │
│  ═══════════════════       │
│                            │
│  TIPO DO DOCUMENTO         │ ← "REGISTRO DE OCORRÊNCIA"
│  Título Principal          │ ← "Faro em Veículo"
│  SUBTÍTULO COLORIDO        │ ← "FARO ANTIDROGAS"
│                            │
│  ┌──────────────────────┐  │
│  │ Data: 12/05/2026     │  │
│  │ Início: 09:42        │  │
│  │ Duração: 1h 36min    │  │
│  └──────────────────────┘  │
│                            │
│  [REG: 2026/05/0142-K9]    │ ← ID único destacado
│                            │
│  BINÔMIO RESPONSÁVEL       │
│  GCM Jilles Ragonha        │
│  RA 691755                 │
└────────────────────────────┘
```

### Páginas internas (sempre)

**Header padrão:**
```
[🛡 mini] GCM LIMEIRA · [TIPO DO DOC]    REG XXXX
─────────────────────────────────────  (linha cor identidade)
```

**Footer padrão:**
```
─────────────────────────────────────
GCM Limeira · Canil K9 · [Tipo]   Página X de Y
```

### Última página (sempre)

- Trilha de auditoria visível
- Card de integridade com hash SHA-256
- QR Code com link de verificação
- Caixa de assinatura tradicional

## Tipografia

```dart
// Fontes a carregar no PDF
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<PdfFonts> _loadFonts() async {
  return PdfFonts(
    regular: await PdfGoogleFonts.interRegular(),
    medium: await PdfGoogleFonts.interMedium(),
    bold: await PdfGoogleFonts.interBold(),
    monospace: await PdfGoogleFonts.sourceSansProRegular(),
  );
}
```

**Tamanhos:**
- Título principal: 24pt
- Subtítulo (tipo doc): 11pt letterSpacing 2pt
- Seções: 12-13pt bold
- Corpo: 10-11pt
- Auxiliar: 9pt
- Micro (IDs, hashes): 7-8pt monospace

## Hash SHA-256

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';

String calculateDocumentHash(Map<String, dynamic> docData) {
  // Serializar de forma determinística
  final orderedKeys = docData.keys.toList()..sort();
  final orderedData = {for (var k in orderedKeys) k: docData[k]};
  
  final jsonString = jsonEncode(orderedData);
  final bytes = utf8.encode(jsonString);
  final hash = sha256.convert(bytes);
  
  return hash.toString();
}
```

**Regras:**
- Hash calculado UMA VEZ ao finalizar documento
- Armazenado em `occurrences.{id}.integrity_hash`
- Re-gerações do PDF usam o MESMO hash (se nada mudou no documento)
- Hash diferente em re-geração = documento foi alterado, deve haver entrada no audit_trail

## QR Code de verificação

Aponta pra Firebase Hosting com URL pública:

```
https://canilk9-limeira.web.app/v/{occurrence_id}
```

Implementação:
```dart
import 'package:qr_flutter/qr_flutter.dart';

pw.Widget _buildQrCode(String url) {
  return pw.BarcodeWidget(
    data: url,
    barcode: pw.Barcode.qrCode(),
    width: 70,
    height: 70,
  );
}
```

A página de verificação (no Firebase Hosting) mostra:
- ID do documento
- Hash esperado
- Status (válido/adulterado)
- Sem expor conteúdo sensível

## Geração de mapa estático (Ocorrência)

```dart
import 'package:http/http.dart' as http;

Future<Uint8List> _generateStaticMap({
  required double lat,
  required double lng,
  required String apiKey,
}) async {
  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/staticmap'
    '?center=$lat,$lng'
    '&zoom=17'
    '&size=600x400'
    '&maptype=roadmap'
    '&markers=color:red%7C$lat,$lng'
    '&key=$apiKey'
  );
  final response = await http.get(url);
  return response.bodyBytes;
}
```

API Key fica em variável de ambiente, nunca commitada.

## Esqueleto de gerador de PDF

```dart
// core/services/pdf_generator/occurrence_pdf_generator.dart

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class OccurrencePdfGenerator {
  final PdfColor identityColor = PdfColor.fromHex('0A8E9D');

  Future<Uint8List> generate(Occurrence occurrence) async {
    final pdf = pw.Document();
    final fonts = await _loadFonts();
    final hash = calculateDocumentHash(occurrence.toJson());
    
    // Página 1: Capa
    pdf.addPage(_buildCoverPage(occurrence, fonts));
    
    // Página 2: Identificação
    pdf.addPage(_buildIdentificationPage(occurrence, fonts));
    
    // Página 3: Ocorrência e localização
    pdf.addPage(await _buildLocationPage(occurrence, fonts));
    
    // Página 4+: Timeline de eventos (pode quebrar em múltiplas)
    pdf.addPage(_buildTimelinePage(occurrence, fonts));
    
    // Página: Relato e resultado
    pdf.addPage(_buildReportAndResultPage(occurrence, fonts));
    
    // Página final: Auditoria e assinatura
    pdf.addPage(_buildAuditPage(occurrence, fonts, hash));
    
    return pdf.save();
  }
  
  pw.Page _buildCoverPage(Occurrence occ, PdfFonts fonts) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (context) {
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildBrand(fonts),
            _buildTitleSection(occ, fonts),
            _buildMetaCard(occ, fonts),
            _buildDocId(occ, fonts),
            _buildResponsible(occ, fonts),
          ],
        );
      },
    );
  }
  
  // ... outras páginas
}
```

## Linguagem formal institucional

**SEM:**
- ❌ "Faro do Bono em veículo"
- ❌ "Cão indicou que tinha droga"
- ❌ "Pegamos 18g de maconha"

**COM:**
- ✅ "Faro operacional do cão K9 Bono em veículo"
- ✅ "Indicação positiva do cão K9 em conformidade com protocolo"
- ✅ "Apreensão de substância análoga à maconha · peso 18g"

Procure tom de **relatório técnico**, não conversa informal.

## Cabeçalho institucional padrão

```dart
pw.Widget _buildHeader(String docType, String docId, PdfColor color) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: color, width: 2),
      ),
    ),
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      children: [
        pw.Container(
          width: 22,
          height: 22,
          decoration: pw.BoxDecoration(
            color: color,
            shape: pw.BoxShape.circle,
          ),
          child: pw.Center(
            child: pw.Text(
              '🛡',
              style: pw.TextStyle(color: PdfColors.white, fontSize: 12),
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          'GCM LIMEIRA · $docType',
          style: pw.TextStyle(
            color: color,
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        pw.Spacer(),
        pw.Text(
          docId,
          style: pw.TextStyle(
            color: PdfColors.grey700,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
```

## Card de integridade (última página)

```dart
pw.Widget _buildIntegrityCard(String hash, DateTime generatedAt) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('1A5560'),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'HASH SHA-256',
          style: pw.TextStyle(
            color: PdfColor.fromHex('4DD0E1'),
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          hash,
          style: const pw.TextStyle(
            color: PdfColors.white,
            fontSize: 8,
            font: pw.Font.courier(),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Gerado em',
              style: pw.TextStyle(
                color: PdfColors.white.shade(0.6),
                fontSize: 9,
              ),
            ),
            pw.Text(
              _formatDateTime(generatedAt),
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
            ),
          ],
        ),
      ],
    ),
  );
}
```

## Salvamento e compartilhamento

```dart
// Salvar no Storage após gerar
final pdfBytes = await OccurrencePdfGenerator().generate(occurrence);

final ref = FirebaseStorage.instance.ref(
  'incidents/${occurrence.id}/pdf_final.pdf',
);
await ref.putData(pdfBytes);

final url = await ref.getDownloadURL();

await _firestore.collection('occurrences').doc(occurrence.id).update({
  'pdf_export_url': url,
  'pdf_generated_at': FieldValue.serverTimestamp(),
});

// Compartilhar
import 'package:printing/printing.dart';
await Printing.sharePdf(bytes: pdfBytes, filename: 'ocorrencia_${occurrence.id}.pdf');
```

## Princípios visuais sempre aplicados

1. ✅ Light mode (branco/preto/cor de detalhe)
2. ✅ Cor identidade por tipo de PDF
3. ✅ Linguagem formal institucional
4. ✅ Sem emojis decorativos no corpo
5. ✅ Tabelas com zebra striping
6. ✅ Hierarquia visual clara (títulos > subtítulos > corpo)
7. ✅ Margens generosas (30mm em A4)
8. ✅ Identificação completa em todas as páginas
9. ✅ Hash SHA-256 verificável
10. ✅ QR code de verificação online