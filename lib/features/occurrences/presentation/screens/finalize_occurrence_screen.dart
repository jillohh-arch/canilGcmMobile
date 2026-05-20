import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/speech_dictation_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';

class FinalizeOccurrenceScreen extends StatefulWidget {
  final String occurrenceId;
  final String typeName;
  final String durationLabel;
  final int eventCount;
  final String dogName;
  final String handlerName;
  final String? locationAddress;

  const FinalizeOccurrenceScreen({
    super.key,
    required this.occurrenceId,
    required this.typeName,
    required this.durationLabel,
    required this.eventCount,
    required this.dogName,
    required this.handlerName,
    this.locationAddress,
  });

  @override
  State<FinalizeOccurrenceScreen> createState() =>
      _FinalizeOccurrenceScreenState();
}

class _FinalizeOccurrenceScreenState extends State<FinalizeOccurrenceScreen> {
  final _pageController = PageController();
  final _reportController = TextEditingController();
  final _speechService = SpeechDictationService();

  int _currentStep = 0;
  bool _isListening = false;
  bool _isFinalizing = false;

  // Passo 2
  final Set<OccurrenceResult> _selectedResults = {};

  // Passo 3
  final Map<String, Map<String, TextEditingController>> _detailControllers = {};
  final List<_DrugEntry> _drugEntries = [];

  static const _drugTypes = ['Maconha', 'Cocaína', 'Crack', 'Ecstasy', 'Outros'];

