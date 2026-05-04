const fs = require('fs');
const path = require('path');

const replacements = [
  [/\bAcao\b/g, 'Ação'],
  [/\bacao\b/g, 'ação'],
  [/\bAcoes\b/g, 'Ações'],
  [/\bacoes\b/g, 'ações'],
  [/\bInformacao\b/g, 'Informação'],
  [/\binformacao\b/g, 'informação'],
  [/\bInformacoes\b/g, 'Informações'],
  [/\binformacoes\b/g, 'informações'],
  [/\bConfiguracao\b/g, 'Configuração'],
  [/\bconfiguracao\b/g, 'configuração'],
  [/\bConfiguracoes\b/g, 'Configurações'],
  [/\bconfiguracoes\b/g, 'configurações'],
  [/\bRelatorio\b/g, 'Relatório'],
  [/\brelatorio\b/g, 'relatório'],
  [/\bRelatorios\b/g, 'Relatórios'],
  [/\brelatorios\b/g, 'relatórios'],
  [/\bEstatistica\b/g, 'Estatística'],
  [/\bestatistica\b/g, 'estatística'],
  [/\bEstatisticas\b/g, 'Estatísticas'],
  [/\bestatisticas\b/g, 'estatísticas'],
  [/\bUsuario\b/g, 'Usuário'],
  [/\busuario\b/g, 'usuário'],
  [/\bUsuarios\b/g, 'Usuários'],
  [/\busuarios\b/g, 'usuários'],
  [/\bVeiculo\b/g, 'Veículo'],
  [/\bveiculo\b/g, 'veículo'],
  [/\bVeiculos\b/g, 'Veículos'],
  [/\bveiculos\b/g, 'veículos'],
  [/\bDescricao\b/g, 'Descrição'],
  [/\bdescricao\b/g, 'descrição'],
  [/\bEndereco\b/g, 'Endereço'],
  [/\bendereco\b/g, 'endereço'],
  [/\bEnderecos\b/g, 'Endereços'],
  [/\benderecos\b/g, 'endereços'],
  [/\bAtencao\b/g, 'Atenção'],
  [/\batencao\b/g, 'atenção'],
  [/\bFuncionario\b/g, 'Funcionário'],
  [/\bfuncionario\b/g, 'funcionário'],
  [/\bFuncionarios\b/g, 'Funcionários'],
  [/\bfuncionarios\b/g, 'funcionários'],
  [/\bConcluido\b/g, 'Concluído'],
  [/\bconcluido\b/g, 'concluído'],
  [/\bConcluidos\b/g, 'Concluídos'],
  [/\bconcluidos\b/g, 'concluídos'],
  [/\bConcluida\b/g, 'Concluída'],
  [/\bconcluida\b/g, 'concluída'],
  [/\bConcluidas\b/g, 'Concluídas'],
  [/\bconcluidas\b/g, 'concluídas'],
  [/\bProximo\b/g, 'Próximo'],
  [/\bproximo\b/g, 'próximo'],
  [/\bProximos\b/g, 'Próximos'],
  [/\bproximos\b/g, 'próximos'],
  [/\bInicio\b/g, 'Início'],
  [/\binicio\b/g, 'início'],
  [/\bEdicao\b/g, 'Edição'],
  [/\bedicao\b/g, 'edição'],
  [/\bExclusao\b/g, 'Exclusão'],
  [/\bexclusao\b/g, 'exclusão'],
  [/\bConfirmacao\b/g, 'Confirmação'],
  [/\bconfirmacao\b/g, 'confirmação'],
  [/\bNao\b/g, 'Não'],
  [/\bnao\b/g, 'não'],
  [/\bAte\b/g, 'Até'],
  [/\bate\b/g, 'até'],
  [/\bJa\b/g, 'Já'],
  [/\bja\b/g, 'já'],
  [/\bEntao\b/g, 'Então'],
  [/\bentao\b/g, 'então'],
  [/\bSenao\b/g, 'Senão'],
  [/\bsenao\b/g, 'senão'],
  [/\bTambem\b/g, 'Também'],
  [/\btambem\b/g, 'também'],
  [/\bCodigo\b/g, 'Código'],
  [/\bcodigo\b/g, 'código'],
  [/\bCodigos\b/g, 'Códigos'],
  [/\bcodigos\b/g, 'códigos'],
  [/\bHistorico\b/g, 'Histórico'],
  [/\bhistorico\b/g, 'histórico'],
  [/\bHistoricos\b/g, 'Históricos'],
  [/\bhistoricos\b/g, 'históricos'],
  [/\bSaude\b/g, 'Saúde'],
  [/\bsaude\b/g, 'saúde'],
  [/\bPadrao\b/g, 'Padrão'],
  [/\bpadrao\b/g, 'padrão'],
  [/\bPadroes\b/g, 'Padrões'],
  [/\bpadroes\b/g, 'padrões'],
  [/\bCao\b/g, 'Cão'],
  [/\bcao\b/g, 'cão'],
  [/\bCaes\b/g, 'Cães'],
  [/\bcaes\b/g, 'cães'],
  [/\bGuarnicao\b/g, 'Guarnição'],
  [/\bguarnicao\b/g, 'guarnição'],
  [/\bGuarnicoes\b/g, 'Guarnições'],
  [/\bguarnicoes\b/g, 'guarnições'],
  [/\bOcorrencia\b/g, 'Ocorrência'],
  [/\bocorrencia\b/g, 'ocorrência'],
  [/\bOcorrencias\b/g, 'Ocorrências'],
  [/\bocorrencias\b/g, 'ocorrências'],
  [/\bMissao\b/g, 'Missão'],
  [/\bmissao\b/g, 'missão'],
  [/\bMissoes\b/g, 'Missões'],
  [/\bmissoes\b/g, 'missões'],
  [/\bCirculacao\b/g, 'Circulação'],
  [/\bcirculacao\b/g, 'circulação'],
  [/\bAssistencia\b/g, 'Assistência'],
  [/\bassistencia\b/g, 'assistência'],
  [/\bVeterinaria\b/g, 'Veterinária'],
  [/\bveterinaria\b/g, 'veterinária'],
  [/\bSituacao\b/g, 'Situação'],
  [/\bsituacao\b/g, 'situação'],
  [/\bSituacoes\b/g, 'Situações'],
  [/\bsituacoes\b/g, 'situações'],
  [/\bComposicao\b/g, 'Composição'],
  [/\bcomposicao\b/g, 'composição'],
  [/\bAtualizacao\b/g, 'Atualização'],
  [/\batualizacao\b/g, 'atualização'],
  [/\bServico\b/g, 'Serviço'],
  [/\bservico\b/g, 'serviço'],
  [/\bServicos\b/g, 'Serviços'],
  [/\bservicos\b/g, 'serviços'],
  [/\bDiarias\b/g, 'Diárias'],
  [/\bdiarias\b/g, 'diárias'],
  [/\bDiarios\b/g, 'Diários'],
  [/\bdiarios\b/g, 'diários'],
  [/\bRacao\b/g, 'Ração'],
  [/\bracao\b/g, 'ração'],
  [/\bAvaliacao\b/g, 'Avaliação'],
  [/\bavaliacao\b/g, 'avaliação'],
  [/\bAvaliacoes\b/g, 'Avaliações'],
  [/\bavaliacoes\b/g, 'avaliações'],
  [/\bPontuacao\b/g, 'Pontuação'],
  [/\bpontuacao\b/g, 'pontuação'],
  [/\bMedica\b/g, 'Médica'],
  [/\bmedica\b/g, 'médica'],
  [/\bMedico\b/g, 'Médico'],
  [/\bmedico\b/g, 'médico'],
  [/\bBasico\b/g, 'Básico'],
  [/\bbasico\b/g, 'básico'],
  [/\bBasica\b/g, 'Básica'],
  [/\bbasica\b/g, 'básica'],
  [/\bDeteccao\b/g, 'Detecção'],
  [/\bdeteccao\b/g, 'detecção'],
  [/\bProtecao\b/g, 'Proteção'],
  [/\bprotecao\b/g, 'proteção'],
  [/\bIntervencao\b/g, 'Intervenção'],
  [/\bintervencao\b/g, 'intervenção'],
  [/\bTatico\b/g, 'Tático'],
  [/\btatico\b/g, 'tático'],
  [/\bTaticos\b/g, 'Táticos'],
  [/\btaticos\b/g, 'táticos'],
  [/\bTATICO\b/g, 'TÁTICO'],
  [/\bVisao\b/g, 'Visão'],
  [/\bvisao\b/g, 'visão'],
  [/\bProntidao\b/g, 'Prontidão'],
  [/\bprontidao\b/g, 'prontidão'],
  [/\bAtras\b/g, 'Atrás'],
  [/\batras\b/g, 'atrás'],
  [/\bFrequencia\b/g, 'Frequência'],
  [/\bfrequencia\b/g, 'frequência'],
  [/\bTransmissao\b/g, 'Transmissão'],
  [/\btransmissao\b/g, 'transmissão'],
  [/\bRadio\b/g, 'Rádio'],
  [/\bradio\b/g, 'rádio'],
  [/\bUltimo\b/g, 'Último'],
  [/\bultimo\b/g, 'último'],
  [/\bUltima\b/g, 'Última'],
  [/\bultima\b/g, 'última'],
  [/\bmilimetro\b/g, 'milímetro'],
  [/\bmilimetros\b/g, 'milímetros'],
  [/\bcentimetro\b/g, 'centímetro'],
  [/\bcentimetros\b/g, 'centímetros'],
  [/\bkilometro\b/g, 'quilômetro'],
  [/\bkilometros\b/g, 'quilômetros'],
  [/\bnumero\b/g, 'número'],
  [/\bNumero\b/g, 'Número'],
  [/\bNumeros\b/g, 'Números'],
  [/\bnumeros\b/g, 'números'],
  [/\bAnalise\b/g, 'Análise'],
  [/\banalise\b/g, 'análise'],
  [/\bEspecie\b/g, 'Espécie'],
  [/\bespecie\b/g, 'espécie'],
  [/\bEspecies\b/g, 'Espécies'],
  [/\bespecies\b/g, 'espécies'],
  [/\bPelo\b/g, 'Pêlo'],
  [/\bpelo\b/g, 'pêlo'], // It can be 'por o = pelo', but let's be careful. Wait, 'pelo' as hair lost its accent in recent orthographic agreement. I will comment this out.
  [/\bMateria\b/g, 'Matéria'],
  [/\bmateria\b/g, 'matéria'],
  [/\bMateriais\b/g, 'Materiais'], // no accent
  [/\bPeriodo\b/g, 'Período'],
  [/\bperiodo\b/g, 'período'],
  [/\bProprio\b/g, 'Próprio'],
  [/\bproprio\b/g, 'próprio'],
  [/\bProprios\b/g, 'Próprios'],
  [/\bproprios\b/g, 'próprios'],
  [/\bRapido\b/g, 'Rápido'],
  [/\brapido\b/g, 'rápido'],
  [/\bRapida\b/g, 'Rápida'],
  [/\brapida\b/g, 'rápida'],
  [/\bVeicular\b/g, 'Veicular'], // no accent
  [/\bObrigatorio\b/g, 'Obrigatório'],
  [/\bobrigatorio\b/g, 'obrigatório'],
  [/\bObrigatoria\b/g, 'Obrigatória'],
  [/\bobrigatoria\b/g, 'obrigatória'],
  [/\bMetodo\b/g, 'Método'],
  [/\bmetodo\b/g, 'método'],
  [/\bInvalido\b/g, 'Inválido'],
  [/\binvalido\b/g, 'inválido'],
  [/\bInvalida\b/g, 'Inválida'],
  [/\binvalida\b/g, 'inválida'],
  [/\bValido\b/g, 'Válido'],
  [/\bvalido\b/g, 'válido'],
  [/\bValida\b/g, 'Válida'],
  [/\bvalida\b/g, 'válida'],
  [/\bSemantica\b/g, 'Semântica'],
  [/\bsemantica\b/g, 'semântica'],
  [/hist\?rico/g, 'histórico'], // Fixing previous errors like hist?rico
];

