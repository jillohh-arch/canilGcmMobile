#!/bin/bash
# Hook executado após Claude editar um arquivo
# Roda formatação e análise automática em arquivos Dart

FILE_PATH="$1"

# Sair silenciosamente se não recebeu arquivo
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Sair silenciosamente se não é arquivo Dart
if [[ ! "$FILE_PATH" == *.dart ]]; then
  exit 0
fi

# Sair silenciosamente se arquivo não existe (foi deletado)
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

echo ""
echo "🔍 Validando $FILE_PATH..."

# 1. Formatar (silencioso se já está formatado)
dart format "$FILE_PATH" --output none --set-exit-if-changed > /dev/null 2>&1
FORMAT_RESULT=$?

if [ $FORMAT_RESULT -ne 0 ]; then
  echo "🎨 Aplicando dart format..."
  dart format "$FILE_PATH" > /dev/null 2>&1
fi

# 2. Analyze (apenas no arquivo editado, não no projeto inteiro)
ANALYZE_OUTPUT=$(flutter analyze "$FILE_PATH" 2>&1)
ANALYZE_RESULT=$?

if [ $ANALYZE_RESULT -ne 0 ]; then
  # Filtrar para mostrar só warnings/erros desse arquivo
  echo "⚠️  Analyzer encontrou problemas:"
  echo "$ANALYZE_OUTPUT" | grep -E "(error|warning|info)" | head -20
  exit 0  # não bloqueia, só informa
fi

echo "✅ Arquivo limpo (format + analyze)"
echo ""
exit 0