  @override
  void dispose() {
    _pageController.dispose();
    _reportController.dispose();
    _speechService.stop();
    for (final map in _detailControllers.values) {
      for (final ctrl in map.values) {
        ctrl.dispose();
      }
    }
    for (final entry in _drugEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  // ─── Navigation ─────────────────────────────────────────────────────

  void _goNext() {
    if (_currentStep == 0 && _reportController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preencha o relato para avançar',
              style: GoogleFonts.inter()),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_currentStep == 1 && _selectedResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selecione pelo menos um resultado',
              style: GoogleFonts.inter()),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // ─── Speech ─────────────────────────────────────────────────────────

  Future<void> _toggleSpeech() async {
    if (_isListening) {
      _speechService.stop();
      setState(() => _isListening = false);
    } else {
      final started = await _speechService.start(
        controller: _reportController,
        onListeningStarted: () => setState(() => _isListening = true),
        onListeningStopped: () => setState(() => _isListening = false),
      );
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Microfone não disponível',
                style: GoogleFonts.inter()),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ─── Results ────────────────────────────────────────────────────────

  void _toggleResult(OccurrenceResult result) {
    setState(() {
      if (result == OccurrenceResult.noOccurrence) {
        if (_selectedResults.contains(result)) {
          _selectedResults.remove(result);
        } else {
          _selectedResults.clear();
          _selectedResults.add(result);
          for (final e in _drugEntries) {
            e.dispose();
          }
          _drugEntries.clear();
        }
      } else {
        _selectedResults.remove(OccurrenceResult.noOccurrence);
        if (_selectedResults.contains(result)) {
          _selectedResults.remove(result);
          if (result == OccurrenceResult.drugSeized) {
            for (final e in _drugEntries) {
              e.dispose();
            }
            _drugEntries.clear();
          }
        } else {
          _selectedResults.add(result);
          if (result == OccurrenceResult.drugSeized &&
              _drugEntries.isEmpty) {
            _drugEntries.add(_DrugEntry());
          }
        }
      }
    });
  }

  // ─── Details ────────────────────────────────────────────────────────

  TextEditingController _getDetailController(String resultKey, String field) {
    _detailControllers.putIfAbsent(resultKey, () => {});
    _detailControllers[resultKey]!.putIfAbsent(
        field, () => TextEditingController());
    return _detailControllers[resultKey]![field]!;
  }

  void _addDrugEntry() {
    setState(() {
      _drugEntries.add(_DrugEntry());
    });
  }

  void _removeDrugEntry(int index) {
    setState(() {
      _drugEntries[index].dispose();
      _drugEntries.removeAt(index);
    });
  }

  Map<String, dynamic>? _buildDetails() {
    final details = <String, dynamic>{};
    for (final result in _selectedResults) {
      if (result == OccurrenceResult.noOccurrence ||
          result == OccurrenceResult.supportProvided) {
        continue;
      }
      final key = result.toMap();

      // Drogas: lista dinâmica
      if (result == OccurrenceResult.drugSeized) {
        final drugs = <Map<String, dynamic>>[];
        for (final entry in _drugEntries) {
          final type = entry.type ?? '';
          final weight = entry.weightController.text.trim();
          if (type.isNotEmpty || weight.isNotEmpty) {
            drugs.add({
              'type': type,
              'weight_grams': weight,
            });
          }
        }
        if (drugs.isNotEmpty) details[key] = drugs;
        continue;
      }

      final fields = _detailControllers[key];
      if (fields == null) continue;
      final map = <String, dynamic>{};
      for (final entry in fields.entries) {
        final val = entry.value.text.trim();
        if (val.isNotEmpty) map[entry.key] = val;
      }
      if (map.isNotEmpty) details[key] = map;
    }
    return details.isNotEmpty ? details : null;
  }

  // ─── Finalize ───────────────────────────────────────────────────────

  Future<void> _finalize() async {
    setState(() => _isFinalizing = true);
    HapticFeedback.heavyImpact();

    try {
      final vm = context.read<OccurrenceViewModel>();
      final report = _reportController.text.trim();
      final results = _selectedResults.toList();
      final details = _buildDetails();

      final hashInput =
          '$report|${results.map((r) => r.toMap()).join(',')}|$details';
      final hash = sha256.convert(utf8.encode(hashInput)).toString();

      await vm.finalizeOccurrence(
        id: widget.occurrenceId,
        integrityHash: hash,
        finalReport: report,
        results: results,
        details: details,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OccurrenceConfirmationScreen(
              data: OccurrenceConfirmationData(
                occurrenceId: widget.occurrenceId,
                typeName: widget.typeName,
                durationLabel: widget.durationLabel,
                locationAddress: widget.locationAddress,
                dogName: widget.dogName,
                handlerName: widget.handlerName,
                eventCount: widget.eventCount,
                results: results,
                details: details,
                integrityHash: hash,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  // ─── Draft ──────────────────────────────────────────────────────────

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1A1F),
        title: Text('Salvar como rascunho?',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
          'Você poderá retomar a finalização depois.',
          style: GoogleFonts.inter(
              color: Colors.white.withAlpha(200), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: Text('DESCARTAR',
                style: GoogleFonts.inter(
                    color: AppTheme.error, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final vm = context.read<OccurrenceViewModel>();
              final updates = <String, dynamic>{
                'status': 'finalizing',
              };
              if (_reportController.text.trim().isNotEmpty) {
                updates['final_report'] = _reportController.text.trim();
              }
              if (_selectedResults.isNotEmpty) {
                updates['results'] =
                    _selectedResults.map((r) => r.toMap()).toList();
              }
              await vm.updateOccurrence(widget.occurrenceId, updates);
              if (mounted) Navigator.of(context).pop();
            },
            child: Text('SALVAR RASCUNHO',
                style: GoogleFonts.inter(
                    color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showExitDialog();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildContextCard(),
              _buildProgressBar(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep1(),
                    _buildStep2(),
                    _buildStep3(),
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showExitDialog,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FINALIZAR OCORRÊNCIA',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Passo ${_currentStep + 1} de 3',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withAlpha(40)),
      ),
      child: Row(
        children: [
          Text('🛡', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${widget.typeName} · ${widget.durationLabel} · ${widget.eventCount} evento${widget.eventCount != 1 ? 's' : ''}',
              style: GoogleFonts.inter(
                color: Colors.white.withAlpha(200),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: List.generate(3, (i) {
          final Color color;
          if (i < _currentStep) {
            color = const Color(0xFF2ECC71);
          } else if (i == _currentStep) {
            color = AppTheme.primary;
          } else {
            color = Colors.white.withAlpha(30);
          }
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFooter() {
    final isLast = _currentStep == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: Colors.white.withAlpha(10))),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _goBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withAlpha(40)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('‹ VOLTAR',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isFinalizing
                  ? null
                  : (isLast ? _finalize : _goNext),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLast
                    ? const Color(0xFF2ECC71)
                    : AppTheme.primary,
                disabledBackgroundColor: Colors.white.withAlpha(30),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isFinalizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isLast ? '✓ CONCLUIR' : 'PRÓXIMO ›',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 1: Relato ─────────────────────────────────────────────────

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RELATO INSTITUCIONAL',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _toggleSpeech,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isListening
                    ? AppTheme.error.withAlpha(20)
                    : AppTheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isListening
                      ? AppTheme.error.withAlpha(80)
                      : AppTheme.primary.withAlpha(60),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _isListening ? AppTheme.error : AppTheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isListening ? 'PARAR GRAVAÇÃO' : '🎙 GRAVAR RELATO',
                    style: GoogleFonts.inter(
                      color:
                          _isListening ? AppTheme.error : AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isListening)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ouvindo...',
                    style: GoogleFonts.inter(
                      color: AppTheme.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'ou digite diretamente:',
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(120),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reportController,
            maxLines: 8,
            minLines: 5,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'Equipe foi acionada às... descreva o que aconteceu...',
              hintStyle:
                  GoogleFonts.inter(color: Colors.white.withAlpha(60)),
              filled: true,
              fillColor: Colors.white.withAlpha(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(20)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(20)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Caracteres: ${_reportController.text.length}',
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(80),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2: Resultados ─────────────────────────────────────────────

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESULTADO DA OCORRÊNCIA',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Marque todos que se aplicam',
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(100),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: OccurrenceResult.values.map((result) {
              final selected = _selectedResults.contains(result);
              return _ResultCard(
                result: result,
                selected: selected,
                onTap: () => _toggleResult(result),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_selectedResults.isNotEmpty)
            Text(
              '${_selectedResults.length} resultado${_selectedResults.length != 1 ? 's' : ''} selecionado${_selectedResults.length != 1 ? 's' : ''}',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Step 3: Detalhes ───────────────────────────────────────────────

  Widget _buildStep3() {
    final needsDetails = _selectedResults.where((r) =>
        r != OccurrenceResult.noOccurrence &&
        r != OccurrenceResult.supportProvided);

    if (needsDetails.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  color: const Color(0xFF2ECC71), size: 48),
              const SizedBox(height: 16),
              Text(
                'Nenhum detalhe adicional necessário',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withAlpha(180),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toque em CONCLUIR para finalizar.',
                style: GoogleFonts.inter(
                  color: Colors.white.withAlpha(100),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DETALHES DOS RESULTADOS',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...needsDetails.map((result) => _buildDetailSection(result)),
        ],
      ),
    );
  }

  Widget _buildDetailSection(OccurrenceResult result) {
    if (result == OccurrenceResult.drugSeized) {
      return _buildDrugSection();
    }

    final fields = _fieldsForResult(result);
    final key = result.toMap();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_iconForResult(result),
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                result.label.toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...fields.map((field) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _getDetailController(key, field.key),
                  keyboardType: field.numeric
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters: field.numeric
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : null,
                  style:
                      GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: _detailFieldDecoration(field.label),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildDrugSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💊', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DROGA APREENDIDA',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _addDrugEntry,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'ADICIONAR',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._drugEntries.asMap().entries.map((entry) {
            final idx = entry.key;
            final drugEntry = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withAlpha(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Substância ${idx + 1}',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_drugEntries.length > 1)
                        GestureDetector(
                          onTap: () => _removeDrugEntry(idx),
                          child: Icon(Icons.close,
                              size: 16,
                              color: AppTheme.error.withAlpha(180)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'TIPO',
                    style: GoogleFonts.inter(
                      color: Colors.white.withAlpha(120),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _drugTypes.map((type) {
                      final selected = drugEntry.type == type;
                      return GestureDetector(
                        onTap: () => setState(() => drugEntry.type = type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.primary.withAlpha(30)
                                : Colors.white.withAlpha(5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? AppTheme.primary
                                  : Colors.white.withAlpha(30),
                            ),
                          ),
                          child: Text(
                            type,
                            style: GoogleFonts.inter(
                              color: selected
                                  ? AppTheme.primary
                                  : Colors.white.withAlpha(180),
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: drugEntry.weightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 14),
                    decoration: _detailFieldDecoration('Peso em gramas'),
                  ),
                ],
              ),
            );
          }),
          if (_drugEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Toque em ADICIONAR para registrar substâncias',
                style: GoogleFonts.inter(
                  color: Colors.white.withAlpha(80),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _detailFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          GoogleFonts.inter(color: Colors.white.withAlpha(120), fontSize: 13),
      filled: true,
      fillColor: Colors.white.withAlpha(8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withAlpha(20)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withAlpha(20)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.primary),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  String _iconForResult(OccurrenceResult result) => switch (result) {
        OccurrenceResult.drugSeized => '💊',
        OccurrenceResult.weaponSeized => '🔫',
        OccurrenceResult.personDetained => '👤',
        OccurrenceResult.boCreated => '📄',
        OccurrenceResult.noOccurrence => '⊘',
        OccurrenceResult.supportProvided => '✋',
      };

  List<_DetailField> _fieldsForResult(OccurrenceResult result) =>
      switch (result) {
        OccurrenceResult.drugSeized => [], // handled by _buildDrugSection
        OccurrenceResult.weaponSeized => [
            const _DetailField(label: 'Tipo de arma', key: 'type'),
            const _DetailField(
                label: 'Quantidade', key: 'quantity', numeric: true),
          ],
        OccurrenceResult.personDetained => [
            const _DetailField(
                label: 'Quantidade', key: 'count', numeric: true),
            const _DetailField(
                label: 'Encaminhamento (DP, etc)', key: 'referral'),
          ],
        OccurrenceResult.boCreated => [
            const _DetailField(label: 'Número do BO', key: 'bo_number'),
            const _DetailField(
                label: 'Tipo (flagrante, TCO, etc)', key: 'bo_type'),
          ],
        _ => [],
      };
}

class _DetailField {
  final String label;
  final String key;
  final bool numeric;

  const _DetailField({
    required this.label,
    required this.key,
    this.numeric = false,
  });
}

class _ResultCard extends StatelessWidget {
  final OccurrenceResult result;
  final bool selected;
  final VoidCallback onTap;

  const _ResultCard({
    required this.result,
    required this.selected,
    required this.onTap,
  });

  String get _icon => switch (result) {
        OccurrenceResult.drugSeized => '💊',
        OccurrenceResult.weaponSeized => '🔫',
        OccurrenceResult.personDetained => '👤',
        OccurrenceResult.boCreated => '📄',
        OccurrenceResult.noOccurrence => '⊘',
        OccurrenceResult.supportProvided => '✋',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withAlpha(25)
              : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.white.withAlpha(20),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: Icon(Icons.check_circle,
                      color: AppTheme.primary, size: 16),
                ),
              ),
            Text(_icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              result.label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color:
                    selected ? Colors.white : Colors.white.withAlpha(180),
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrugEntry {
  String? type;
  final TextEditingController weightController;

  _DrugEntry() : weightController = TextEditingController();

  void dispose() => weightController.dispose();
}
