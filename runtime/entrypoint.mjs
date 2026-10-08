import { setTimeout as sleep } from 'node:timers/promises';
import { captureProducerSourceIdentity, resolvePinnedTankAnalysisSkill } from './pinned-skill.mjs';
import { runCodexCliTankAnalysis } from './codex-cli-executor.mjs';
import { JournalProducerIpcClient } from './journal-ipc-client.mjs';
import { JournalCodexClaimClient } from './journal-codex-claim-client.mjs';
import { GitHubArtifactStore } from './github-artifact-store.mjs';
import { isSuccessfulOneShotStatus, runProducerCycle } from './producer-cycle.mjs';

const socketPath = process.env.JOURNAL_JI_PRODUCER_SOCKET_PATH;
const nonprodMode = process.env.JOURNAL_JI_NONPROD_PRODUCER_ENABLED === 'true';
const codexCliMode = process.env.JOURNAL_JI_CODEX_CLI_ADAPTER_ENABLED === 'true';
const productionEnvironment = process.env.NODE_ENV === 'production' || process.env.VERCEL_ENV === 'production';
const once = process.argv.slice(2).includes('--once');
if (nonprodMode === codexCliMode) throw new Error('Enable exactly one Journal Intelligence producer adapter mode.');
if (productionEnvironment && !codexCliMode) throw new Error('The qualification-only producer refuses production activation.');
if (codexCliMode && !once) throw new Error('The Codex CLI scheduled adapter requires one-shot execution with --once.');
if (nonprodMode && !socketPath) throw new Error('JOURNAL_JI_PRODUCER_SOCKET_PATH is required.');

const sourceIdentity = await captureProducerSourceIdentity();
const skill = await resolvePinnedTankAnalysisSkill();
const journal = codexCliMode
  ? new JournalCodexClaimClient()
  : new JournalProducerIpcClient(socketPath);
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
  if (once && !isSuccessfulOneShotStatus(outcome.status)) {
    process.stdout.write(JSON.stringify({ event: 'producer_attempt_failed', attemptId: outcome.attemptId, code: outcome.status }) + '\n');
    process.exitCode = 1;
    break;
  }
  process.stdout.write(JSON.stringify({ event: 'producer_attempt_complete', attemptId: outcome.attemptId, status: outcome.status }) + '\n');
  if (once) break;
}
