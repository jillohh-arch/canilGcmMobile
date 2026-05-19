#!/bin/bash
# Hook executado antes de commit no git
# Garante que testes e analyze passam antes de commitar

echo ""
echo "🔍 Validações pré-commit..."
echo ""

EXIT_CODE=0

# 1. Flutter analyze (projeto inteiro)
echo "📊 Rodando flutter analyze..."
ANALYZE_OUTPUT=$(flutter analyze 2>&1)
ANALYZE_RESULT=$?

if [ $ANALYZE_RESULT -ne 0 ]; then
  echo "❌ Analyzer encontrou problemas:"
  echo "$ANALYZE_OUTPUT" | grep -E "(error|warning)" | head -20
  echo ""
  echo "💡 Corrija os problemas e tente novamente."
  echo "   Pra ignorar (não recomendado), use: git commit --no-verify"
  EXIT_CODE=1
else
  echo "✅ Analyzer limpo"
fi

# 2. Testes (se houver pasta test/)
if [ -d "test" ]; then
  TESTS_COUNT=$(find test -name "*_test.dart" 2>/dev/null | wc -l | xargs)
  
  if [ "$TESTS_COUNT" -gt 0 ]; then
    echo ""
    echo "🧪 Rodando $TESTS_COUNT testes..."
    
    TEST_OUTPUT=$(flutter test 2>&1)
    TEST_RESULT=$?
    
    if [ $TEST_RESULT -ne 0 ]; then
      echo "❌ Testes falharam:"
      echo "$TEST_OUTPUT" | tail -20
      echo ""
      echo "💡 Corrija os testes e tente novamente."
      EXIT_CODE=1
    else
      echo "✅ Todos os testes passaram"
    fi
  fi
fi

echo ""

if [ $EXIT_CODE -eq 0 ]; then
  echo "🎉 Validações OK · prossegue commit"
  echo ""
else
  echo "🚫 Commit bloqueado · corrija os problemas acima"
  echo ""
fi

exit $EXIT_CODE
