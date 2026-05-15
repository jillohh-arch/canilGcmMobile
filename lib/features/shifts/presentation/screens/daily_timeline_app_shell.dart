part of 'daily_timeline_screen.dart';

extension _DailyTimelineAppShell on _DailyTimelineScreenState {
  Widget _buildNoActiveShiftScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Text(
          'Nenhum turno ativo.',
          style: GoogleFonts.inter(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildTimelineScaffold(String dogId) {
    return Scaffold(
      backgroundColor: _hudBackground,
      appBar: AppBar(
        title: Text(
          'LINHA DO TEMPO',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.white,
            letterSpacing: 1.4,
          ),
        ),
        backgroundColor: _hudBackground,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            icon: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFFFBBF24),
            ),
            onPressed: () => _exportPdf(context, dogId),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: HudTabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.shield_outlined, size: 22),
                text: 'Ocorrências',
              ),
              Tab(
                icon: Icon(Icons.track_changes_rounded, size: 22),
                text: 'Treinos',
              ),
              Tab(
                icon: Icon(Icons.bar_chart_rounded, size: 22),
                text: 'Evolução',
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOccurrencesTab(dogId),
          _buildTrainingsTab(dogId),
          _buildEvolutionTab(dogId),
        ],
      ),
    );
  }
}
