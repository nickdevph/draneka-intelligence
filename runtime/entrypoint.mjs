import { setTimeout as sleep } from 'node:timers/promises';
import { captureProducerSourceIdentity, resolvePinnedTankAnalysisSkill } from './pinned-skill.mjs';
import { runCodexCliTankAnalysis } from './codex-cli-executor.mjs';
import { JournalProducerIpcClient } from './journal-ipc-client.mjs';
import { GitHubArtifactStore } from './github-artifact-store.mjs';
import { executeEligibleWork } from './producer.mjs';
import { expireProducerScanDeferrals, producerScanExclusions, recordProducerScanOutcome } from './scan-policy.mjs';

const socketPath = process.env.JOURNAL_JI_PRODUCER_SOCKET_PATH;
if (process.env.NODE_ENV === 'production' || process.env.VERCEL_ENV === 'production' || process.env.JOURNAL_JI_NONPROD_PRODUCER_ENABLED !== 'true') {
  throw new Error('The local Codex CLI producer is qualification-only and refuses production activation.');
}
if (!socketPath) throw new Error('JOURNAL_JI_PRODUCER_SOCKET_PATH is required.');

const sourceIdentity = await captureProducerSourceIdentity();
const skill = await resolvePinnedTankAnalysisSkill();
const journal = new JournalProducerIpcClient(socketPath);
const artifactStore = new GitHubArtifactStore();
await artifactStore.verifyWriteAuthority();
const deferredUntil = new Map();
const excluded = new Set();
let stopping = false;

function stop() { stopping = true; }
process.once('SIGINT', stop);
process.once('SIGTERM', stop);

while (!stopping) {
  const now = Date.now();
  expireProducerScanDeferrals(deferredUntil, now);
  const excludeAttemptIds = producerScanExclusions(excluded, deferredUntil);
  let work;
  try {
    work = await journal.scan(excludeAttemptIds);
  } catch {
    await sleep(1500);
    continue;
  }
  if (!work) {
    await sleep(1500);
    continue;
  }
  try {
    const result = await executeEligibleWork({
      work,
      journal,
      artifactStore,
      executor: runCodexCliTankAnalysis,
      sourceIdentity,
      skillResolver: async () => skill,
    });
    recordProducerScanOutcome({ attemptId: work.attemptId, status: result.status, now, deferredUntil, excluded });
    process.stdout.write(JSON.stringify({ event: 'producer_attempt_complete', attemptId: work.attemptId, status: result.status }) + '\n');
  } catch {
    deferredUntil.set(work.attemptId, now + 5000);
    process.stdout.write(JSON.stringify({ event: 'producer_attempt_retryable_failure', attemptId: work.attemptId, code: 'PRODUCER_EXECUTION_FAILED' }) + '\n');
  }
}
