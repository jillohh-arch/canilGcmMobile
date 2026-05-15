part of 'dog_prontuario_tab_screen.dart';

extension _DogProntuarioFicha on _DogProntuarioTabScreenState {
  Widget _buildFicha(Dog dog) {
    final age = dog.age;
    final sexLabel = dog.sex == 'M' ? 'MACHO' : 'FÊMEA';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _cyanAccent.withAlpha(13),
            _greenAccent.withAlpha(5),
          ],
        ),
        border: Border.all(color: _cyanAccent.withAlpha(51)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Foto do cão
          _buildDogPhoto(dog),
          const SizedBox(width: 14),
          // Dados
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dog.name,
                  style: GoogleFonts.inter(
                    color: _textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${dog.breed.toUpperCase()} · $sexLabel',
                  style: GoogleFonts.inter(
                    color: _cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                // Meta row
                Row(
                  children: [
                    _buildMetaItem('Idade:', '$age anos'),
                    const SizedBox(width: 6),
                    Text('·', style: GoogleFonts.inter(color: _textMuted, fontSize: 12)),
                    const SizedBox(width: 6),
                    _buildMetaItem('Peso:', dog.weight != null ? '${dog.weight}kg' : '—'),
                  ],
                ),
                const SizedBox(height: 8),
                // Badge operacional
                if (dog.status == 'Ativo')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _greenAccent.withAlpha(31),
                      border: Border.all(color: _greenAccent.withAlpha(77)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _greenAccent,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'OPERACIONAL',
                          style: GoogleFonts.inter(
                            color: _greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_handlerName != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Condutor: $_handlerName',
                    style: GoogleFonts.inter(
                      color: _textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDogPhoto(Dog dog) {
    return Stack(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _cyanAccent, width: 3),
            color: const Color(0xFF1A2A30),
          ),
          child: dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: dog.profileImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Center(
                      child: Text(
                        dog.name.substring(0, 2).toUpperCase(),
                        style: GoogleFonts.inter(
                          color: _cyanAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Center(
                      child: Text(
                        dog.name.substring(0, 2).toUpperCase(),
                        style: GoogleFonts.inter(
                          color: _cyanAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    dog.name.substring(0, 2).toUpperCase(),
                    style: GoogleFonts.inter(
                      color: _cyanAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
        ),
        if (dog.status == 'Ativo')
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _greenAccent,
                border: Border.all(color: _bgColor, width: 2),
              ),
              child: const Icon(Icons.check, color: Color(0xFF050D10), size: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(color: _textMuted, fontSize: 11)),
        const SizedBox(width: 3),
        Text(
          value,
          style: GoogleFonts.inter(
            color: _textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
