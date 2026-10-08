import assert from 'node:assert/strict';
import test from 'node:test';
import { runProducerCycle } from './producer-cycle.mjs';

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
