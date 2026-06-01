import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/core/services/storage_service.dart';

class HealthEventFormScreen extends StatefulWidget {
  final String dogId;
  final String
  type; // 'vaccination' | 'antiparasitic' | 'exam' | 'consultation' | 'medication' | 'symptom' | 'surgery' | 'other'

  const HealthEventFormScreen({
    super.key,
    required this.dogId,
    required this.type,
  });

  @override
  State<HealthEventFormScreen> createState() => _HealthEventFormScreenState();
}

class _HealthEventFormScreenState extends State<HealthEventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storageService = StorageService();

  // Controllers
  final _subtypeController =
      TextEditingController(); // e.g. vaccine name, medicine name
  final _observationsController = TextEditingController();
  final _weightController = TextEditingController();
  final _vetNameController = TextEditingController();
  final _crmvController = TextEditingController();
  final _clinicController = TextEditingController();
  final _costController = TextEditingController();

  // Specific medication fields
  final _dosageController = TextEditingController();
  final _frequencyController = TextEditingController();
  final _durationController = TextEditingController();

  // Specific surgery fields
  final _anesthesiaController = TextEditingController();

  // General fields
  DateTime _applicationDate = DateTime.now();
  DateTime? _nextDueDate;
  double _symptomSeverity = 3.0; // Slider scale 1-5
  File? _attachmentFile;
  String? _attachmentName;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Default vaccination to auto-calculate next due date (+1 year)
    if (widget.type == 'vaccination') {
      _nextDueDate = _applicationDate.add(const Duration(days: 365));
    }
  }

  @override
  void dispose() {
    _subtypeController.dispose();
    _observationsController.dispose();
    _weightController.dispose();
    _vetNameController.dispose();
    _crmvController.dispose();
    _clinicController.dispose();
    _costController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _durationController.dispose();
    _anesthesiaController.dispose();
    super.dispose();
  }

  Color get _categoryColor {
    switch (widget.type) {
      case 'vaccination':
        return AppTheme.success;
      case 'antiparasitic':
        return AppTheme.healthAccent;
      case 'exam':
        return AppTheme.info;
      case 'consultation':
        return AppTheme.successOperational;
      case 'medication':
        return AppTheme.warning;
      case 'symptom':
        return AppTheme.error;
      case 'surgery':
        return AppTheme.attention;
      case 'other':
      default:
        return AppTheme.textSoft;
    }
  }

  String get _categoryTitle {
    switch (widget.type) {
      case 'vaccination':
        return 'Nova Vacina';
      case 'antiparasitic':
        return 'Novo Antiparasitário';
      case 'exam':
        return 'Novo Exame';
      case 'consultation':
        return 'Nova Consulta';
      case 'medication':
        return 'Nova Medicação';
      case 'symptom':
        return 'Registrar Sintoma';
      case 'surgery':
        return 'Nova Cirurgia';
      case 'other':
      default:
        return 'Outro Evento';
    }
  }

  void _updateAutoVaccineNextDueDate() {
    if (widget.type == 'vaccination') {
      setState(() {
        _nextDueDate = _applicationDate.add(const Duration(days: 365));
      });
    }
  }

  Future<void> _pickAttachment() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: AppTheme.primary,
              ),
              title: Text('Tirar Foto', style: GoogleFonts.inter()),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 80,
                );
                if (picked != null) {
                  setState(() {
                    _attachmentFile = File(picked.path);
                    _attachmentName = picked.name;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppTheme.primary,
              ),
              title: Text('Escolher da Galeria', style: GoogleFonts.inter()),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80,
                );
                if (picked != null) {
                  setState(() {
                    _attachmentFile = File(picked.path);
                    _attachmentName = picked.name;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.picture_as_pdf_rounded,
                color: AppTheme.primary,
              ),
              title: Text(
                'Selecionar Documento/PDF',
                style: GoogleFonts.inter(),
              ),
              onTap: () async {
                Navigator.pop(context);
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: [
                    'pdf',
                    'doc',
                    'docx',
                    'jpg',
                    'jpeg',
                    'png',
                  ],
                );
                if (result != null && result.files.single.path != null) {
                  setState(() {
                    _attachmentFile = File(result.files.single.path!);
                    _attachmentName = result.files.single.name;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final dogVM = Provider.of<DogViewModel>(context, listen: false);
      final dog = dogVM.dogs.firstWhere((d) => d.id == widget.dogId);
      final dogName = dog.name;

      final healthVM = Provider.of<HealthViewModel>(context, listen: false);

      String? attachmentUrl;
      if (_attachmentFile != null) {
        attachmentUrl = await _storageService.uploadFile(
          _attachmentFile!,
          'health_attachments/${widget.dogId}',
        );
      }

      // Dynamic sub-typing / values mapping
      String finalObservations = _observationsController.text.trim();
      if (widget.type == 'symptom') {
        finalObservations =
            '[Gravidade Subjetiva: ${_symptomSeverity.toInt()}/5]\n$finalObservations';
      } else if (widget.type == 'medication') {
        finalObservations =
            '[Dosagem: ${_dosageController.text.trim()} | Frequência: ${_frequencyController.text.trim()} | Duração: ${_durationController.text.trim()}]\n$finalObservations';
      } else if (widget.type == 'surgery') {
        finalObservations =
            '[Cuidados Pós-Operatórios / Anestesia: ${_anesthesiaController.text.trim()}]\n$finalObservations';
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;

      final log = HealthLogModel(
        dogId: widget.dogId,
        dogName: dogName,
        date: _applicationDate,
        type: widget.type,
        subtype: _subtypeController.text.trim().isNotEmpty
            ? _subtypeController.text.trim()
            : null,
        weight: _weightController.text.trim().isNotEmpty
            ? double.tryParse(
                _weightController.text.trim().replaceAll(',', '.'),
              )
            : null,
        healthObservations: finalObservations,
        nextDueDate: _nextDueDate,
        professionalCrmv: _crmvController.text.trim().isNotEmpty
            ? _crmvController.text.trim()
            : null,
        professionalClinic: _clinicController.text.trim().isNotEmpty
            ? _clinicController.text.trim()
            : null,
        vetName: _vetNameController.text.trim().isNotEmpty
            ? _vetNameController.text.trim()
            : null,
        attachmentUrl: attachmentUrl,
        costBrl: _costController.text.trim().isNotEmpty
            ? double.tryParse(_costController.text.trim().replaceAll(',', '.'))
            : null,
        createdBy: uid,
      );

      await healthVM.addHealthLog(log);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registro de ${log.logType} salvo com sucesso!'),
          backgroundColor: AppTheme.success,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar registro: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          _categoryTitle,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(color: _categoryColor, height: 3),
        ),
      ),
      body: _isSaving
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Gravando e sincronizando prontuário...',
                    style: TextStyle(
                      color: AppTheme.textPrimary.withAlpha(179),
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('DADOS GERAIS'),
                    _buildDateField(),
                    const SizedBox(height: 16),
                    _buildSubtypeField(),
                    const SizedBox(height: 16),
                    _buildWeightField(),
                    const SizedBox(height: 16),
                    _buildCostField(),
                    const SizedBox(height: 24),

                    // Adaptive Fields
                    ..._buildAdaptiveFields(cs),

                    _buildSectionHeader('PROFISSIONAL RESPONSÁVEL'),
                    _buildProfessionalFields(),
                    const SizedBox(height: 24),

                    _buildSectionHeader('ANEXOS E DOCUMENTOS'),
                    _buildAttachmentField(cs),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _categoryColor,
                          foregroundColor: AppTheme.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _saveForm,
                        child: Text(
                          'Salvar Registro',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppTheme.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Data do Registro',
        prefixIcon: Icon(Icons.calendar_today_rounded),
      ),
      controller: TextEditingController(
        text: DateFormat('dd/MM/yyyy').format(_applicationDate),
      ),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _applicationDate,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
        );
        if (date != null) {
          setState(() {
            _applicationDate = date;
            _updateAutoVaccineNextDueDate();
          });
        }
      },
    );
  }

  Widget _buildSubtypeField() {
    String label = 'Subtipo';
    IconData icon = Icons.info_outline_rounded;
    List<String> suggestions = [];

    if (widget.type == 'vaccination') {
      label = 'Vacina';
      icon = Icons.vaccines_rounded;
      suggestions = [
        'V10',
        'Antirrábica',
        'Gripe',
        'Giardíase',
        'Leishmaniose',
      ];
    } else if (widget.type == 'antiparasitic') {
      label = 'Medicamento / Marca';
      icon = Icons.bug_report_rounded;
      suggestions = ['Bravecto', 'NexGard', 'Simparic', 'Frontline'];
    } else if (widget.type == 'exam') {
      label = 'Tipo de Exame';
      icon = Icons.biotech_rounded;
      suggestions = [
        'Hemograma',
        'Ultrassonografia',
        'Raio-X',
        'Exame de Urina',
      ];
    } else if (widget.type == 'consultation') {
      label = 'Motivo da Consulta';
      icon = Icons.medical_services_rounded;
      suggestions = [
        'Rotina',
        'Averiguação de Sintomas',
        'Retorno',
        'Urgência',
      ];
    } else if (widget.type == 'medication') {
      label = 'Nome do Medicamento';
      icon = Icons.medication_rounded;
    } else if (widget.type == 'surgery') {
      label = 'Tipo de Cirurgia';
      icon = Icons.healing_rounded;
    } else if (widget.type == 'other') {
      label = 'Título / Descrição do Evento';
      icon = Icons.star_rounded;
    }

    if (widget.type == 'symptom') {
      return const SizedBox.shrink(); // Not needed for symptoms (observations contains detail)
    }

    if (suggestions.isNotEmpty) {
      return DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        initialValue: suggestions.contains(_subtypeController.text)
            ? _subtypeController.text
            : null,
        items:
            suggestions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList()
              ..add(
                const DropdownMenuItem(
                  value: 'outros',
                  child: Text('Outro...'),
                ),
              ),
        onChanged: (val) {
          if (val == 'outros') {
            _subtypeController.clear();
            // Trigger textfield input overlay or just show textfield below.
            // For simplicity, if 'outros' is chosen, we let them type it below
            showDialog(
              context: context,
              builder: (context) {
                final controller = TextEditingController();
                return AlertDialog(
                  title: Text('Especificar $label', style: GoogleFonts.inter()),
                  content: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Digite o nome do $label',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _subtypeController.text = controller.text;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Confirmar'),
                    ),
                  ],
                );
              },
            );
          } else if (val != null) {
            setState(() {
              _subtypeController.text = val;
            });
          }
        },
        validator: (value) =>
            _subtypeController.text.isEmpty ? 'Campo obrigatório' : null,
      );
    }

    return TextFormField(
      controller: _subtypeController,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'Campo obrigatório' : null,
    );
  }

  Widget _buildWeightField() {
    return TextFormField(
      controller: _weightController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Peso do Cão (Opcional)',
        prefixIcon: Icon(Icons.monitor_weight_rounded),
        suffixText: 'kg',
      ),
    );
  }

  Widget _buildCostField() {
    return TextFormField(
      controller: _costController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Custo do Procedimento (Opcional)',
        prefixIcon: Icon(Icons.attach_money),
        suffixText: r'R$',
      ),
    );
  }

  List<Widget> _buildAdaptiveFields(ColorScheme cs) {
    switch (widget.type) {
      case 'vaccination':
        return [
          _buildSectionHeader('DADOS DA VACINAÇÃO'),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Próxima Dose Auto-calculada',
              prefixIcon: Icon(Icons.event_repeat_rounded),
            ),
            readOnly: true,
            controller: TextEditingController(
              text: _nextDueDate != null
                  ? DateFormat('dd/MM/yyyy').format(_nextDueDate!)
                  : 'Não definida',
            ),
          ),
          const SizedBox(height: 16),
          _buildObservationsField(
            'Observações da vacina (lote, fabricante, etc.)',
          ),
          const SizedBox(height: 24),
        ];

      case 'antiparasitic':
        return [
          _buildSectionHeader('CONTROLE DE PRÓXIMA DOSE'),
          TextFormField(
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Data da Próxima Dose (Opcional)',
              prefixIcon: Icon(Icons.event_repeat_rounded),
            ),
            controller: TextEditingController(
              text: _nextDueDate != null
                  ? DateFormat('dd/MM/yyyy').format(_nextDueDate!)
                  : 'Selecione uma data ou atalho',
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate:
                    _nextDueDate ??
                    DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setState(() => _nextDueDate = date);
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _nextDueDate = _applicationDate.add(
                        const Duration(days: 30),
                      );
                    });
                  },
                  child: const Text('+1 Mês (Simparic/Nexgard)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _nextDueDate = _applicationDate.add(
                        const Duration(days: 90),
                      );
                    });
                  },
                  child: const Text('+3 Meses (Bravecto)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildObservationsField('Dosagem, lote ou observações...'),
          const SizedBox(height: 24),
        ];

      case 'medication':
        return [
          _buildSectionHeader('POSOLOGIA'),
          TextFormField(
            controller: _dosageController,
            decoration: const InputDecoration(
              labelText: 'Dosagem (Ex: 1 comp., 2ml)',
              prefixIcon: Icon(Icons.scale_rounded),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Defina a dosagem'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _frequencyController,
            decoration: const InputDecoration(
              labelText: 'Frequência (Ex: 12 em 12h, 1x ao dia)',
              prefixIcon: Icon(Icons.timer_rounded),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Defina a frequência'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _durationController,
            decoration: const InputDecoration(
              labelText: 'Duração (Ex: 7 dias, contínuo)',
              prefixIcon: Icon(Icons.calendar_today_rounded),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Defina a duração'
                : null,
          ),
          const SizedBox(height: 16),
          _buildObservationsField('Outras orientações...'),
          const SizedBox(height: 24),
        ];

      case 'symptom':
        return [
          _buildSectionHeader('GRAVIDADE E DETALHES'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.error.withAlpha(50)),
            ),
            child: Row(
              children: [
                const Icon(Icons.gavel_rounded, color: AppTheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aviso Ético: Registro de sintomas pelo condutor. Não substitui o diagnóstico veterinário profissional.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Gravidade Percebida: ${_symptomSeverity.toInt()}/5',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Slider(
            value: _symptomSeverity,
            min: 1.0,
            max: 5.0,
            divisions: 4,
            activeColor: AppTheme.error,
            onChanged: (val) {
              setState(() {
                _symptomSeverity = val;
              });
            },
          ),
          const SizedBox(height: 16),
          _buildObservationsField(
            'Descreva detalhadamente o sintoma observado, frequência e comportamento do cão...',
          ),
          const SizedBox(height: 24),
        ];

      case 'surgery':
        return [
          _buildSectionHeader('DADOS CIRÚRGICOS'),
          TextFormField(
            controller: _anesthesiaController,
            decoration: const InputDecoration(
              labelText: 'Cuidados Pós-Operatórios / Anestesia',
              prefixIcon: Icon(Icons.bed_rounded),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          TextFormField(
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Data do Retorno (Opcional)',
              prefixIcon: Icon(Icons.event_repeat_rounded),
            ),
            controller: TextEditingController(
              text: _nextDueDate != null
                  ? DateFormat('dd/MM/yyyy').format(_nextDueDate!)
                  : 'Selecione se aplicável',
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate:
                    _nextDueDate ?? DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setState(() => _nextDueDate = date);
              }
            },
          ),
          const SizedBox(height: 16),
          _buildObservationsField('Descrição da cirurgia e pós-operatório...'),
          const SizedBox(height: 24),
        ];

      default:
        return [
          _buildSectionHeader('MAIS DETALHES'),
          _buildObservationsField('Detalhamento do registro...'),
          const SizedBox(height: 24),
        ];
    }
  }

  Widget _buildObservationsField(String hint) {
    return TextFormField(
      controller: _observationsController,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: 'Observações Clínicas',
        hintText: hint,
        alignLabelWithHint: true,
      ),
      validator: (value) => (value == null || value.trim().isEmpty)
          ? 'Informe as observações'
          : null,
    );
  }

  Widget _buildProfessionalFields() {
    final isMandatory =
        widget.type == 'vaccination' ||
        widget.type == 'surgery' ||
        widget.type == 'consultation' ||
        widget.type == 'exam';

    return Column(
      children: [
        TextFormField(
          controller: _vetNameController,
          decoration: const InputDecoration(
            labelText: 'Nome do Veterinário',
            prefixIcon: Icon(Icons.person_rounded),
          ),
          validator: (val) => isMandatory && (val == null || val.trim().isEmpty)
              ? 'Nome do profissional é obrigatório'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _crmvController,
          decoration: const InputDecoration(
            labelText: 'CRMV (Obrigatório para Vacina/Cirurgia)',
            prefixIcon: Icon(Icons.badge_rounded),
          ),
          validator: (val) {
            final requiredForThisType =
                widget.type == 'vaccination' || widget.type == 'surgery';
            if (requiredForThisType && (val == null || val.trim().isEmpty)) {
              return 'CRMV é obrigatório';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _clinicController,
          decoration: const InputDecoration(
            labelText: 'Clínica / Hospital Veterinário',
            prefixIcon: Icon(Icons.apartment_rounded),
          ),
          validator: (val) => isMandatory && (val == null || val.trim().isEmpty)
              ? 'Local de atendimento é obrigatório'
              : null,
        ),
      ],
    );
  }

  Widget _buildAttachmentField(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(26)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _attachmentName != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _attachmentName!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Arquivo pronto para envio',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Nenhum anexo selecionado',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textTertiary,
                    ),
                  ),
          ),
          if (_attachmentName != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppTheme.error),
              onPressed: () {
                setState(() {
                  _attachmentFile = null;
                  _attachmentName = null;
                });
              },
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.textPrimary.withAlpha(31),
              foregroundColor: AppTheme.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.attach_file_rounded, size: 16),
            label: Text(
              _attachmentName != null ? 'Alterar' : 'Anexar',
              style: const TextStyle(fontSize: 13),
            ),
            onPressed: _pickAttachment,
          ),
        ],
      ),
    );
  }
}
