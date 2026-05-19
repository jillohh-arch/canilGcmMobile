#!/bin/bash
# Hook executado quando Claude Code inicia uma sessão
# Mostra status atual do projeto

echo ""
echo "🛡 ═══════════════════════════════════════"
echo "   APP CANIL K9 · GCM LIMEIRA"
echo "═══════════════════════════════════════════"
echo ""

# Versão atual
if [ -f "pubspec.yaml" ]; then
  VERSION=$(grep '^version:' pubspec.yaml | head -1 | cut -d ':' -f2 | xargs)
  echo "📦 Versão: $VERSION"
fi

# Branch atual
if [ -d ".git" ]; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  if [ -n "$BRANCH" ]; then
    echo "🌿 Branch: $BRANCH"
  fi
  
  # Status do repositório
  CHANGES=$(git status --porcelain 2>/dev/null | wc -l | xargs)
  if [ "$CHANGES" -gt 0 ]; then
    echo "⚠️  $CHANGES arquivo(s) modificado(s)"
  else
    echo "✅ Working directory limpo"
  fi
fi

# Verificar documentação de referência
echo ""
if [ -d "temp/docs" ]; then
  DOCS_COUNT=$(ls temp/docs 2>/dev/null | wc -l | xargs)
  echo "📚 Documentação: $DOCS_COUNT arquivos em temp/docs/"
fi

if [ -d "temp/mockups" ]; then
  MOCKUPS_COUNT=$(ls temp/mockups/*.html 2>/dev/null | wc -l | xargs)
  echo "🎨 Mockups: $MOCKUPS_COUNT arquivos em temp/mockups/"
fi

# Skills carregadas
if [ -d ".claude/skills" ]; then
  SKILLS_COUNT=$(ls -d .claude/skills/*/ 2>/dev/null | wc -l | xargs)
  echo "🧠 Skills do projeto: $SKILLS_COUNT carregadas"
fi

echo ""
echo "📋 Lembretes:"
echo "   • Trilha de auditoria obrigatória em escritas Firestore"
echo "   • Soft delete sempre · nunca hard delete"
echo "   • Consulte temp/docs/ antes de implementar features"
echo "   • Painel React acessa mesmo Firestore · cuidado com mudanças destrutivas"
echo ""
echo "═══════════════════════════════════════════"
echo ""
