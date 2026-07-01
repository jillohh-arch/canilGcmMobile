import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/onboarding/presentation/screens/onboarding_screen.dart';

/// Help Center screen with expandable accordion sections.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Central de Ajuda',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Highlight card: versão de teste + rever introdução
          const _TestVersionCard(),
          const SizedBox(height: 20),
          const _HelpSection(
            icon: Icons.login_rounded,
            title: 'Primeiro acesso',
            content: _PrimeiroAcessoContent(),
          ),
          const _HelpSection(
            icon: Icons.home_outlined,
            title: 'Assumir turno',
            content: _AssumirTurnoContent(),
          ),
          const _HelpSection(
            icon: Icons.explore_outlined,
            title: 'Navegação',
            content: _NavegacaoContent(),
          ),
          const _HelpSection(
            icon: Icons.shield_rounded,
            title: 'Ocorrências',
            content: _OcorrenciasContent(),
          ),
          const _HelpSection(
            icon: Icons.auto_awesome_rounded,
            title: 'IA assistiva',
            content: _IAAssistivaContent(),
          ),
          const _HelpSection(
            icon: Icons.restaurant_rounded,
            title: 'Análise nutricional',
            content: _AnaliseNutricionalContent(),
          ),
          const _HelpSection(
            icon: Icons.fitness_center_rounded,
            title: 'Treinamentos',
            content: _TreinamentosContent(),
          ),
          const _HelpSection(
            icon: Icons.health_and_safety_rounded,
            title: 'Saúde do K9',
            content: _SaudeK9Content(),
          ),
          const _HelpSection(
            icon: Icons.notifications_outlined,
            title: 'Notificações',
            content: _NotificacoesContent(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Card de destaque: versão de teste + rever introdução ──────────────────────

class _TestVersionCard extends StatelessWidget {
  const _TestVersionCard();

  void _reopenOnboarding(BuildContext context) {
    HapticFeedback.lightImpact();
    final nav = Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(onComplete: () => nav.pop()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warning.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withAlpha(102)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.science_outlined,
                  color: AppTheme.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Esta é uma versão de teste',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _BulletList([
            'Explore todas as funções à vontade.',
            'Achou bug, travamento ou algo estranho? Reporte ao responsável pelo teste.',
            'Seu retorno ajuda a ajustar o app antes do lançamento oficial.',
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _reopenOnboarding(context),
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: Text(
                'Rever introdução',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.primary.withAlpha(102)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Accordion section ─────────────────────────────────────────────────────────

class _HelpSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final Widget content;

  const _HelpSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  State<_HelpSection> createState() => _HelpSectionState();
}

class _HelpSectionState extends State<_HelpSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isExpanded
              ? AppTheme.primary.withAlpha(77)
              : AppTheme.surfaceWhiteBorderSubtle,
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isExpanded = !_isExpanded);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      widget.icon,
                      color: AppTheme.primary,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.content,
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ─── Bullets ───────────────────────────────────────────────────────────────────

class _BulletList extends StatelessWidget {
  final List<String> items;

  const _BulletList(this.items);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => _BulletItem(item)).toList(),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;

  const _BulletItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Content Widgets ──────────────────────────────────────────────────────────

class _PrimeiroAcessoContent extends StatelessWidget {
  const _PrimeiroAcessoContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Entre com seu RA e senha.',
      'Autorize notificações e localização (importantes pra avisos e ocorrências).',
      'Se não houver turno ativo, o app te leva pra assumir turno.',
    ]);
  }
}

class _AssumirTurnoContent extends StatelessWidget {
  const _AssumirTurnoContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Confira seu usuário e escolha o K9 de serviço.',
      'Veja os alertas do cão (saúde, pendências) antes de assumir.',
      'Assuma a viatura quando estiver em operação.',
      'A troca de K9 ou viatura no meio do turno fica registrada para auditoria.',
    ]);
  }
}

class _NavegacaoContent extends StatelessWidget {
  const _NavegacaoContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Turno: painel do dia, status e atalhos.',
      'Treino: modalidades e registros de formação/manutenção.',
      'Nova (botão central): inicia ou continua ocorrência.',
      'Saúde: prontuário do K9 ativo.',
      'Histórico: timeline dos registros.',
    ]);
  }
}

class _OcorrenciasContent extends StatelessWidget {
  const _OcorrenciasContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Toque em "Nova", escolha a natureza e confirme o início.',
      'Registre eventos durante a ocorrência (deslocamento, busca, material localizado, fotos).',
      'A guarnição vem do turno/viatura — integrantes podem receber notificação para tomar ciência.',
      'Na finalização, revise relato, resultado, anexos e equipe.',
      'Ocorrência finalizada é documento institucional, com integridade e assinatura. Revise sempre antes de finalizar.',
    ]);
  }
}

class _IAAssistivaContent extends StatelessWidget {
  const _IAAssistivaContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Escreva seu relato bruto no campo "Relato institucional".',
      'Toque em "Transformar em minuta": a IA organiza em texto formal.',
      'A IA aponta "pontos de atenção" (dados que faltam, divergências) — confira-os.',
      'Revise e toque em "Usar minuta". A IA NÃO finaliza a ocorrência; você é responsável pelo conteúdo final.',
      'Se a rede falhar, o app gera uma versão local simples; tente de novo com sinal melhor.',
    ]);
  }
}

class _AnaliseNutricionalContent extends StatelessWidget {
  const _AnaliseNutricionalContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Na aba Saúde > Nutrição, escolha o período (7/30/60 dias) e gere a análise.',
      'A IA cruza treinos, peso e registros e dá orientações operacionais.',
      'É apoio, não prescrição: qualquer ajuste de dieta deve passar pelo responsável técnico/veterinário.',
      'Quanto mais você registrar (alimentação, peso, intensidade de treino), melhor a análise.',
    ]);
  }
}

class _TreinamentosContent extends StatelessWidget {
  const _TreinamentosContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Aba Treino reúne as modalidades (Busca & Captura, Detecção, Guarda & Proteção, Obediência).',
      'Registre sessões; marcos e evolução dependem de decisão do condutor/instrutor.',
      'A evolução de módulo precisa de aprovação do Instrutor K9.',
      'Sessões com trajeto (Busca & Captura) usam GPS — confira sinal e bateria antes.',
    ]);
  }
}

class _SaudeK9Content extends StatelessWidget {
  const _SaudeK9Content();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'Prontuário com Resumo, Vacinas, Peso, Nutrição e Documentos.',
      'Mantenha pesagens e registros em dia — alimentam alertas e a análise nutricional.',
    ]);
  }
}

class _NotificacoesContent extends StatelessWidget {
  const _NotificacoesContent();

  @override
  Widget build(BuildContext context) {
    return const _BulletList([
      'O sininho mostra pendências: convite de guarnição, assinatura pendente, lembrete de plantão.',
      '"Requer ação" = precisa de decisão sua. "Avisos" = informativos.',
      'Use "Limpar todos" para arquivar avisos resolvidos (o registro é preservado).',
    ]);
  }
}
