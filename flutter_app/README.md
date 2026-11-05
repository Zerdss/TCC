# Fatigue Guard — app Flutter (TCC)

Versão nativa (Android/iOS) em **Flutter** da demo *Detecção de Sonolência ao Volante*.
Ela segue o mesmo fluxo e a mesma lógica do protótipo web em `../frontend`:

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

## Como rodar

Requisitos: Flutter 3.24+ (testado com 3.47), Android Studio/SDK (Android) ou Xcode (iOS).

```bash
cd flutter_app
```

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
  theme.dart                    paleta "Dark-First Utility" (design_guidelines.json)
  vision/
    metrics.dart                EAR, MAR, média móvel, PERCLOS
    fatigue_engine.dart         limiares, calibração, máquina de estados temporal
    vision_controller.dart      câmera + ML Kit → métricas → status/alertas
  widgets/
    camera_panel.dart           preview, malha facial, guia de enquadramento
    common.dart                 cabeçalho, botões, painéis
  screens/
    home_screen.dart  calibration_screen.dart  demo_screen.dart  explanation_screen.dart
test/                           testes unitários e de widget
```

## Diferenças em relação à versão web

| | Web (`frontend/`) | Flutter (`flutter_app/`) |
|---|---|---|
| Detector | MediaPipe FaceLandmarker (468 pontos) | ML Kit Face Detection (contornos, ~130 pontos) |
| EAR | 6 pontos por olho | 16 pontos por olho (3 pares verticais ÷ largura) |
| Suavização | 7 quadros | 5 quadros (ML Kit costuma rodar a 15–30 FPS no celular) |
| Amostras por etapa de calibração | 90 | 60 |

Como os pontos do ML Kit não são os mesmos do MediaPipe, os valores absolutos de EAR/MAR
podem ser um pouco diferentes; por isso a **calibração** é recomendada antes da demo.
Os parâmetros ficam no topo de `lib/vision/fatigue_engine.dart`.
