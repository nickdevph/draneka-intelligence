import { setTimeout as sleep } from 'node:timers/promises';
import { captureProducerSourceIdentity, resolvePinnedTankAnalysisSkill } from './pinned-skill.mjs';
import { runCodexCliTankAnalysis } from './codex-cli-executor.mjs';
import { JournalProducerIpcClient } from './journal-ipc-client.mjs';
import { GitHubArtifactStore } from './github-artifact-store.mjs';
import { runProducerCycle } from './producer-cycle.mjs';

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
const once = process.argv.slice(2).includes('--once');
let stopping = false;

function stop() { stopping = true; }
process.once('SIGINT', stop);
process.once('SIGTERM', stop);

while (!stopping) {
  const now = Date.now();
  const outcome = await runProducerCycle({
    journal,
    artifactStore,
    executor: runCodexCliTankAnalysis,
    sourceIdentity,
    skillResolver: async () => skill,
    deferredUntil,
    excluded,
    now,
  });
  if (outcome.status === 'NO_ELIGIBLE_WORK') {
    if (once) {
      process.stdout.write(JSON.stringify({ event: 'producer_no_eligible_work' }) + '\n');
      break;
    }
    await sleep(1500);
    continue;
  }
  if (outcome.status === 'SCAN_RETRYABLE_FAILURE') {
    if (once) {
      process.stdout.write(JSON.stringify({ event: 'producer_scan_retryable_failure', code: 'PRODUCER_SCAN_FAILED' }) + '\n');
      process.exitCode = 1;
      break;
    }
    await sleep(1500);
    continue;
  }
  if (outcome.status === 'PRODUCER_EXECUTION_FAILED') {
    process.stdout.write(JSON.stringify({ event: 'producer_attempt_retryable_failure', attemptId: outcome.attemptId, code: 'PRODUCER_EXECUTION_FAILED' }) + '\n');
    if (once) {
      process.exitCode = 1;
      break;
    }
    continue;
  }
  process.stdout.write(JSON.stringify({ event: 'producer_attempt_complete', attemptId: outcome.attemptId, status: outcome.status }) + '\n');
  if (once) break;
}
