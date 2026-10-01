# InvTec

Sistema de gestão patrimonial da GETEC.

## Stack

- Flutter / Dart
- Supabase
- PostgreSQL
- Riverpod
- GoRouter

## Requisitos

- Flutter SDK compatível com `environment.sdk` do `pubspec.yaml` (Dart ^3.12.2)
- Um projeto Supabase configurado com as migrations em `supabase/migrations/`

## Configuração

1. Copie `.env.example` para `.env`.
2. Preencha `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` com os dados do seu projeto Supabase.
3. **Nunca versione o `.env`** — ele contém credenciais e já está no `.gitignore`.

## Instalação

```
flutter pub get
```

## Executar

```
flutter run -d windows
```

## Build (Windows)

```
flutter build windows --release
```

O executável é gerado em `build/windows/x64/runner/Release/`.

## Perfis de usuário

- `ADMIN`
- `GESTOR`
- `OPERADOR`
- `CONSULTA`
