import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/dogs/data/dog_profile_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

part 'dog_profile_hero_card.dart';
part 'dog_profile_general_data.dart';
part 'dog_profile_health_section.dart';
part 'dog_profile_aptitude_section.dart';
part 'dog_profile_recent_records.dart';
part 'dog_profile_observations.dart';

const _bgColor = Color(0xFF070B14);
const _panelColor = Color(0xFF0B1220);
const _cyan = Color(0xFF00E5FF);
const _green = Color(0xFF00E58A);
const _amber = Color(0xFFFBBF24);
const _danger = Color(0xFFFF3B6B);
const _purple = Color(0xFFAB47BC);

class DogProfileScreen extends StatefulWidget {
  final Dog dog;
  const DogProfileScreen({super.key, required this.dog});

  @override
  State<DogProfileScreen> createState() => _DogProfileScreenState();
}

class _DogProfileScreenState extends State<DogProfileScreen> {
  final DogProfileService _service = DogProfileService();

  List<VaccineRecord> _vaccines = [];
  List<DogAptitude> _aptitudes = [];
  List<RecentRecord> _recentRecords = [];
  String? _handlerName;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final results = await Future.wait([
        _service.getVaccines(widget.dog.id),
        _service.getAptitudes(widget.dog.id),
        _service.getRecentRecords(widget.dog.id),
        _resolveHandlerName(),
      ]);

      if (!mounted) return;
      setState(() {
        _vaccines = results[0] as List<VaccineRecord>;
        _aptitudes = results[1] as List<DogAptitude>;
        _recentRecords = results[2] as List<RecentRecord>;
        _handlerName = results[3] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar o perfil do cão.';
        _loading = false;
      });
    }
  }

  Future<String?> _resolveHandlerName() async {
    // Tenta resolver pelo conductorRa via UserViewModel
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    if (widget.dog.conductorRa != null) {
      final name = userVM.displayNameFor(ra: widget.dog.conductorRa);
      if (name != 'Condutor') return name;
      // Fallback: busca no Firestore
      return _service.getHandlerName(widget.dog.conductorRa!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // App bar
        SliverAppBar(
          backgroundColor: _bgColor,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: _cyan, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          centerTitle: true,
          title: Text(
            'Perfil do Cão',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: _cyan, size: 20),
              onPressed: () {
                // TODO: abrir tela de edição
              },
            ),
          ],
        ),
        // Hero card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _loading
                ? _buildShimmer()
                : _HeroCard(
                    dog: widget.dog,
                    handlerName: _handlerName,
                  ),
          ),
        ),
        // Dados gerais
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _GeneralDataSection(dog: widget.dog),
          ),
        ),
        // Saúde
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _HealthSection(
              dog: widget.dog,
              vaccines: _vaccines,
              loading: _loading,
            ),
          ),
        ),
        // Aptidão operacional
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _AptitudeSection(
              aptitudes: _aptitudes,
              specialties: widget.dog.specialties,
              loading: _loading,
            ),
          ),
        ),
        // Últimos registros
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _RecentRecordsSection(
              records: _recentRecords,
              loading: _loading,
            ),
          ),
        ),
        // Observações
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            child: _ObservationsSection(
              observacoes: widget.dog.observacoes,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmer() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: _panelColor.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cyan.withAlpha(30)),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
        ),
      ),
    );
  }
}
