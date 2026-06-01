import 'package:flutter/material.dart';
import 'seal_data.dart';

/// Lista completa dos 12 selos de conformidade profissional.
/// Dados hardcoded por ora. TODO: calcular dinamicamente via Firestore.
List<SealData> buildSealDefinitions({int specialtyCount = 0}) {
  return [
    // ── OPERACIONAL ──────────────────────────────────────────────────────
    const SealData(
      id: 'plantoes_sem_lacunas',
      name: 'Plantoes sem lacunas',
      isActive: true,
      subtitle: 'ha 142 dias',
      icon: Icons.calendar_month_rounded,
      criterion:
          'Todos os plantoes dos ultimos 90 dias registrados com inicio e fim.',
      activity: '12 plantoes consecutivos registrados sem lacuna.',
      howToMaintain: 'Continue registrando inicio e fim de cada plantao.',
    ),
    const SealData(
      id: 'relato_final_100',
      name: 'Relato final 100%',
      isActive: true,
      subtitle: 'ultimas 30 ocorrencias',
      icon: Icons.edit_note_rounded,
      criterion:
          'Ultimas 30 ocorrencias com final_report preenchido completamente.',
      activity: '30/30 ocorrencias com relato completo.',
      howToMaintain: 'Sempre completar o wizard de finalizacao.',
    ),
    const SealData(
      id: 'pdfs_gerados_100',
      name: 'PDFs gerados 100%',
      isActive: true,
      subtitle: 'ultimas 30 ocorrencias',
      icon: Icons.picture_as_pdf_rounded,
      criterion: 'Ultimas 30 ocorrencias com PDF institucional gerado.',
      activity: '30/30 ocorrencias com PDF disponivel.',
      howToMaintain: 'Gerar PDF ao finalizar cada ocorrencia.',
    ),
    // ── TREINO ───────────────────────────────────────────────────────────
    SealData(
      id: 'manutencoes_em_dia',
      name: 'Manutencoes em dia',
      isActive: true,
      subtitle: ' especialidades',
      icon: Icons.fitness_center_rounded,
      criterion:
          'Especialidades operacionais com sessao de manutencao nos ultimos 30 dias.',
      activity: ' especialidades com manutencao recente.',
      howToMaintain:
          'Realizar sessao de manutencao a cada 30 dias por especialidade.',
    ),
    const SealData(
      id: 'sessoes_registradas',
      name: 'Sessoes registradas',
      isActive: true,
      subtitle: 'dados completos',
      icon: Icons.assignment_turned_in_rounded,
      criterion:
          'Sessoes de treino dos ultimos 30 dias registradas com duracao, comandos trabalhados e observacoes.',
      activity: 'Sessoes registradas no ultimo mes com dados completos.',
      howToMaintain:
          'Registrar toda sessao de treino conduzida, mesmo as curtas.',
    ),
    const SealData(
      id: 'biblioteca_atualizada',
      name: 'Biblioteca atualizada',
      isActive: true,
      subtitle: 'comandos e estagios',
      icon: Icons.pets_rounded,
      criterion: 'Comandos com stage_updated_at em ate 90 dias.',
      activity: 'Biblioteca de comandos com estagios atualizados.',
      howToMaintain:
          'Atualizar estagios dos comandos apos sessoes de obediencia.',
    ),
    // ── SAUDE DO CAO ─────────────────────────────────────────────────────
    const SealData(
      id: 'vacinas_em_dia',
      name: 'Vacinas em dia',
      isActive: true,
      subtitle: 'cronograma cumprido',
      icon: Icons.vaccines_rounded,
      criterion: 'Todas as vacinas com data de proxima dose ainda nao vencida.',
      activity: 'V10, Raiva, Giardia em dia (cronograma cumprido).',
      howToMaintain: 'Aplicar vacinas conforme cronograma veterinario.',
    ),
    const SealData(
      id: 'antipulgas_em_dia',
      name: 'Antipulgas em dia',
      isActive: false,
      subtitle: 'vence em 15 dias',
      icon: Icons.shield_rounded,
      currentState: 'Ultima dose Bravecto em 02/03/2026, vence em 15 dias.',
      requiredAction:
          'Aplique antiparasitario e registre o evento de saude para reativar este selo.',
      actionButtonLabel: 'Registrar antipulgas',
      actionRoute: '/registrar/saude',
    ),
    const SealData(
      id: 'conformidade_alimentar',
      name: 'Conformidade alimentar',
      isActive: true,
      subtitle: '100% conforme laudo',
      icon: Icons.restaurant_rounded,
      criterion:
          '>= 90% de aderencia a prescricao nutricional nos ultimos 30 dias.',
      activity: '100% conforme laudo nutricional vigente.',
      howToMaintain: 'Seguir a prescricao registrada pelo veterinario.',
    ),
    const SealData(
      id: 'peso_monitorado',
      name: 'Peso monitorado',
      isActive: true,
      subtitle: 'registros recentes',
      icon: Icons.monitor_weight_rounded,
      criterion: 'Pesagem registrada nos ultimos 30 dias.',
      activity: 'Pesagens recentes registradas.',
      howToMaintain: 'Registrar pesagem a cada 30 dias.',
    ),
    // ── ADMINISTRATIVO ───────────────────────────────────────────────────
    const SealData(
      id: 'perfil_completo',
      name: 'Perfil completo',
      isActive: true,
      subtitle: 'dados atualizados',
      icon: Icons.person_rounded,
      criterion: 'Foto, funcao, RA e dados pessoais preenchidos.',
      activity: 'Cadastro completo e atualizado.',
      howToMaintain: 'Manter cadastro atualizado quando algo mudar.',
    ),
    const SealData(
      id: 'documentos_do_cao',
      name: 'Documentos do cao',
      isActive: false,
      subtitle: '2 pendentes',
      icon: Icons.assignment_rounded,
      currentState:
          '2 documentos pendentes (laudo nutricional desatualizado, sem comprovante de antipulgas recente).',
      requiredAction:
          'Anexar laudo nutricional vigente e comprovante de antipulgas atualizado.',
      actionButtonLabel: 'Ver documentos pendentes',
      actionRoute: '/cao/documentos',
    ),
  ];
}
