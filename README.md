# Fatigue Guard — app Flutter (TCC)

Aplicativo **Flutter** (Android e iPhone) do TCC *Detecção de Sonolência ao Volante*.
Fluxo:

**Início → Calibração (4 etapas) → Painel ao vivo → Como funciona**

- Câmera frontal + **Google ML Kit Face Detection** (contornos faciais), tudo no aparelho:
  nenhum quadro é salvo ou enviado pela rede.
- **EAR** (olhos), **MAR** (boca) e **PERCLOS** (janela deslizante de 60 s).
- Calibração pessoal: olhos abertos, olhos fechados, bocejo e sorriso (opcional).
- Lógica temporal: piscadas (0,08–0,4 s) não geram alerta; olhos fechados por 1,2 s
  ou bocejo sustentado por 1,8 s geram **ALERTA**; checagem cruzada EAR × MAR para
  sorriso/fala; histerese de 1 s para voltar ao normal.
- Status em 3 níveis (NORMAL / ATENÇÃO / ALERTA DE SONOLÊNCIA), alerta sonoro e vibração
  (podem ser desligados), tela sempre ligada durante o monitoramento.

## Dados salvos no aparelho

Nada sai do celular. Só números e horários são gravados — **nunca imagens**.

| O quê | Onde | Para quê |
|---|---|---|
| Limiares da calibração (EAR, MAR, faixa neutra, data) | `shared_preferences` | Botão **"Usar calibração salva"** na tela inicial, sem recalibrar toda vez |
| Histórico de sessões e alertas | **SQLite** (`sqflite`), arquivo `fatigue_guard.db` | Tela **Histórico de sessões**, detalhes com linha do tempo e **exportação CSV** |

Uma sessão começa no primeiro quadro do painel ao vivo e termina ao sair do painel,
recalibrar ou minimizar o app. Sessões com menos de 10 s são descartadas.

Esquema do banco:

```sql
CREATE TABLE sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at TEXT, ended_at TEXT, duration_s REAL,
  alerts_eyes INTEGER, alerts_yawn INTEGER, attention_count INTEGER,
  max_perclos REAL, avg_blink_rate REAL,
  ear_threshold REAL, mar_threshold REAL, calibrated INTEGER
);
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER REFERENCES sessions(id) ON DELETE CASCADE,
  time TEXT, type TEXT,            -- eyes | yawn | attention
  ear REAL, mar REAL, perclos REAL
);
```

A exportação gera dois arquivos (`sessoes_*.csv` e `alertas_*.csv`, separador `;`,
abrem direto no Excel/Planilhas) e abre o menu de compartilhar do celular — útil para
montar tabelas e gráficos no capítulo de resultados do TCC.

## Como rodar

Requisitos: Flutter 3.24+ (testado com 3.47), Android Studio/SDK (Android) ou Xcode (iOS).

```bash
flutter pub get
```

```bash
flutter run
```

Use um **aparelho físico**: emuladores normalmente não têm câmera frontal real.

- Android: a permissão de câmera é pedida na primeira abertura da calibração.
- iOS: mínimo iOS 15.5 (exigido pelo ML Kit). Rode `pod install` em `ios/` se o Xcode pedir.

Testes (lógica de métricas, motor de fadiga e telas):

```bash
flutter test
```

## Estrutura

```
lib/
  main.dart                     app, tema, ciclo de vida da câmera e wakelock
  data/
    models.dart                 SessionRecord e SessionEvent
    session_recorder.dart       resume a sessão a partir das métricas (alertas, PERCLOS máx.)
    session_database.dart       banco SQLite local (sessions + events)
    calibration_store.dart      limiares calibrados em shared_preferences
    csv_export.dart             exportação CSV
  theme.dart                    paleta "Dark-First Utility" (docs/design_guidelines.json)
  vision/
    metrics.dart                EAR, MAR, média móvel, PERCLOS
    fatigue_engine.dart         limiares, calibração, máquina de estados temporal
    vision_controller.dart      câmera + ML Kit → métricas → status/alertas
  widgets/
    camera_panel.dart           preview, malha facial, guia de enquadramento
    common.dart                 cabeçalho, botões, painéis
  screens/
    home_screen.dart  calibration_screen.dart  demo_screen.dart  explanation_screen.dart
    history_screen.dart         histórico, detalhes da sessão, exportar/apagar
test/                           testes unitários e de widget
```

## Instalar no celular sem computador de desenvolvimento

O GitHub Actions (`.github/workflows/flutter-apk.yml`) gera a cada atualização:

- **`fatigue-guard-apk`** — APK para Android (instalar direto no celular);
- **`fatigue-guard-ipa`** — IPA sem assinatura para iPhone (instalar com Sideloadly/AltStore e um Apple ID).

Baixe em **Actions → execução mais recente → Artifacts**.

## Histórico

O projeto começou como um protótipo web em React Native/Expo (MediaPipe FaceLandmarker,
468 pontos), que foi totalmente substituído por este app Flutter. O código antigo
continua no histórico do Git; o documento de requisitos original está em
`docs/PRD-versao-web.md`. Principais diferenças da versão Flutter:

- detector **Google ML Kit** (contornos, ~130 pontos), que roda offline no celular;
- EAR com 16 pontos por olho (3 pares verticais ÷ largura);
- suavização em 5 quadros e 60 amostras por etapa de calibração (FPS menor no celular).

Os parâmetros ficam no topo de `lib/vision/fatigue_engine.dart`.
