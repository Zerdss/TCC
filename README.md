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
- **Calibração rígida** (`lib/vision/calibration.dart`): cada quadro só conta com o rosto
  enquadrado, a cabeça parada (< 35°/s) e na mesma posição da 1ª etapa (±10°); piscadas são
  descartadas. 80 quadros válidos por etapa, sem picos (filtro por desvio robusto). Cada etapa é
  analisada: variação dos olhos abertos ≤ 12%, poucas piscadas, olho fechado ≥ 12% menor que o
  aberto (ou probabilidade do ML Kit 0,4 menor), bocejo com pico de MAR ≥ 0,35 e 0,15 acima da boca
  fechada (no bocejo e no sorriso a cabeça pode mexer e bastam ~2–3 s de boca aberta), sorriso
  identificado. Bocejo e sorriso podem ser pulados (usa o limite padrão). Etapa reprovada é repetida (3 tentativas; olho fechado parecido com o
  aberto permite "continuar com reforço"). No fim aparece a **análise do rosto** (posição do
  celular, formato dos olhos × padrão, diferença entre os olhos, separação aberto × fechado,
  bocejo, sorriso e confiança) e a calibração só é salva quando o usuário confirma; sair no meio
  mantém a calibração anterior.
- Lógica temporal: piscadas (0,08–0,4 s) não geram alerta; olhos fechados por 1,2 s
  ou bocejo sustentado por 1,8 s geram **ALERTA**; checagem cruzada EAR × MAR para
  sorriso/fala; histerese de 1 s para voltar ao normal.
- **Cabeça caindo**: ângulos da cabeça do ML Kit; queda de 20° (ou inclinação lateral de 30°)
  em relação à posição normal medida na calibração, por 1,5 s com olhos fechados → ALERTA
  (com olhos indefinidos, espera 3 s).
- **Movimento normal não é sono** (evita alarme falso): cabeça virada mais de 25° para o lado →
  olhos não são medidos (ficam distorcidos); cabeça baixa com olhos abertos → "olhando para baixo",
  sem alarme, e o olho só conta como fechado se estiver bem abaixo do limiar (pálpebra baixa ao
  olhar para baixo); giro rápido da cabeça (> 120°/s) pausa a medição. Desvio do olhar por mais de
  2,5 s → ATENÇÃO ("volte a atenção à estrada").
- **Rosto fora da câmera**: 2 s → ATENÇÃO; 4 s → ALERTA.
- **Posição do celular**: na calibração (olhos abertos, olhando para a estrada) o app mede o ângulo do
  rosto na câmera e classifica o celular como de frente (reto), abaixo, acima ou de lado do rosto
  (ou combinações). A posição aparece na calibração, no painel ao vivo e em Configurações; os
  limites e a posição "normal" da cabeça são os dessa posição. Bem abaixo/acima (≥ 25°) ou bem de
  lado (≥ 30°) → reforço automático. Mudou o celular de lugar: recalibrar.
- **Modo inclinação (celular abaixo do rosto)**: visto de baixo, o olho parece achatado e o EAR
  "acha" que ele está fechado. Com o celular abaixo do rosto (medido na calibração) ou olhos pouco
  visíveis, a decisão passa a ser pela **cabeça**: cabeça caída por 2 s (1,2 s se os olhos também
  parecerem fechados) ou **cabeceio** — a cabeça cai ≥ 10° e volta em 0,25–2,5 s — 3 vezes em
  1 minuto → ALERTA; 2 cabeceios → ATENÇÃO. Olhadas rápidas para baixo com o olho aberto não contam.
  Olhos fechados sozinhos só alertam se a probabilidade do ML Kit separou bem aberto × fechado na
  calibração, e com o dobro do tempo; piscadas e PERCLOS não geram aviso nesse modo. O bocejo segue
  igual.
- **Dia / Noite / Automático** (escolha da pessoa, como o claro/escuro dos sites; botão no painel ao vivo e
  em Configurações; padrão Dia). **Cada modo tem os seus próprios ajustes** (sensibilidade, tempos, alertas):
  mexer no modo Noite não muda o Dia. Salvos separados (chaves com prefixo `night.`).
