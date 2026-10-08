import assert from 'node:assert/strict';
import test from 'node:test';
import { JournalCodexClaimClient, journalCodexClaimPaths } from './journal-codex-claim-client.mjs';

const token = 'qualification-only-secret-value-with-at-least-32-chars';

test('Codex client uses only the dedicated Journal claim and currentness endpoints', async () => {
  const calls = [];
  const client = new JournalCodexClaimClient({
    env: {
      NODE_ENV: 'test',
      JOURNAL_JI_CODEX_CLI_ADAPTER_ENABLED: 'true',
      JOURNAL_JI_CODEX_CLI_SERVICE_TOKEN: token,
      JOURNAL_JI_CODEX_CLI_JOURNAL_ORIGIN: 'http://127.0.0.1:8787',
      JOURNAL_JI_CODEX_CLI_ALLOW_LOOPBACK: 'true',
    },
    fetchImpl: async (url, options) => {
      calls.push({ url: String(url), options });
      if (String(url).endsWith(journalCodexClaimPaths.reconcile)) {
        return {
          status: 200,
          text: async () => JSON.stringify({ accepted: true, resultId: 'result-id', analysisRequestId: 'request-id', attemptId: 'attempt-id' }),
        };
      }
      return { status: 204, text: async () => '' };
    },
  });
  assert.equal(await client.claim(), null);
  assert.equal(calls[0].url, `http://127.0.0.1:8787${journalCodexClaimPaths.claim}`);
  assert.deepEqual(JSON.parse(calls[0].options.body), {});
  assert.equal(calls[0].options.headers.authorization, `Bearer ${token}`);
  assert.equal(await client.current('attempt-id', 'claim-token'), null);
  assert.equal(calls[1].url, `http://127.0.0.1:8787${journalCodexClaimPaths.current}`);
  assert.deepEqual(JSON.parse(calls[1].options.body), { attemptId: 'attempt-id', claimToken: 'claim-token' });
  assert.equal(calls[1].options.redirect, 'error');
  const accepted = await client.reconcile('attempt-id', 'claim-token');
  assert.equal(accepted.resultId, 'result-id');
  assert.equal(calls[2].url, `http://127.0.0.1:8787${journalCodexClaimPaths.reconcile}`);
  assert.deepEqual(JSON.parse(calls[2].options.body), { attemptId: 'attempt-id', claimToken: 'claim-token' });
});

test('producer-cycle scan maps to exactly one unselected authoritative claim', async () => {
  const calls = [];
  const client = new JournalCodexClaimClient({
    env: {
      JOURNAL_JI_CODEX_CLI_ADAPTER_ENABLED: 'true',
      JOURNAL_JI_CODEX_CLI_SERVICE_TOKEN: 'a'.repeat(48),
      JOURNAL_JI_CODEX_CLI_JOURNAL_ORIGIN: 'http://127.0.0.1:8787',
      JOURNAL_JI_CODEX_CLI_ALLOW_LOOPBACK: 'true',
      NODE_ENV: 'test',
    },
    fetchImpl: async (url, options) => {
      calls.push({ url: String(url), options });
      return { status: 204, text: async () => '' };
    },
  });
  assert.equal(await client.scan([]), null);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `http://127.0.0.1:8787${journalCodexClaimPaths.claim}`);
  assert.equal(calls[0].options.body, '{}');
  await assert.rejects(client.scan(['attempt-id']), /do not accept selectors or scan exclusions/);
  assert.equal(calls.length, 1);
});

test('Codex client rejects production origins outside aquaticfinder.com and any selectors', () => {
  assert.throws(() => new JournalCodexClaimClient({
    env: {
      NODE_ENV: 'production',
      JOURNAL_JI_CODEX_CLI_ADAPTER_ENABLED: 'true',
      JOURNAL_JI_CODEX_CLI_SERVICE_TOKEN: token,
      JOURNAL_JI_CODEX_CLI_JOURNAL_ORIGIN: 'https://example.com',
    },
  }), /unapproved Journal origin/);
  assert.throws(() => new JournalCodexClaimClient({
    env: { NODE_ENV: 'test', JOURNAL_JI_CODEX_CLI_SERVICE_TOKEN: token, JOURNAL_JI_CODEX_CLI_JOURNAL_ORIGIN: 'http://127.0.0.1:8787' },
  }), /not enabled/);
});
