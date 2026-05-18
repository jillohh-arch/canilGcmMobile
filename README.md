# Canil K9 GCM Limeira

App de gestão do canil K9 da Guarda Civil Municipal de Limeira-SP.

Ferramenta de prestação de contas, defesa profissional e prontuário
institucional dos cães operacionais. Acompanha rotina, treino,
saúde e ocorrências dos binômios condutor-cão.

## Stack

- Flutter (Dart 3.11+)
- Firebase: Auth, Firestore, Storage, App Check
- Provider (state management)
- go_router (navegação)

## Setup

```bash
flutter pub get
flutter run -d <device-id>
```

Necessário arquivo `google-services.json` (Android) e
`GoogleService-Info.plist` (iOS) do projeto Firebase configurado.

## Arquitetura

Clean architecture por feature:

```
lib/
  core/                    Recursos compartilhados (theme, services, widgets)
  features/
    <feature>/
      data/                Models, repositories
      domain/              Entities, use cases
      presentation/        Screens, viewmodels, widgets
```

## Painel web

Existe painel web React separado que consome o mesmo Firestore.
Mudanças no schema precisam ser coordenadas.
