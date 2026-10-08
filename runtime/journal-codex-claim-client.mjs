const PROD_ORIGIN = 'https://aquaticfinder.com';
const CLAIM_PATH = '/api/journal/internal/ji/codex-cli/work/claim';
const CURRENT_PATH = '/api/journal/internal/ji/codex-cli/work/current';
const MAX_RESPONSE_BYTES = 150_000;

function resolveOrigin(env) {
  const raw = String(env.JOURNAL_JI_CODEX_CLI_JOURNAL_ORIGIN || '');
  let origin;
  try { origin = new URL(raw); } catch { throw new Error('A Journal origin is required for the Codex claim adapter.'); }
  if (origin.username || origin.password || origin.search || origin.hash || origin.pathname !== '/') {
    throw new Error('The configured Journal origin is malformed.');
  }
  const production = String(env.NODE_ENV || '').toLowerCase() === 'production' || String(env.VERCEL_ENV || '').toLowerCase() === 'production';
  const testLoopback = !production && env.JOURNAL_JI_CODEX_CLI_ALLOW_LOOPBACK === 'true' &&
    ['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname);
  if ((production && origin.origin !== PROD_ORIGIN) || (!production && !testLoopback && origin.protocol !== 'https:')) {
    throw new Error('The Codex claim adapter refused an unapproved Journal origin.');
  }
  return origin.origin;
}

export class JournalCodexClaimClient {
  constructor({ env = process.env, fetchImpl = globalThis.fetch, timeoutMs = 8000 } = {}) {
    if (env.JOURNAL_JI_CODEX_CLI_ADAPTER_ENABLED !== 'true') throw new Error('The Journal Codex CLI adapter is not enabled.');
    const token = String(env.JOURNAL_JI_CODEX_CLI_SERVICE_TOKEN || '');
    if (!token || token.length < 32 || /\s/.test(token)) throw new Error('The dedicated Journal Codex CLI service credential is unavailable.');
    if (typeof fetchImpl !== 'function') throw new Error('The Journal Codex claim transport is unavailable.');
    this.origin = resolveOrigin(env);
    this.token = token;
    this.fetchImpl = fetchImpl;
    this.timeoutMs = timeoutMs;
  }

  async request(path, body) {
    let response;
    try {
      response = await this.fetchImpl(new URL(path, this.origin), {
        method: 'POST',
        redirect: 'error',
        headers: {
          authorization: `Bearer ${this.token}`,
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body: JSON.stringify(body),
        ...(typeof globalThis.AbortSignal?.timeout === 'function' ? { signal: globalThis.AbortSignal.timeout(this.timeoutMs) } : {}),
      });
    } catch {
      throw new Error('Journal Codex claim request failed.');
    }
    if (response.status === 204) return { status: 204, data: null };
    let raw;
    try { raw = await response.text(); } catch { throw new Error('Journal Codex response could not be read.'); }
    if (Buffer.byteLength(raw, 'utf8') > MAX_RESPONSE_BYTES) throw new Error('Journal Codex response exceeded its bounded limit.');
    let data;
    try { data = JSON.parse(raw); } catch { throw new Error('Journal Codex response was malformed.'); }
    return { status: response.status, data };
  }

  async claim() {
    const response = await this.request(CLAIM_PATH, {});
    if (response.status === 204) return null;
    if (response.status !== 200 || !response.data?.work || typeof response.data.work !== 'object') {
      throw new Error(`Journal Codex claim failed (${response.status}).`);
    }
    return response.data.work;
  }

  async current(attemptId, claimToken) {
    const response = await this.request(CURRENT_PATH, { attemptId, claimToken });
    if (response.status === 204 || response.status === 404 || response.status === 409) return null;
    if (response.status !== 200 || !response.data?.work || typeof response.data.work !== 'object') {
      throw new Error(`Journal Codex currentness check failed (${response.status}).`);
    }
    return response.data.work;
  }
}

export const journalCodexClaimPaths = Object.freeze({ claim: CLAIM_PATH, current: CURRENT_PATH });
