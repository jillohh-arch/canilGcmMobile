part of 'dog_prontuario_tab_screen.dart';

extension _DogProntuarioDocumentos on _DogProntuarioTabScreenState {
  Widget _buildDocumentosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          'LAUDOS E DOCUMENTOS',
          count: _documents.isNotEmpty ? _documents.length : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              if (_documents.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(5),
                    border: Border.all(color: Colors.white.withAlpha(15)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: _documents.asMap().entries.map((entry) {
                      final index = entry.key;
                      final doc = entry.value;
                      final isLast = index == _documents.length - 1;
                      return _buildDocumentRow(doc, isLast: isLast);
                    }).toList(),
                  ),
                ),
              if (_documents.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(5),
                    border: Border.all(color: Colors.white.withAlpha(15)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: _textMuted, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Nenhum documento anexado',
                        style: GoogleFonts.inter(
                          color: _textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              // Botão anexar
              GestureDetector(
                onTap: () => _showUploadDialog(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _cyanAccent.withAlpha(10),
                    border: Border.all(
                      color: _cyanAccent.withAlpha(77),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: _cyanAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Anexar laudo ou documento',
                        style: GoogleFonts.inter(
                          color: _cyanAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentRow(DogDocument doc, {required bool isLast}) {
    return GestureDetector(
      onTap: () => _openDocument(doc),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: Color(0x0AFFFFFF))),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _cyanAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_docIcon(doc.tipo), color: _cyanAccent, size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.nome,
                    style: GoogleFonts.inter(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (doc.emissor != null && doc.emissor!.isNotEmpty)
                    Text(
                      doc.emissor!,
                      style: GoogleFonts.inter(
                        color: _textMuted,
                        fontSize: 11,
                      ),
                    )
                  else if (doc.descricao.isNotEmpty)
                    Text(
                      doc.descricao,
                      style: GoogleFonts.inter(
                        color: _textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              DateFormat('MM/yyyy').format(doc.dataUpload),
              style: GoogleFonts.inter(
                color: _dimMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDocument(DogDocument doc) {
    HapticFeedback.lightImpact();
    final url = doc.url;
    if (url.isEmpty) return;

    final ext = url.split('.').last.split('?').first.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);

    if (isImage) {
      // Abre imagem em tela cheia
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) {
            return FadeTransition(
              opacity: animation,
              child: Scaffold(
                backgroundColor: Colors.black87,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: Text(
                    doc.nome,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } else {
      // Para PDFs e outros, mostra um dialog com link
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0E1A1F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            doc.nome,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc.descricao.isNotEmpty)
                Text(doc.descricao, style: GoogleFonts.inter(color: _textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                'Tipo: ${doc.tipo}',
                style: GoogleFonts.inter(color: _textMuted, fontSize: 11),
              ),
              Text(
                'Data: ${DateFormat('dd/MM/yyyy').format(doc.dataUpload)}',
                style: GoogleFonts.inter(color: _textMuted, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Fechar', style: GoogleFonts.inter(color: _cyanAccent)),
            ),
          ],
        ),
      );
    }
  }

  void _showUploadDialog() {
    HapticFeedback.lightImpact();
    final nomeController = TextEditingController();
    final descricaoController = TextEditingController();
    String tipoSelecionado = 'laudo';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1A1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16, 20, 16,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Anexar documento',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Nome
                  TextField(
                    controller: nomeController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Nome do documento',
                      labelStyle: GoogleFonts.inter(color: _textMuted, fontSize: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withAlpha(30)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _cyanAccent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Descrição
                  TextField(
                    controller: descricaoController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Descrição (opcional)',
                      labelStyle: GoogleFonts.inter(color: _textMuted, fontSize: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withAlpha(30)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _cyanAccent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tipo
                  Row(
                    children: [
                      Text('Tipo:', style: GoogleFonts.inter(color: _textMuted, fontSize: 12)),
                      const SizedBox(width: 10),
                      _buildTipoChip('laudo', tipoSelecionado, (v) {
                        setModalState(() => tipoSelecionado = v);
                      }),
                      const SizedBox(width: 6),
                      _buildTipoChip('certificado', tipoSelecionado, (v) {
                        setModalState(() => tipoSelecionado = v);
                      }),
                      const SizedBox(width: 6),
                      _buildTipoChip('documento', tipoSelecionado, (v) {
                        setModalState(() => tipoSelecionado = v);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Botão selecionar arquivo
                  GestureDetector(
                    onTap: () async {
                      final nome = nomeController.text.trim();
                      if (nome.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Informe o nome do documento')),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      await _pickAndUploadFile(
                        nome: nome,
                        descricao: descricaoController.text.trim(),
                        tipo: tipoSelecionado,
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _cyanAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload_file, color: AppTheme.background, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'SELECIONAR ARQUIVO',
                            style: GoogleFonts.inter(
                              color: AppTheme.background,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTipoChip(String tipo, String selected, ValueChanged<String> onTap) {
    final isActive = tipo == selected;
    return GestureDetector(
      onTap: () => onTap(tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? _cyanAccent.withAlpha(26) : Colors.transparent,
          border: Border.all(
            color: isActive ? _cyanAccent : Colors.white.withAlpha(30),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          tipo[0].toUpperCase() + tipo.substring(1),
          style: GoogleFonts.inter(
            color: isActive ? _cyanAccent : _textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadFile({
    required String nome,
    required String descricao,
    required String tipo,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );

    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    final file = File(filePath);
    final dogId = _lastDogId;
    if (dogId == null) return;

    // Mostra loading
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enviando documento...'),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      final newDoc = await _service.uploadDocument(
        dogId: dogId,
        nome: nome,
        descricao: descricao,
        tipo: tipo,
        file: file,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento anexado com sucesso!')),
      );

      setState(() {
        _documents.insert(0, newDoc);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    }
  }

  IconData _docIcon(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'laudo':
        return Icons.medical_information_outlined;
      case 'certificado':
        return Icons.workspace_premium_outlined;
      case 'documento':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
