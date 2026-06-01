# Sessao 2026-06-01 - Integridade, selo e verificador publico

## Objetivo

Fortalecer a integridade probatoria das ocorrencias finalizadas, conectando o verificador real ao app/PDF e alinhando o hash local com o endpoint publico `/v/{id}`.

## Alteracoes principais

### App Flutter

- `IntegrityVerificationService.verifyById` passou a fazer verificacao documental por padrao.
- A verificacao profunda de midias ficou explicita por parametro (`verifyMediaBytes: true`), evitando baixar fotos pesadas automaticamente.
- A tela de detalhe do historico passou a exibir verificacao documental automatica para ocorrencias finalizadas.
- A tela de detalhe passou a oferecer acao sob demanda: `Verificar fotos no Storage`.
- O PDF de ocorrencia passou a receber o veredito do verificador antes de renderizar o bloco de hash.
- O PDF deixou de declarar "integro" apenas pela existencia de hash armazenado.
- O texto do QR no PDF foi ajustado para diferenciar consulta rapida documental e verificacao profunda de midias.

### Hash canonico

- A serializacao Dart foi alinhada com a Function publica:
  - arrays canonicos com `trim`, remocao de vazios, remocao de duplicatas e ordenacao;
  - eventos soft-deletados ignorados no payload;
  - preservacao da compatibilidade v1, v2, v3 e v4.
- A Function foi mantida como referencia para nao invalidar hashes v4 ja selados no servidor.

### Firebase Functions

- O endpoint publico `/v/{id}` continua com consulta rapida por padrao.
- Foi adicionada verificacao profunda via `?media=1`.
- A verificacao profunda baixa as midias do Firebase Storage, recalcula SHA-256 e compara com os hashes gravados.
- Quando o documento confere mas uma midia diverge, o retorno passa a informar:
  - `status: media_broken`;
  - `intact: false`;
  - `document_intact: true`;
  - `media_issues` com os detalhes.
- O HTML publico mostra se a verificacao foi documental ou profunda e oferece link para verificar fotos no Storage.

## Arquivos alterados

- `functions/src/index.ts`
- `lib/core/services/integrity_verification_service.dart`
- `lib/core/services/occurrence_finalization_service.dart`
- `lib/core/services/pdf_generator/occurrence_pdf_generator.dart`
- `lib/features/history/presentation/screens/history_detail_screen.dart`
- `lib/features/occurrences/presentation/view_models/occurrence_view_model.dart`
- `test/core/services/integrity_verification_service_test.dart`

## Validacoes executadas

- `npm run build` em `functions/`.
- `dart analyze` nos arquivos alterados.
- `flutter test test/core/services/integrity_verification_service_test.dart test/core/services/occurrence_finalization_service_test.dart`.
- `git diff --check`.

## Observacoes

- A verificacao profunda de midias nao roda automaticamente ao abrir historico, gerar PDF ou acessar o QR, para evitar lentidao e consumo excessivo de memoria/rede.
- O caminho probatorio recomendado no uso real e:
  1. abrir a ocorrencia finalizada;
  2. conferir o selo documental;
  3. acionar verificacao de fotos quando houver questionamento;
  4. no PDF, usar o QR para consulta publica e `?media=1` para verificacao completa das midias.

