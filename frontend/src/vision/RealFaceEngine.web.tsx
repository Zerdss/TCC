import React, { useEffect, useRef, useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import { calculateMetrics, LEFT_EYE, MOUTH_RING, PerclosWindow, Point, RIGHT_EYE } from "./metrics";

type Props = {
  stream: MediaStream | null;
  calibrationStep: number;
  earThreshold: number;
  onMetrics: (metrics: { ear: number; mar: number; perclos: number; closedFrames: number; landmarks: Point[] }) => void;
  onCalibrationProgress: (progress: number, baseline: number | null) => void;
  onFps: (fps: number) => void;
  onEngineState: (state: "loading" | "running" | "error") => void;
};

const SAMPLES_PER_STEP = 90;

export default function RealFaceEngine({ stream, calibrationStep, earThreshold, onMetrics, onCalibrationProgress, onFps, onEngineState }: Props) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const guideRef = useRef("");
  const taskRef = useRef<any>(null);
  const frameRef = useRef<number | null>(null);
  const lastVideoTime = useRef(-1);
  const lastInference = useRef(0);
  const frameCount = useRef(0);
  const fpsStart = useRef(0);
  const closedFrames = useRef(0);
  const perclos = useRef(new PerclosWindow(60000));
  const sampleStep = useRef(-1);
  const samples = useRef<number[]>([]);
  const [error, setError] = useState("");
  const [guide, setGuide] = useState({ text: "Iniciando câmera local...", good: false });
  const stepRef = useRef(calibrationStep);
  const thresholdRef = useRef(earThreshold);
  const handlersRef = useRef({ onMetrics, onCalibrationProgress, onFps, onEngineState });
  stepRef.current = calibrationStep;
  thresholdRef.current = earThreshold;
  handlersRef.current = { onMetrics, onCalibrationProgress, onFps, onEngineState };

  useEffect(() => {
    let disposed = false;
    const start = async () => {
      if (!stream || typeof window === "undefined") return;
      try {
        handlersRef.current.onEngineState("loading");
        const video = videoRef.current;
        if (!video) return;
        video.srcObject = stream;
        video.muted = true;
        video.playsInline = true;
        await video.play();
        // Metro parses the package's internal dynamic WASM import incorrectly on Expo Web.
        // Loading the pinned browser ESM bundle keeps inference client-side and avoids bundling video data.
        const loadVision = new Function("url", "return import(url)") as (url: string) => Promise<any>;
        const { FilesetResolver, FaceLandmarker } = await loadVision("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/vision_bundle.mjs");
        const vision = await FilesetResolver.forVisionTasks("https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm");
        taskRef.current = await FaceLandmarker.createFromOptions(vision, {
          baseOptions: { modelAssetPath: "/models/face_landmarker.task" },
          runningMode: "VIDEO", numFaces: 1, minFaceDetectionConfidence: 0.5,
          minFacePresenceConfidence: 0.5, minTrackingConfidence: 0.5,
          outputFaceBlendshapes: false, outputFacialTransformationMatrixes: false,
        });
        if (disposed) return;
        fpsStart.current = performance.now();
        handlersRef.current.onEngineState("running");
        frameRef.current = requestAnimationFrame(loop);
      } catch (cause: any) {
        if (!disposed) { setError(cause?.message || "Falha ao carregar o modelo facial."); handlersRef.current.onEngineState("error"); }
      }
    };
    const report = (text: string, good: boolean) => {
      if (guideRef.current === text) return;
      guideRef.current = text;
      setGuide({ text, good });
    };
    const paint = (points: Point[]) => {
      const video = videoRef.current;
      const canvas = canvasRef.current;
      if (!video || !canvas) return;
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      if (!width || !height) return;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) {
        canvas.width = Math.round(width * dpr);
        canvas.height = Math.round(height * dpr);
      }
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, height);
      const videoWidth = video.videoWidth || width;
      const videoHeight = video.videoHeight || height;
      const scale = Math.max(width / videoWidth, height / videoHeight);
      const offsetX = (width - videoWidth * scale) / 2;
      const offsetY = (height - videoHeight * scale) / 2;
      const toX = (n: number) => offsetX + n * videoWidth * scale;
      const toY = (n: number) => offsetY + n * videoHeight * scale;

      ctx.save();
      ctx.setLineDash([7, 7]);
      ctx.strokeStyle = "rgba(148,163,184,0.55)";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.ellipse(width / 2, height / 2, width * 0.21, height * 0.33, 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();

      if (!points.length) { report("Rosto não detectado — enquadre-se na câmera", false); return; }

      let minX = 1, maxX = 0, minY = 1, maxY = 0;
      ctx.fillStyle = "rgba(245,158,11,0.7)";
      for (let index = 0; index < points.length; index += 1) {
        const point = points[index];
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
        if (index % 4 === 0) ctx.fillRect(toX(point.x) - 1, toY(point.y) - 1, 2, 2);
      }
      ctx.strokeStyle = "#38BDF8";
      ctx.lineWidth = 2;
      [LEFT_EYE, RIGHT_EYE, MOUTH_RING].forEach(ring => {
        ctx.beginPath();
        ring.forEach((index, position) => {
          const point = points[index];
          if (!point) return;
          const x = toX(point.x);
          const y = toY(point.y);
          if (position === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        });
        ctx.closePath();
        ctx.stroke();
      });
      const faceWidth = maxX - minX;
      const centerX = (minX + maxX) / 2;
      const centerY = (minY + maxY) / 2;
      const centered = Math.abs(centerX - 0.5) <= 0.14 && Math.abs(centerY - 0.5) <= 0.16;
      const framed = faceWidth >= 0.16 && faceWidth <= 0.6 && centered;
      ctx.strokeStyle = framed ? "rgba(16,185,129,0.9)" : "rgba(245,158,11,0.9)";
      ctx.lineWidth = 1.5;
      ctx.strokeRect(toX(minX), toY(minY), toX(maxX) - toX(minX), toY(maxY) - toY(minY));
      if (faceWidth < 0.16) report("Aproxime-se da câmera", false);
      else if (faceWidth > 0.6) report("Afaste-se um pouco da câmera", false);
      else if (!centered) report("Centralize o rosto no quadro", false);
      else report("Posicionamento ideal", true);
    };
    const loop = (now: number) => {
      const video = videoRef.current;
      if (!video || !taskRef.current || video.readyState < 2) { frameRef.current = requestAnimationFrame(loop); return; }
      if (video.currentTime !== lastVideoTime.current && now - lastInference.current >= 33) {
        lastVideoTime.current = video.currentTime;
        lastInference.current = now;
        const result = taskRef.current.detectForVideo(video, Math.round(now));
        const points = (result.faceLandmarks?.[0] || []) as Point[];
        paint(points);
        const values = calculateMetrics(points);
        if (values) {
          if (sampleStep.current !== stepRef.current) { sampleStep.current = stepRef.current; samples.current = []; }
          if (samples.current.length < SAMPLES_PER_STEP) {
            samples.current.push(values.ear);
            const sorted = [...samples.current].sort((a, b) => a - b);
            handlersRef.current.onCalibrationProgress(Math.round((samples.current.length / SAMPLES_PER_STEP) * 100), sorted[Math.floor(sorted.length / 2)]);
          }
          if (values.ear < thresholdRef.current) closedFrames.current += 1; else closedFrames.current = 0;
          const perclosValue = perclos.current.add(now, values.ear, thresholdRef.current);
          handlersRef.current.onMetrics({ ear: values.ear, mar: values.mar, perclos: perclosValue, closedFrames: closedFrames.current, landmarks: points });
        }
        frameCount.current += 1;
        if (now - fpsStart.current >= 1000) { handlersRef.current.onFps(frameCount.current * 1000 / (now - fpsStart.current)); fpsStart.current = now; frameCount.current = 0; }
      }
      frameRef.current = requestAnimationFrame(loop);
    };
    start();
    return () => { disposed = true; if (frameRef.current) cancelAnimationFrame(frameRef.current); taskRef.current?.close?.(); taskRef.current = null; };
  }, [stream]);

  return <View style={styles.engine}>
    <video ref={videoRef} autoPlay muted playsInline style={styles.video as any} />
    <canvas ref={canvasRef} style={styles.canvas as any} />
    <View testID="framing-guide" style={[styles.guide, { borderColor: guide.good ? "#10B981" : "#F59E0B" }]}>
      <View style={[styles.guideDot, { backgroundColor: guide.good ? "#10B981" : "#F59E0B" }]} />
      <Text style={[styles.guideText, { color: guide.good ? "#10B981" : "#F59E0B" }]}>{guide.text}</Text>
    </View>
    {error ? <Text style={styles.error}>{error}</Text> : null}
  </View>;
}

const styles = StyleSheet.create({
  engine: { ...StyleSheet.absoluteFillObject, backgroundColor: "#090D14" },
  video: { width: "100%", height: "100%", objectFit: "cover", transform: "scaleX(-1)" } as any,
  canvas: { position: "absolute", top: 0, left: 0, width: "100%", height: "100%", transform: "scaleX(-1)" } as any,
  guide: { position: "absolute", top: 10, left: 10, right: 10, alignSelf: "center", maxWidth: "94%", flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 6, paddingHorizontal: 10, paddingVertical: 6, borderRadius: 20, borderWidth: 1, backgroundColor: "#090D14E6" },
  guideDot: { width: 7, height: 7, borderRadius: 7 },
  guideText: { fontSize: 11, fontWeight: "800", flexShrink: 1 },
  error: { position: "absolute", bottom: 8, left: 8, right: 8, color: "#FCA5A5", backgroundColor: "#090D14DD", padding: 8, fontSize: 11 },
});