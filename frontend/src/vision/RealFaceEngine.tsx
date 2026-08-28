import React from "react";
import { View } from "react-native";

type NativeProps = { stream: unknown; calibrationStep: number; earThreshold: number; marThreshold: number; marNeutralMax: number; onMetrics: (...args: any[]) => void; onFps: (...args: any[]) => void; onEngineState: (...args: any[]) => void; onCalibrationProgress: (...args: any[]) => void };
export default function RealFaceEngine(_props: NativeProps) { return <View />; }