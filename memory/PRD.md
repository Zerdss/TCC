# PRD — Detecção de Sonolência ao Volante

## Problema
Demo acadêmica em português para apresentar um protótipo de visão computacional que identifica sinais de sonolência ao volante usando câmera local, EAR, MAR e PERCLOS.

## Arquitetura
- Frontend Expo Router / React Native, com preview web priorizando webcam via `getUserMedia`.
- Processamento e fluxo preparados para execução local; nenhum frame é enviado ao backend.
- Backend FastAPI/Mongo permanece sem uso, pois o produto não requer conta, persistência ou API de vídeo.

## Personas
- Estudante apresentando TCC para banca.
- Visitante acadêmico explorando o conceito de segurança veicular.

## Requisitos principais
- Fluxo linear: início → calibração → demonstração → explicação.
- Aviso de privacidade visível, calibração guiada e telemetria EAR/MAR/PERCLOS.
- Status Normal/Atenção/Alerta e resposta visual, sonora/vibratória conforme plataforma.
- Visual técnico escuro, azul profundo e acentos de status.

## Implementado — 2026-08-27
- Tela inicial com identidade TCC, explicação, privacidade local e métricas.
- Calibração em três etapas com progresso e limiares pessoais conceituais.
- Painel ao vivo com webcam local no web preview, overlay visual de landmarks, gráficos, status e alertas.
- Seção explicativa com fórmulas e pipeline Captura → Detecção → Métricas → Classificação → Alerta.
- Permissões de câmera e vibração configuradas no app.json.

## Backlog priorizado
- P0: conectar FaceLandmarker real ao loop de frames e calcular EAR/MAR/PERCLOS a partir dos pontos detectados.
- P1: adicionar áudio de alerta nativo/web com controle de volume.
- P1: desenhar malha facial completa em Canvas/web e overlay nativo.
- P2: exportar um resumo da sessão para uso na apresentação.

## Próximas tarefas
1. Integrar o modelo FaceLandmarker local e validar thresholds com diferentes iluminações.
2. Testar câmera e vibração em Android/iOS reais.
3. Refinar acessibilidade e estados de erro da câmera.