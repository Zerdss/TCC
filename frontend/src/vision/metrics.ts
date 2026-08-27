export type Point = { x: number; y: number; z?: number };

export const LEFT_EYE = [33, 160, 158, 133, 153, 144];
export const RIGHT_EYE = [362, 385, 387, 263, 373, 380];
export const MOUTH_RING = [61, 39, 0, 269, 291, 405, 17, 181];
const MOUTH_LEFT = 61;
const MOUTH_RIGHT = 291;
const MOUTH_TOP = 13;
const MOUTH_BOTTOM = 14;

const distance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y, (a.z || 0) - (b.z || 0));

const singleEar = (points: Point[], indices: number[]) => {
  const [p1, p2, p3, p4, p5, p6] = indices.map(index => points[index]);
  return (distance(p2, p6) + distance(p3, p5)) / Math.max(2 * distance(p1, p4), 0.000001);
};

export function calculateMetrics(points: Point[]) {
  if (points.length < 468) return null;
  const leftEAR = singleEar(points, LEFT_EYE);
  const rightEAR = singleEar(points, RIGHT_EYE);
  const ear = (leftEAR + rightEAR) / 2;
  const mar = distance(points[MOUTH_TOP], points[MOUTH_BOTTOM]) / Math.max(distance(points[MOUTH_LEFT], points[MOUTH_RIGHT]), 0.000001);
  return { ear, mar, leftEAR, rightEAR };
}

export class PerclosWindow {
  private samples: Array<{ time: number; closed: boolean }> = [];
  constructor(private readonly windowMs = 60000) {}
  add(time: number, ear: number, threshold: number) {
    this.samples.push({ time, closed: ear < threshold });
    const cutoff = time - this.windowMs;
    while (this.samples.length && this.samples[0].time < cutoff) this.samples.shift();
    if (this.samples.length < 2) return 0;
    let closedMs = 0;
    for (let index = 0; index < this.samples.length - 1; index += 1) {
      if (this.samples[index].closed) closedMs += this.samples[index + 1].time - this.samples[index].time;
    }
    return closedMs / Math.max(time - this.samples[0].time, 1);
  }
  reset() { this.samples = []; }
}