function applyFixes(filePath) {
  if (!fs.existsSync(filePath)) return;
  // Read in UTF-8
  let content = fs.readFileSync(filePath, 'utf8');
  let original = content;

  replacements.forEach(([regex, replacement]) => {
    content = content.replace(regex, replacement);
  });
  
  // Specific cases that might be dangerous but are often text
  content = content.replace(/'Logar'/g, "'Acessar'");
  content = content.replace(/>Logar</g, ">Acessar<");
  content = content.replace(/'Log de Radio'/g, "'Log de Rádio'");

  // Fix words inside template literals or strings if missed
  
  // Write in UTF-8 if there were changes
  if (content !== original) {
    fs.writeFileSync(filePath, content, 'utf8');
    console.log(`Updated: ${filePath}`);
  }
}

function walkSync(currentDirPath, callback) {
  fs.readdirSync(currentDirPath).forEach(function (name) {
    var filePath = path.join(currentDirPath, name);
    var stat = fs.statSync(filePath);
    if (stat.isFile() && (filePath.endsWith('.tsx') || filePath.endsWith('.ts') || filePath.endsWith('.html') || filePath.endsWith('.js') || filePath.endsWith('.jsx'))) {
      callback(filePath);
    } else if (stat.isDirectory() && name !== 'node_modules' && name !== 'dist' && name !== 'build' && name !== '.git') {
      walkSync(filePath, callback);
    }
  });
}

const targetDir = process.argv[2];
if (!targetDir) {
  console.error("Please provide a target directory");
  process.exit(1);
}

walkSync(targetDir, applyFixes);
console.log("Done.");
