import React, { useEffect, useRef, useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import { calculateMetrics, PerclosWindow, Point } from "./metrics";

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

  useEffect(() => {
    let disposed = false;
    const start = async () => {
      if (!stream || typeof window === "undefined") return;
      try {
        onEngineState("loading");
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
        onEngineState("running");
        frameRef.current = requestAnimationFrame(loop);
      } catch (cause: any) {
        if (!disposed) { setError(cause?.message || "Falha ao carregar o modelo facial."); onEngineState("error"); }
      }
    };
    const loop = (now: number) => {
      const video = videoRef.current;
      if (!video || !taskRef.current || video.readyState < 2) { frameRef.current = requestAnimationFrame(loop); return; }
      if (video.currentTime !== lastVideoTime.current && now - lastInference.current >= 33) {
        lastVideoTime.current = video.currentTime;
        lastInference.current = now;
        const result = taskRef.current.detectForVideo(video, Math.round(now));
        const points = (result.faceLandmarks?.[0] || []) as Point[];
        const values = calculateMetrics(points);
        if (values) {
          if (sampleStep.current !== calibrationStep) { sampleStep.current = calibrationStep; samples.current = []; }
          if (samples.current.length < SAMPLES_PER_STEP) {
            samples.current.push(values.ear);
            const sorted = [...samples.current].sort((a, b) => a - b);
            onCalibrationProgress(Math.round((samples.current.length / SAMPLES_PER_STEP) * 100), sorted[Math.floor(sorted.length / 2)]);
          }
          if (values.ear < earThreshold) closedFrames.current += 1; else closedFrames.current = 0;
          const perclosValue = perclos.current.add(now, values.ear, earThreshold);
          onMetrics({ ear: values.ear, mar: values.mar, perclos: perclosValue, closedFrames: closedFrames.current, landmarks: points });
        }
        frameCount.current += 1;
        if (now - fpsStart.current >= 1000) { onFps(frameCount.current * 1000 / (now - fpsStart.current)); fpsStart.current = now; frameCount.current = 0; }
      }
      frameRef.current = requestAnimationFrame(loop);
    };
    start();
    return () => { disposed = true; if (frameRef.current) cancelAnimationFrame(frameRef.current); taskRef.current?.close?.(); taskRef.current = null; };
  }, [stream]);

  return <View style={styles.engine}><video ref={videoRef} autoPlay muted playsInline style={styles.video as any} />{error ? <Text style={styles.error}>{error}</Text> : null}</View>;
}

const styles = StyleSheet.create({ engine: { ...StyleSheet.absoluteFillObject }, video: { width: "100%", height: "100%", objectFit: "cover", transform: "scaleX(-1)" } as any, error: { position: "absolute", bottom: 8, left: 8, right: 8, color: "#FCA5A5", backgroundColor: "#090D14DD", padding: 8, fontSize: 11 } });