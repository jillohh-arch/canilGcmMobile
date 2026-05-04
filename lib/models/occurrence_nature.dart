class OccurrenceNature {
  final String code;
  final String name;
  final String group;
  final bool active;

  const OccurrenceNature({
    required this.code,
    required this.name,
    required this.group,
    this.active = true,
  });

  factory OccurrenceNature.fromJson(Map<String, dynamic> json) {
    return OccurrenceNature(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'group': group,
      'active': active,
      'searchText': searchableText,
    };
  }

  String get label => code.isEmpty ? name : '$code - $name';

  String get searchableText => normalizeForSearch('$code $name $group');

  bool matches(String query) {
    final normalized = normalizeForSearch(query);
    if (normalized.isEmpty) return true;
    return normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .every(searchableText.contains);
  }

  static String normalizeForSearch(String value) {
    var normalized = value.toLowerCase().trim();
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };

    replacements.forEach((from, to) {
      normalized = normalized.replaceAll(from, to);
    });

    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

abstract final class OccurrenceNatureSeed {
  static const List<OccurrenceNature> items = [
    OccurrenceNature(
      code: 'A01',
      name: 'Homicídio culposo',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A02',
      name: 'Homicídio doloso',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A03',
      name: 'Homicídio tentativa',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A04',
      name: 'Aborto',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A05',
      name: 'Agressão',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A06',
      name: 'Infanticídio',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A07',
      name: 'Periclitação de vida',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A08',
      name: 'Abandono',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A09',
      name: 'Omissão de socorro',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A10',
      name: 'Ameaça',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A11',
      name: 'Sequestro / cárcere privado',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A12',
      name: 'Violação de domicílio',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A13',
      name: 'Maus-tratos',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A14',
      name: 'Rixa',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A15',
      name: 'Calúnia',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A16',
      name: 'Difamação',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A17',
      name: 'Injúria',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A18',
      name: 'Constrangimento ilegal',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A19',
      name: 'Racismo',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A20',
      name: 'Pedido de socorro',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A21',
      name: 'Encontro de cadáver',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A22',
      name: 'Suicídio',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A23',
      name: 'Tentativa de suicídio',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A24',
      name: 'Afogamento em curso',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A25',
      name: 'Tortura',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A26',
      name: 'Abandono natural',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A27',
      name: 'Abandono intelectual',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A28',
      name: 'Entrega de filho menor a pessoa inidônea',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A29',
      name: 'Subtração de incapaz',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A30',
      name: 'Lesão corporal / agressão culposa',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A31',
      name: 'Morte de pessoa ou tentativa',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A32',
      name: 'Pessoa ferida',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A33',
      name: 'Pessoa ofendida ou ameaçada',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A34',
      name: 'Privação de liberdade',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A35',
      name: 'Violência sexual',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A36',
      name: 'Abandono de incapaz',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A37',
      name: 'Violência',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(
      code: 'A90',
      name: 'Outras',
      group: 'Contra a pessoa e a vida',
    ),
    OccurrenceNature(code: 'B01', name: 'Furto', group: 'Contra o patrimônio'),
    OccurrenceNature(
      code: 'B02',
      name: 'Furto tentativa',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B03',
      name: 'Roubo tentativa',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(code: 'B04', name: 'Roubo', group: 'Contra o patrimônio'),
    OccurrenceNature(
      code: 'B05',
      name: 'Extorsão',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B06',
      name: 'Posse / invasão de propriedade',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B07',
      name: 'Dano material',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B08',
      name: 'Apropriação indébita',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B09',
      name: 'Estelionato / fraude',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B10',
      name: 'Receptação',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B11',
      name: 'Latrocínio',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B12',
      name: 'Alarme disparado',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(code: 'B13', name: 'Golpe', group: 'Contra o patrimônio'),
    OccurrenceNature(
      code: 'B14',
      name: 'Subtração coisa própria',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B15',
      name: 'Subtração de coisa alheia',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B16',
      name: 'Veículo localizado',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(
      code: 'B17',
      name: 'Invasão de domicílio',
      group: 'Contra o patrimônio',
    ),
    OccurrenceNature(code: 'B90', name: 'Outras', group: 'Contra o patrimônio'),
    OccurrenceNature(
      code: 'C01',
      name: 'Perturbação de sossego público',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C02',
      name: 'Conduta inconveniente',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C03',
      name: 'Sinalizações',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C04',
      name: 'Usina elétrica',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C05',
      name: 'Averiguação de atitude suspeita',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C06',
      name: 'Perturbação de cerimônia funerária',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C07',
      name: 'Violação de sepultura',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C08',
      name: 'Destruição / subtração / ocultação de cadáver',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C09',
      name: 'Vilipêndio a cadáver',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(
      code: 'C90',
      name: 'Outras',
      group: 'Contra a tranquilidade e mortos',
    ),
    OccurrenceNature(code: 'D01', name: 'Estupro', group: 'Contra os costumes'),
    OccurrenceNature(
      code: 'D02',
      name: 'Estupro tentativa',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D03',
      name: 'Ato obsceno',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D04',
      name: 'Escrita ou objeto obsceno',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D05',
      name: 'Atentado violento ao pudor',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D06',
      name: 'Corrupção de menores',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(code: 'D07', name: 'Rapto', group: 'Contra os costumes'),
    OccurrenceNature(
      code: 'D08',
      name: 'Exploração de lenocínio',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D09',
      name: 'Jogos de azar',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D10',
      name: 'Vadiagem',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D11',
      name: 'Mendicância',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D12',
      name: 'Servir bebida alcoólica a incapaz',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D13',
      name: 'Importunação ofensiva ao pudor',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(
      code: 'D14',
      name: 'Prostituição',
      group: 'Contra os costumes',
    ),
    OccurrenceNature(code: 'D90', name: 'Outras', group: 'Contra os costumes'),
    OccurrenceNature(
      code: 'E01',
      name: 'Peculato',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E02',
      name: 'Concussão',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E03',
      name: 'Corrupção',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E04',
      name: 'Prevaricação',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E05',
      name: 'Violência arbitrária',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E06',
      name: 'Usurpação de função pública',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E07',
      name: 'Apoio',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E08',
      name: 'Desobediência',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E09',
      name: 'Desacato',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E10',
      name: 'Contrabando / descaminho',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E11',
      name: 'Abuso de autoridade',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E13',
      name: 'Resistência',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E14',
      name: 'Crime contra funcionários públicos',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E15',
      name: 'Queixa contra funcionários públicos',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'E90',
      name: 'Outras',
      group: 'Contra a administração pública',
    ),
    OccurrenceNature(
      code: 'F01',
      name: 'Ocorrência com entorpecente',
      group: 'Prev. / repressão de substância entorpecente',
    ),
    OccurrenceNature(
      code: 'G01',
      name: 'Ocorrências com preso',
      group: 'Contra a administração da justiça',
    ),
    OccurrenceNature(
      code: 'G02',
      name: 'Comunicação falsa de crime / trote',
      group: 'Contra a administração da justiça',
    ),
    OccurrenceNature(
      code: 'G90',
      name: 'Outras',
      group: 'Contra a administração da justiça',
    ),
    OccurrenceNature(
      code: 'H01',
      name: 'Greve',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'H02',
      name: 'Piquete',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'H03',
      name: 'Tumulto',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'H04',
      name: 'Passeata',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'H05',
      name: 'Saque / arrastão',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'H06',
      name: 'Manifestação pública',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'H07',
      name: 'Reunião de pessoas',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'H90',
      name: 'Outras',
      group: 'Contra a administração do trabalho / política',
    ),
    OccurrenceNature(
      code: 'I01',
      name: 'Resgate de animal silvestre',
      group: 'Contra o meio ambiente',
    ),
    OccurrenceNature(
      code: 'I02',
      name: 'Devolução de animal silvestre ao habitat natural',
      group: 'Contra o meio ambiente',
    ),
    OccurrenceNature(
      code: 'I03',
      name: 'Crime ambiental',
      group: 'Contra o meio ambiente',
    ),
    OccurrenceNature(
      code: 'I90',
      name: 'Outras ambientais',
      group: 'Contra o meio ambiente',
    ),
    OccurrenceNature(
      code: 'J01',
      name: 'Exercício ilegal de profissão / atividade',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J02',
      name: 'Envenenamento de água potável',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J03',
      name: 'Detenção de suspeito',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J04',
      name: 'Subversão / terrorismo',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J05',
      name: 'Crime contra a economia popular',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J06',
      name: 'Falsa identidade',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J07',
      name: 'Uso de documento falso',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J08',
      name: 'Falsidade ideológica',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J09',
      name: 'Abuso de fogo',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J10',
      name: 'Ocorrência de falsificação',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J11',
      name: 'Formação de bando / quadrilha',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J12',
      name: 'Soltura de balões / fogos',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J13',
      name: 'Ameaça de bomba',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J14',
      name: 'Disparo de arma de fogo',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J15',
      name: 'Ocorrência com material bélico',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'J16',
      name: 'Ocorrências com arma de fogo',
      group: 'Contra a incolumidade, paz e fé pública',
    ),
    OccurrenceNature(
      code: 'L01',
      name: 'Localização de veículo',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L02',
      name: 'Acidente de trânsito',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L03',
      name: 'Direção de veículo',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L04',
      name: 'Congestionamento',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L05',
      name: 'Infração de trânsito',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L06',
      name: 'Infração de via pública',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L07',
      name: 'Atropelamento',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L08',
      name: 'Acidente de trânsito com vítima',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L09',
      name: 'Acidente de trânsito sem vítima',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L10',
      name: 'Ocorrência com veículo',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L11',
      name: 'Ocorrência de trânsito',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L12',
      name: 'Acidente de trânsito com moto',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L13',
      name: 'Acidente de trânsito com ônibus escolar',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'L90',
      name: 'Outras',
      group: 'Ocorrências de trânsito',
    ),
    OccurrenceNature(
      code: 'M01',
      name: 'Ocorrência com pessoa',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M02',
      name: 'Choque elétrico',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M03',
      name: 'Mergulho / salto na água causa trauma',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M04',
      name: 'Inseto agressivo',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M05',
      name: 'Overdose',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M06',
      name: 'Ingestão / injeção / inalação de substância',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M07',
      name: 'Intoxicação por exposição a gases',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M08',
      name: 'Lesão por explosão a PP (exceto explosão em foco)',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M09',
      name: 'Queimadura',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M10',
      name: 'Desmoronamento',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M11',
      name: 'Auxílio à gestante',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M12',
      name: 'Desaparecimento de pessoa',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M14',
      name: 'Mal súbito',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M15',
      name: 'Queda de pessoa',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M17',
      name: 'Outra ocorrência com pessoa',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M18',
      name: 'Outra ocorrência contra o patrimônio',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M20',
      name: 'Acidente pessoal',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'M90',
      name: 'Outras',
      group: 'Ocorrências de auxílio ao público',
    ),
    OccurrenceNature(
      code: 'N01',
      name: 'Incêndio',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N02',
      name: 'Explosão',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N03',
      name: 'Vistoria em edificação',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N04',
      name: 'Vazamento',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N06',
      name: 'Auxílio assistencial',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N07',
      name: 'Vistoria em área de risco',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N08',
      name: 'Acidente',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N10',
      name: 'Desabamento / desmoronamento',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N13',
      name: 'Ocorrência com objeto',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N14',
      name: 'Inundação / enchente / alagamento',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N15',
      name: 'Queda',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N16',
      name: 'Embarcação em situação de risco',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N17',
      name: 'Odor de produto químico / derramamento',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N21',
      name: 'Queda de árvore',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N22',
      name: 'Risco iminente de explosão',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N23',
      name: 'Situação de risco',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N24',
      name: 'Vazamento de GLP / outros gases',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N25',
      name: 'Animal em situação de risco',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'N90',
      name: 'Outras',
      group: 'Ocorrências de bombeiros',
    ),
    OccurrenceNature(
      code: 'O01',
      name: 'Ocorrência em cemitério / velório',
      group: 'Contra a paz dos mortos',
    ),
    OccurrenceNature(
      code: 'T01',
      name: 'Ocorrência de teste / simulado',
      group: 'Ocorrência de teste / simulado',
    ),
    OccurrenceNature(
      code: 'Z01',
      name: 'Em via pública, calçada ou praça',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z02',
      name: 'Em imóvel privado',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z03',
      name: 'Em imóvel público',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z04',
      name: 'Em equipamento / concessão de serviço público',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z05',
      name: 'No meio ambiente',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z06',
      name: 'Em escola pública ou privada',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z07',
      name: 'Relacionado à prostituição',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z08',
      name: 'Relacionado à população de rua',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z09',
      name: 'Relacionado a eventos não autorizados',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'Z10',
      name: 'Relacionado a atividades irregulares',
      group: 'Ocorrências relacionadas a políticas da área',
    ),
    OccurrenceNature(
      code: 'V01',
      name: 'Viagem para outro município',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V02',
      name: 'Serviço administrativo',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V03',
      name: 'Apoio a outros órgãos (exceto trânsito)',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V04',
      name: 'Saturação',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V05',
      name: 'Auxílio / condução',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V06',
      name: 'Ordem de serviço',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V07',
      name: 'Manutenção',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V08',
      name: 'Apoio em ocorrências',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V09',
      name: 'Condutor de preso / equipamento',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V10',
      name: 'Apoio / condutor de C.C.M.',
      group: 'Ocorrência de apoio / operações',
    ),
    OccurrenceNature(
      code: 'V90',
      name: 'Outras operações',
      group: 'Ocorrência de apoio / operações',
    ),
  ];
}
