import { executeEligibleWork } from './producer.mjs';
import { expireProducerScanDeferrals, producerScanExclusions, recordProducerScanOutcome } from './scan-policy.mjs';

const ONE_SHOT_SUCCESS_STATUSES = new Set(['NO_ELIGIBLE_WORK', 'ARTIFACT_CREATED', 'EXISTING_ARTIFACT_VERIFIED']);

export function isSuccessfulOneShotStatus(status) {
  return ONE_SHOT_SUCCESS_STATUSES.has(status);
}

export async function runProducerCycle({
  journal,
  artifactStore,
  executor,
  sourceIdentity,
  skillResolver,
  deferredUntil,
  excluded,
  now = Date.now(),
  executeWork = executeEligibleWork,
}) {
  expireProducerScanDeferrals(deferredUntil, now);
  const excludeAttemptIds = producerScanExclusions(excluded, deferredUntil);
  let work;
  try {
    work = typeof journal.claim === 'function'
      ? await journal.claim()
      : await journal.scan(excludeAttemptIds);
  } catch {
    return { status: 'SCAN_RETRYABLE_FAILURE' };
  }
  if (!work) return { status: 'NO_ELIGIBLE_WORK' };

  try {
    const result = await executeWork({
      work,
      journal,
      artifactStore,
      executor,
      sourceIdentity,
      skillResolver,
    });
    recordProducerScanOutcome({ attemptId: work.attemptId, status: result.status, now, deferredUntil, excluded });
    return { status: result.status, attemptId: work.attemptId };
  } catch {
    deferredUntil.set(work.attemptId, now + 5000);
    return { status: 'PRODUCER_EXECUTION_FAILED', attemptId: work.attemptId };
  }
}
