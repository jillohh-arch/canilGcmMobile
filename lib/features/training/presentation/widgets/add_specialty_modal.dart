import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

class AddSpecialtyModal extends StatefulWidget {
  final Dog dog;

  const AddSpecialtyModal({super.key, required this.dog});

  @override
  State<AddSpecialtyModal> createState() => _AddSpecialtyModalState();
}

class _AddSpecialtyModalState extends State<AddSpecialtyModal> {
  String? _selectedSpecialty;
  final Set<String> _selectedSubstances = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0C1920),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedSpecialty == 'Detecção' ? 'Substâncias Alvo' : 'Nova Especialidade',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedSpecialty == 'Detecção'
                ? 'Selecione quais substâncias o cão começará a farejar'
                : 'Selecione qual especialidade deseja iniciar com ${widget.dog.name}',
            style: GoogleFonts.inter(
              color: const Color(0xFF7A8A92),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),

          if (_selectedSpecialty == null)
            _buildSpecialtySelector()
          else if (_selectedSpecialty == 'Detecção')
            _buildSubstanceSelector()
          else
            _buildConfirmation(),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (_selectedSpecialty != null) {
                      setState(() {
                        _selectedSpecialty = null;
                        _selectedSubstances.clear();
                      });
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7A8A92),
                    side: const BorderSide(color: Color(0x1AFFFFFF)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _selectedSpecialty != null ? 'Voltar' : 'Cancelar',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _selectedSpecialty == null ? null : () => _saveSpecialty(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DD0E1),
                    foregroundColor: const Color(0xFF050D10),
                    disabledBackgroundColor: const Color(0x1F4DD0E1),
                    disabledForegroundColor: const Color(0x33050D10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _selectedSpecialty == 'Detecção' ? 'Confirmar' : 'Iniciar Formação',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialtySelector() {
    return Column(
      children: [
        _buildSpecialtyCard('🎯', 'Busca & Captura', 'Formação em rastro e perseguição de odor humano.'),
        _buildSpecialtyCard('👃', 'Detecção', 'Drogas, armas, explosivos ou cadáveres.'),
        _buildSpecialtyCard('🛡', 'Guarda & Proteção', 'Impulsos de caça, guarda de perímetro e defesa.'),
      ],
    );
  }

  Widget _buildSpecialtyCard(String emoji, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        border: Border.all(color: const Color(0x14FFFFFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Text(emoji, style: const TextStyle(fontSize: 24)),
        title: Text(
          title,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.inter(color: const Color(0xFF7A8A92), fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF5A7280)),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedSpecialty = title;
          });
        },
      ),
    );
  }

  Widget _buildSubstanceSelector() {
    return Column(
      children: [
        _buildSubstanceRow('💊', 'Drogas', 'maconha, cocaína, crack, LSD, ecstasy, etc.'),
        _buildSubstanceRow('🔫', 'Armas e Pólvora', 'munições e derivados de pólvora.'),
        _buildSubstanceRow('🕯', 'Cadáver', 'fontes biológicas e decomposição.'),
      ],
    );
  }

  Widget _buildSubstanceRow(String emoji, String title, String subtitle) {
    final isSelected = _selectedSubstances.contains(title);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0x1A4DD0E1) : const Color(0x0DFFFFFF),
        border: Border.all(color: isSelected ? const Color(0xFF4DD0E1) : const Color(0x14FFFFFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (val) {
          HapticFeedback.lightImpact();
          setState(() {
            if (val == true) {
              _selectedSubstances.add(title);
            } else {
              _selectedSubstances.remove(title);
            }
          });
        },
        activeColor: const Color(0xFF4DD0E1),
        checkColor: const Color(0xFF050D10),
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.inter(color: const Color(0xFF7A8A92), fontSize: 10.5),
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Text('📈', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          Text(
            'Confirmar início de formação',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'O cão será registrado como "Em Formação" na especialidade de $_selectedSpecialty.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: const Color(0xFFB0C4CC), fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSpecialty() async {
    HapticFeedback.mediumImpact();
    
    String? typeKey;
    if (_selectedSpecialty == 'Busca & Captura') {
      typeKey = 'busca_captura';
    } else if (_selectedSpecialty == 'Detecção') {
      typeKey = 'deteccao';
    } else if (_selectedSpecialty == 'Guarda & Proteção') {
      typeKey = 'guarda_protecao';
    }

    if (typeKey == null) return;

    final data = <String, dynamic>{
      'type': typeKey,
      'status': 'in_formation',
      'started_at': FieldValue.serverTimestamp(),
    };

    if (typeKey == 'deteccao') {
      data['sub_areas'] = _selectedSubstances.map((subName) => {
        'name': subName,
        'status': 'in_formation',
      }).toList();
    }

    try {
      await FirebaseFirestore.instance
          .collection('dogs')
          .doc(widget.dog.id)
          .collection('specialties')
          .doc(typeKey)
          .set(data);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedSpecialty == 'Detecção'
                ? 'Especialidade de Detecção iniciada com as substâncias: ${_selectedSubstances.join(", ")}!'
                : 'Especialidade de $_selectedSpecialty iniciada com sucesso!',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao iniciar especialidade: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}