- **Modo noite (pouca luz)** (`lib/vision/night_mode.dart`): no Automático, o app mede o brilho médio da
  imagem; abaixo de 45/255 por 3 s conta como escuro (volta a claro acima de 65, histerese). No modo noite, a tela do app
  vira luz de apoio: a cada 20 s (ajustável de 10 a 60 s) o brilho **sobe devagar** (1,5 s), fica no
  máximo (60%, ajustável) por 3 s e **desce devagar** — sem clarão. Se nesse momento houver sinal de sono
  com o rosto visível, a luz fica acesa até normalizar (no máximo 15 s). No escuro a decisão vai para a
  cabeça (modo inclinação) e o rosto sumir não gera alarme de "rosto fora", só o aviso "Pouca luz". Só
  funciona com o app aberto na tela (não com a bolinha/janela flutuante). Brilho controlado por canal
  nativo (`fatigue_guard/screen`: Android `screenBrightness` da janela; iPhone `UIScreen.brightness`).
- **Modo de reforço (celular em ângulo ruim)**: se na calibração o EAR com olhos abertos e fechados
  ficar parecido (separação < 35%, ex.: celular muito abaixo do rosto), o app liga um reforço: a
  inclinação da cabeça fica mais sensível (75% do ângulo e 80% do tempo) e o olho fechado passa a ser
  medido pela probabilidade de olho aberto do ML Kit, quando ela separa bem aberto de fechado. A boca
  segue igual. O app também avisa quando o celular está muito abaixo, acima ou de lado do rosto.
  Pode ser ligado sempre em Configurações.
- Status em 3 níveis (NORMAL / ATENÇÃO / ALERTA DE SONOLÊNCIA) com **alerta progressivo**:
  tela cheia piscando, bipe e vibração; se continuar por 4 s, sirene rápida e vibração longa.
  Botão **"Estou acordado"** silencia por 10 s. O som toca no canal de alarme (Android) e
  mesmo no modo silencioso (iPhone). Tela sempre ligada durante o monitoramento.
- **Junto com o GPS — indicador flutuante** (Android): durante o monitoramento, ao apertar
  "início" (ou no botão "Usar junto com o GPS"), aparece uma **bolinha** arrastável por cima do
  outro app (Maps, Waze...): um ponto **verde / amarelo / vermelho** (pisca no alerta) e o ícone de
  **câmera** — riscado com **X** quando a detecção parou (sem câmera ou sem rosto). A câmera e o
  ML Kit passam para um serviço nativo em primeiro plano (`BubbleService.kt`, com notificação), que
  manda os pontos do rosto para o app; a lógica de sonolência é a mesma, e o alarme toca e vibra
  normalmente. Tocar na bolinha volta ao app. Precisa da permissão "Exibir sobre outros apps"; sem
  ela, o app usa a janela flutuante do Android (picture-in-picture, quadrada, ~108 dp). Também
  funciona com a tela dividida. No iPhone não é possível: o iOS não deixa a câmera funcionar com
  outro app em primeiro plano.
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
- Design claro: fundo verde bem claro (quase branco), cartões brancos e destaque verde;
  amarelo e vermelho só para ATENÇÃO e ALERTA. Fontes Barlow Condensed (títulos/números) e
  Manrope (texto). Ilustração e ícone com um olho minimalista em contorno.

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

A exportação gera **um único arquivo** (`FatigueGuard_relatorio_<data>.csv`) e abre o menu de
compartilhar do celular. Ele é organizado em seções, separadas por linhas em branco:

1. **Cabeçalho**: data de geração, número de sessões, tempo total monitorado e totais de alertas.
2. **Resumo das sessões**: uma linha por sessão (ordem cronológica, numeradas) e uma linha de **TOTAL**.
3. **Alertas e avisos**: cada evento com o número da sessão, data, horário, tempo decorrido na
   sessão, tipo por extenso ("ALERTA - cabeça caindo") e EAR/MAR/PERCLOS no momento.
4. **Como ler este arquivo**: legenda explicando cada coluna.

Padrão brasileiro: separador `;`, vírgula decimal, datas dd/mm/aaaa e horários hh:mm:ss. Abre
direto no Excel/Planilhas, pronto para tabelas e gráficos no capítulo de resultados do TCC.

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
  theme.dart                    paleta clara (verde quase branco) e tipografia
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
