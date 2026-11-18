// Basic per-IP limiter. In-memory => per serverless instance only; use Upstash/Redis before heavy traffic.
const hits = new Map<string, number[]>();
export function rateLimit(key: string, max = 5, windowMs = 10 * 60 * 1000) {
  const now = Date.now();
  const recent = (hits.get(key) || []).filter(t => now - t < windowMs);
  if (recent.length >= max) { hits.set(key, recent); return false; }
  recent.push(now); hits.set(key, recent);
  return true;
}
