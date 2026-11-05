# Fatigue Guard — app Flutter (TCC)

Aplicativo **Flutter** (Android e iPhone) do TCC *Detecção de Sonolência ao Volante*.
Fluxo:

**Início → Calibração (4 etapas) → Painel ao vivo → Como funciona**

- Câmera frontal + **Google ML Kit Face Detection** (contornos faciais), tudo no aparelho:
  nenhum quadro é salvo ou enviado pela rede.
- **EAR** (olhos), **MAR** (boca) e **PERCLOS** (janela deslizante de 60 s).
- Calibração pessoal: olhos abertos, olhos fechados, bocejo e sorriso (opcional). Cada etapa
  começa com contagem 3‑2‑1 com bipes e termina com um "plim" + vibração; por padrão avança
  sozinha (dá para fazer a etapa de olhos fechados sem olhar para a tela).
- Lógica temporal: piscadas (0,08–0,4 s) não geram alerta; olhos fechados por 1,2 s
  ou bocejo sustentado por 1,8 s geram **ALERTA**; checagem cruzada EAR × MAR para
  sorriso/fala; histerese de 1 s para voltar ao normal.
- **Cabeça caindo**: ângulos da cabeça do ML Kit; queda de 20° (ou inclinação lateral de 30°)
  em relação à posição normal medida na calibração, por 1,5 s → ALERTA.
- **Rosto fora da câmera**: 2 s → ATENÇÃO; 4 s → ALERTA.
- Status em 3 níveis (NORMAL / ATENÇÃO / ALERTA DE SONOLÊNCIA) com **alerta progressivo**:
  tela cheia piscando, bipe e vibração; se continuar por 4 s, sirene rápida e vibração longa.
  Botão **"Estou acordado"** silencia por 10 s. O som toca no canal de alarme (Android) e
  mesmo no modo silencioso (iPhone). Tela sempre ligada durante o monitoramento.
- **Modo deitado** (opcional): celular na horizontal no suporte do carro, com câmera e métricas
  lado a lado. Se o aparelho entregar a imagem num ângulo inesperado, o app testa as rotações
  sozinho até reencontrar o rosto.
- **Configurações** (ícone no topo de qualquer tela):
  - alertas: som, vibração e botão "Testar alerta";
  - sorriso e expressões: ligar/desligar o filtro de sorriso/fala, tolerância ao sorriso e
    "Recalibrar só o sorriso";
  - sensibilidade: limiares de EAR e MAR (ajuste manual) e refazer calibração completa;
  - tempos: olhos fechados para alertar (0,8–3 s), bocejo sustentado (1–3 s), piscadas/min
    para ATENÇÃO;
  - cabeça e rosto: liga/desliga, graus de inclinação, tempo com a cabeça caída, tempo sem rosto;
  - alertas: tela cheia e alerta progressivo (liga/desliga), testar bipe e sirene;
  - tela: permitir modo deitado;
  - dados: histórico, apagar calibração, restaurar padrões.
- Design "Dark-First Utility" de `docs/design_guidelines.json`: fontes Barlow Condensed
  (títulos/números) e Manrope (texto), ícone próprio e tela de abertura escura.

## Dados salvos no aparelho

Nada sai do celular. Só números e horários são gravados — **nunca imagens**.

| O quê | Onde | Para quê |
|---|---|---|
| Limiares da calibração (EAR, MAR, faixa neutra, data) | `shared_preferences` | Botão **"Usar calibração salva"** na tela inicial, sem recalibrar toda vez |
| Ajustes da tela de Configurações | `shared_preferences` | Som, vibração, filtro de sorriso e tempos dos alertas |
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
  time TEXT, type TEXT,            -- eyes | yawn | head | faceLost | attention
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
    settings_store.dart         ajustes da tela de Configurações
    csv_export.dart             exportação CSV
  theme.dart                    paleta "Dark-First Utility" (docs/design_guidelines.json)
  vision/
    metrics.dart                EAR, MAR, média móvel, PERCLOS
    fatigue_engine.dart         limiares, calibração, máquina de estados temporal
    vision_controller.dart      câmera + ML Kit → métricas → status/alertas
  widgets/
    camera_panel.dart           preview, malha facial, guia de enquadramento
    alert_overlay.dart          alerta em tela cheia ("Estou acordado")
    common.dart                 cabeçalho, botões, painéis
  screens/
    home_screen.dart  calibration_screen.dart  demo_screen.dart  explanation_screen.dart
    history_screen.dart         histórico, detalhes da sessão, exportar/apagar
    settings_screen.dart        configurações (alertas, sorriso, sensibilidade, tempos)
assets/
  fonts/                        Barlow Condensed + Manrope (licença OFL)
  sounds/alerta.wav             bipe do alerta
  sounds/sirene.wav             sirene do alerta intensificado
  icon/                         ícone do app (gerado com flutter_launcher_icons)
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
