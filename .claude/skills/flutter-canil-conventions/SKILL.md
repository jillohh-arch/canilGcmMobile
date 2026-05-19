---
name: flutter-canil-conventions
description: Convenções Flutter e padrões de código do projeto Canil K9
alwaysApply: true
---

# Convenções Flutter — Canil K9

## Estrutura de Pastas

```
lib/
├── core/
│   ├── controllers/    # Controllers compartilhados
│   ├── domain/         # Entidades e interfaces base
│   ├── services/       # Serviços (PDF, auth, etc)
│   ├── theme/          # AppTheme, cores, tipografia
│   ├── utils/          # Helpers e extensões
│   └── widgets/        # Widgets reutilizáveis (Header, BottomNav, etc)
├── features/
│   └── {feature}/
│       ├── data/           # Repositories (implementação Firestore)
│       ├── domain/         # Models, entidades, interfaces
│       └── presentation/
│           ├── screens/    # Telas (StatelessWidget com Consumer)
│           ├── viewmodels/ # ChangeNotifier (Provider)
│           └── widgets/    # Widgets específicos da feature
└── main.dart
```

## Nomenclatura

- Arquivos: `snake_case.dart` (ex: `dog_profile_screen.dart`)
- Classes: `PascalCase` (ex: `DogProfileScreen`)
- Variáveis/métodos: `camelCase`
- Constantes: `camelCase` (Dart convention, não SCREAMING_CASE)
- Features: singular snake_case (ex: `training`, `health`, `incidents`)

## Stack

- State management: Provider (ChangeNotifier)
- Backend: Firebase (Auth, Firestore, Storage, AppCheck)
- Navegação: Navigator manual (push/pop)
- Gráficos: fl_chart
- PDF: pdf + printing
- Auth local: local_auth
- Geolocalização: geolocator

## Criar Nova Feature

1. Criar pasta `lib/features/{nome}/`
2. Criar subpastas: `data/`, `domain/`, `presentation/screens/`, `presentation/viewmodels/`
3. Model em `domain/` com `fromMap()` e `toMap()` (conversão snake_case ↔ camelCase)
4. Repository em `data/` com acesso Firestore
5. ViewModel em `presentation/viewmodels/` extends ChangeNotifier
6. Screen em `presentation/screens/`
7. Registrar Provider no widget tree (MultiProvider no app)

## Criar Nova Tela

1. Arquivo: `lib/features/{feature}/presentation/screens/{nome}_screen.dart`
2. Classe: `{Nome}Screen extends StatelessWidget`
3. ViewModel correspondente se tiver estado
4. Rota: registrar no Navigator (push nomeado ou direto)

## Firestore ↔ Dart

Campos Firestore em `snake_case`, models Dart em `camelCase`:

```dart
class DogModel {
  final String activeDogId;
  
  factory DogModel.fromMap(Map<String, dynamic> map) {
    return DogModel(activeDogId: map['active_dog_id']);
  }
  
  Map<String, dynamic> toMap() {
    return {'active_dog_id': activeDogId};
  }
}
```

## Coleções Firestore

- Plural, snake_case: `/users`, `/dogs`, `/occurrences`, `/training_sessions`
- Subcoleções: `/dogs/{id}/health_events`, `/dogs/{id}/commands`
- IDs: UUID (package uuid)

## Widgets Compartilhados

Ficam em `core/widgets/`. Exemplos:
- Header Universal
- Bottom Navigation (5 itens fixos)
- Bottom Sheet padrão
- Cards institucionais
- Botões (primário ciano fill, destrutivo vermelho outline)
