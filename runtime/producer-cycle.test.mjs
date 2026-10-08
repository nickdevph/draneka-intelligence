import assert from 'node:assert/strict';
import test from 'node:test';
import { isSuccessfulOneShotStatus, runProducerCycle } from './producer-cycle.mjs';

test('one-shot scheduler success is limited to no-work or a verified immutable artifact', () => {
  assert.equal(isSuccessfulOneShotStatus('NO_ELIGIBLE_WORK'), true);
  assert.equal(isSuccessfulOneShotStatus('ARTIFACT_CREATED'), true);
  assert.equal(isSuccessfulOneShotStatus('EXISTING_ARTIFACT_VERIFIED'), true);
  for (const status of ['INVALID_STRUCTURED_RESULT', 'ADMISSION_SOURCE_MISMATCH', 'PINNED_SKILL_MISMATCH', 'STALE_AFTER_EXECUTION', 'DUPLICATE_SCAN_SKIPPED', 'PRODUCER_EXECUTION_FAILED']) {
    assert.equal(isSuccessfulOneShotStatus(status), false, `${status} must report a failed one-shot invocation`);
  }
});

function dependencies({ work = null, scanError = null, executeError = null } = {}) {
  let scanCount = 0;
  let executeCount = 0;
  const deferredUntil = new Map();
  const excluded = new Set();
  const journal = {
    async scan() {
      scanCount += 1;
      if (scanError) throw scanError;
      return work;
    },
  };
  const executeWork = async () => {
    executeCount += 1;
    if (executeError) throw executeError;
    return { status: 'ARTIFACT_CREATED' };
  };
  return { journal, deferredUntil, excluded, executeWork, counts: () => ({ scanCount, executeCount }) };
}

test('one producer cycle scans once and exits when no eligible work exists', async () => {
  const state = dependencies();
  const result = await runProducerCycle({ ...state, now: 1000 });
  assert.deepEqual(result, { status: 'NO_ELIGIBLE_WORK' });
  assert.deepEqual(state.counts(), { scanCount: 1, executeCount: 0 });
});

test('one producer cycle executes at most the one returned attempt', async () => {
  const state = dependencies({ work: { attemptId: 'attempt-one' } });
  const result = await runProducerCycle({ ...state, now: 1000 });
  assert.deepEqual(result, { status: 'ARTIFACT_CREATED', attemptId: 'attempt-one' });
  assert.deepEqual(state.counts(), { scanCount: 1, executeCount: 1 });
  assert.deepEqual([...state.excluded], ['attempt-one']);
});

test('one producer cycle reports retryable scan and execution failures without looping', async () => {
  const scan = dependencies({ scanError: new Error('private detail') });
  assert.deepEqual(await runProducerCycle({ ...scan, now: 1000 }), { status: 'SCAN_RETRYABLE_FAILURE' });
  assert.deepEqual(scan.counts(), { scanCount: 1, executeCount: 0 });

  const execute = dependencies({ work: { attemptId: 'attempt-two' }, executeError: new Error('private detail') });
  assert.deepEqual(await runProducerCycle({ ...execute, now: 1000 }), {
    status: 'PRODUCER_EXECUTION_FAILED', attemptId: 'attempt-two',
  });
  assert.deepEqual(execute.counts(), { scanCount: 1, executeCount: 1 });
  assert.equal(execute.deferredUntil.get('attempt-two'), 6000);
});

test('scheduled Codex cycle performs one authoritative claim and does not fall back to scan', async () => {
  let claimCount = 0;
  let scanCount = 0;
  const journal = {
    async claim() { claimCount += 1; return null; },
    async scan() { scanCount += 1; throw new Error('global scan must not be used'); },
  };
  const result = await runProducerCycle({
    journal,
    artifactStore: {},
    executor: async () => { throw new Error('no work should reach executor'); },
    sourceIdentity: {},
    skillResolver: async () => ({}),
    deferredUntil: new Map(),
    excluded: new Set(),
    now: 1000,
  });
  assert.deepEqual(result, { status: 'NO_ELIGIBLE_WORK' });
  assert.equal(claimCount, 1);
  assert.equal(scanCount, 0);
});
