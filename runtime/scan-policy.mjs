const TERMINAL_SCAN_STATUSES = new Set([
  'ARTIFACT_CREATED',
  'EXISTING_ARTIFACT_VERIFIED',
  'STALE_BEFORE_EXECUTION',
  'STALE_AFTER_EXECUTION',
  'ADMISSION_SOURCE_MISMATCH',
  'PINNED_SKILL_MISMATCH',
]);

const DUPLICATE_SCAN_RETRY_DELAY_MS = 5_000;

export function expireProducerScanDeferrals(deferredUntil, now) {
  for (const [attemptId, until] of deferredUntil) {
    if (until <= now) deferredUntil.delete(attemptId);
  }
}

export function producerScanExclusions(excluded, deferredUntil) {
  return [...new Set([...excluded, ...deferredUntil.keys()])].slice(-100);
}

export function recordProducerScanOutcome({ attemptId, status, now, deferredUntil, excluded }) {
  if (TERMINAL_SCAN_STATUSES.has(status)) {
    deferredUntil.delete(attemptId);
    excluded.add(attemptId);
    return 'EXCLUDED';
  }

  if (status === 'DUPLICATE_SCAN_SKIPPED') {
    deferredUntil.set(attemptId, now + DUPLICATE_SCAN_RETRY_DELAY_MS);
    return 'DEFERRED';
  }

  const previousRetryAt = deferredUntil.get(attemptId);
  const previousDelay = previousRetryAt === undefined ? 2_000 : previousRetryAt - now;
  const nextDelay = Math.min(60_000, Math.max(2_000, previousDelay) * 2);
  deferredUntil.set(attemptId, now + nextDelay);
  return 'DEFERRED';
}
