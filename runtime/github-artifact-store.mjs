import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { validateTankAnalysisResult } from './result-validator.mjs';
import { pinnedSkillLock } from './pinned-skill.mjs';
import { adapterContractForWork } from './adapter-contract.mjs';

export const ARTIFACT_REPOSITORY = 'nickdevph/aquaticfinder-intelligence-work';
export const ARTIFACT_BRANCH = 'main';
export const PRODUCER_IDENTITY = 'draneka_intelligence_nonprod';
export const ARTIFACT_NAMESPACE = 'journal-intelligence';
export const ARTIFACT_SCHEMA = 'af.intelligence-work-result.v1';
const MAX_ARTIFACT_BYTES = 100_000;

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function journalArtifactPath(work) {
  const requestId = String(work.analysisRequestId || '');
  const attemptId = String(work.attemptId || '');
  if (!/^[0-9a-f-]{36}$/i.test(requestId) || !/^[0-9a-f-]{36}$/i.test(attemptId)) throw new Error('Journal artifact identity is invalid.');
  return `journal-intelligence/results/${requestId}/${attemptId}.json`;
}

function gitBlobSha(bytes) {
  return createHash('sha1').update(Buffer.from(`blob ${bytes.length}\0`)).update(bytes).digest('hex');
}

function contentSha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function parseJson(raw, label) {
  try { return JSON.parse(raw); } catch { throw new Error(`${label} returned malformed JSON.`); }
}

function runGh(args, input, { cwd = process.cwd() } = {}) {
  const result = spawnSync('gh', ['api', ...args], {
    cwd,
    input,
    encoding: 'utf8',
    timeout: 30_000,
    maxBuffer: 2_000_000,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  if (result.error || result.status !== 0) throw new Error('Authorized GitHub API operation failed.');
  return result.stdout;
}

export function createGhApiRequest({ cwd = process.cwd() } = {}) {
  return async ({ method = 'GET', endpoint, body = null }) => {
    const args = [endpoint];
    if (method !== 'GET') args.push('--method', method);
    if (body !== null) args.push('--input', '-');
    return parseJson(runGh(args, body === null ? undefined : JSON.stringify(body), { cwd }), 'GitHub API');
  };
}

function expectedSource(work) {
  return {
    system: 'aquaticfinder-journal-ji',
    executionJobId: String(work.executionJobId),
    analysisRequestId: String(work.analysisRequestId),
    attemptId: String(work.attemptId),
    requestRevision: Number(work.requestRevision),
    processingCycle: Number(work.processingCycle),
    contextFingerprint: String(work.contextFingerprint),
  };
}

function assertArtifactBinding(artifact, work, { expectedResult = null } = {}) {
  const adapter = adapterContractForWork(work);
  if (!artifact || typeof artifact !== 'object' || Array.isArray(artifact) ||
      artifact.namespace !== ARTIFACT_NAMESPACE || artifact.schemaVersion !== ARTIFACT_SCHEMA ||
      artifact.producer !== adapter.producerIdentity || !['PASS', 'COMPLETED'].includes(artifact.disposition) ||
      artifact.taskId !== work.analysisRequestId || artifact.runId !== work.attemptId) {
    throw new Error('Existing GitHub artifact does not match the admitted producer identity.');
  }
  if (!Number.isFinite(Date.parse(artifact.createdAt || ''))) throw new Error('GitHub artifact creation timestamp is invalid.');
  for (const [key, value] of Object.entries(expectedSource(work))) {
    if (artifact.source?.[key] !== value) throw new Error(`GitHub artifact source binding mismatch: ${key}.`);
  }
  const provenance = artifact.executionProvenance;
  const expectedSkillFiles = Object.fromEntries(Object.entries(pinnedSkillLock.files).map(([name, sha256]) => [
    name.replace('skills/draneka-tank-analysis/', ''), sha256,
  ]));
  const expectedBinding = {
    analysisRequestId: work.analysisRequestId,
    executionJobId: work.executionJobId,
    attemptId: work.attemptId,
    requestRevision: work.requestRevision,
    processingCycle: work.processingCycle,
    contextFingerprint: work.contextFingerprint,
    providerAdmissionId: work.providerAdmissionId,
    adapterKey: work.adapterKey,
    adapterVersion: work.adapterVersion,
  };
  if (provenance?.producerIdentity !== adapter.producerIdentity ||
      provenance?.producerRuntime !== adapter.producerRuntime ||
      provenance?.artifactRepository !== ARTIFACT_REPOSITORY ||
      provenance?.artifactNamespace !== ARTIFACT_NAMESPACE ||
      provenance?.artifactSchema !== ARTIFACT_SCHEMA ||
      provenance?.producerSource?.repository !== 'nickdevph/draneka-intelligence' ||
      provenance?.producerSource?.commit !== work.producerSourceCommit ||
      provenance?.producerSource?.tree !== work.producerSourceTree ||
      provenance?.executor?.identity !== 'codex-cli' ||
      typeof provenance?.executor?.version !== 'string' || provenance.executor.version.length > 128 ||
      typeof provenance?.executor?.executionId !== 'string' || !/^[A-Za-z0-9._:-]{1,128}$/.test(provenance.executor.executionId) ||
      (adapter.authoritativeExecutionId && provenance.executor.executionId !== work.executorExecutionId) ||
      provenance?.skill?.name !== pinnedSkillLock.name ||
      provenance?.skill?.version !== pinnedSkillLock.version ||
      provenance?.skill?.sourceRepository !== pinnedSkillLock.repository ||
      provenance?.skill?.sourceCommit !== pinnedSkillLock.sourceCommit ||
      provenance?.skill?.schemaVersion !== pinnedSkillLock.schemaVersion ||
      stableJson(provenance?.skill?.sourceFileSha256) !== stableJson(expectedSkillFiles) ||
      stableJson(provenance?.executionBinding) !== stableJson(expectedBinding)) {
    throw new Error('GitHub artifact execution provenance is not admitted.');
  }
  const result = artifact.metadata?.result;
  if (!result || typeof result !== 'object' || Array.isArray(result)) throw new Error('GitHub artifact result is missing.');
  const validation = validateTankAnalysisResult(result, {
    expectedAnalysisRequestId: work.analysisRequestId,
    expectedQuestion: work.question,
    allowExternalResearch: false,
  });
  if (!validation.valid) throw new Error('GitHub artifact Tank Analysis result is invalid.');
  if (expectedResult && stableJson(expectedResult) !== stableJson(result)) throw new Error('GitHub artifact content differs from the create-only result.');
  return result;
}

export class GitHubArtifactStore {
  constructor({ request = createGhApiRequest(), repository = ARTIFACT_REPOSITORY, branch = ARTIFACT_BRANCH } = {}) {
    this.request = request;
    this.repository = repository;
    this.branch = branch;
  }

  async verifyWriteAuthority() {
    const viewer = await this.request({ endpoint: 'user' });
    if (viewer?.login !== 'nickdevph') throw new Error('Existing GitHub authentication is not bound to the authorized owner.');
    const repository = await this.request({ endpoint: `repos/${this.repository}` });
    if (repository?.private !== true || repository?.default_branch !== this.branch || repository?.permissions?.push !== true) {
      throw new Error('Authorized private GitHub artifact write access is unavailable.');
    }
    return { identity: viewer.login, repository: this.repository, branch: this.branch, private: true, push: true };
  }

  async history(path) {
    const endpoint = `repos/${this.repository}/commits?path=${encodeURIComponent(path)}&per_page=2`;
    const commits = await this.request({ endpoint });
    if (!Array.isArray(commits)) throw new Error('GitHub artifact path history is malformed.');
    if (commits.length > 1) throw new Error('GitHub artifact path is not append-only.');
    return commits;
  }

  async readAtCommit(path, commitSha) {
    if (!/^[0-9a-f]{40}$/i.test(commitSha)) throw new Error('GitHub artifact commit identity is invalid.');
    const encodedPath = path.split('/').map(encodeURIComponent).join('/');
    const contents = await this.request({ endpoint: `repos/${this.repository}/contents/${encodedPath}?ref=${encodeURIComponent(commitSha)}` });
    if (contents?.type !== 'file' || contents.path !== path || contents.encoding !== 'base64' ||
        typeof contents.sha !== 'string' || !/^[0-9a-f]{40}$/i.test(contents.sha)) {
      throw new Error('GitHub Contents API did not return an exact file identity.');
    }
    const bytes = Buffer.from(String(contents.content || '').replace(/\s/g, ''), 'base64');
    if (bytes.length === 0 || bytes.length > MAX_ARTIFACT_BYTES || Number(contents.size) !== bytes.length || gitBlobSha(bytes) !== contents.sha.toLowerCase()) {
      throw new Error('GitHub Contents blob identity does not match its bytes.');
    }
    const blob = await this.request({ endpoint: `repos/${this.repository}/git/blobs/${contents.sha}` });
    if (blob?.sha !== contents.sha || blob.encoding !== 'base64') throw new Error('GitHub Git Blob identity mismatch.');
    const blobBytes = Buffer.from(String(blob.content || '').replace(/\s/g, ''), 'base64');
    if (!blobBytes.equals(bytes) || gitBlobSha(blobBytes) !== contents.sha.toLowerCase()) throw new Error('GitHub Git Blob content mismatch.');
    let artifact;
    try { artifact = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); } catch { throw new Error('GitHub artifact is not valid UTF-8 JSON.'); }
    return { artifact, commitSha: commitSha.toLowerCase(), path, blobSha: contents.sha.toLowerCase(), contentSha256: contentSha256(bytes), bytes };
  }

  async findExisting(work) {
    const path = journalArtifactPath(work);
    const commits = await this.history(path);
    if (commits.length === 0) return null;
    const commitSha = String(commits[0]?.sha || '').toLowerCase();
    const loaded = await this.readAtCommit(path, commitSha);
    assertArtifactBinding(loaded.artifact, work);
    return { ...loaded, result: loaded.artifact.metadata.result, created: false };
  }

  async createOnly({ work, result, executionProvenance, createdAt = new Date().toISOString() }) {
    const adapter = adapterContractForWork(work);
    const path = journalArtifactPath(work);
    const prior = await this.findExisting(work);
    if (prior) return prior;
    const artifact = {
      namespace: ARTIFACT_NAMESPACE,
      schemaVersion: ARTIFACT_SCHEMA,
      producer: adapter.producerIdentity,
      disposition: 'PASS',
      createdAt,
      taskId: work.analysisRequestId,
      runId: work.attemptId,
      source: expectedSource(work),
      executionProvenance,
      metadata: { result },
    };
    const bytes = Buffer.from(`${JSON.stringify(artifact, null, 2)}\n`, 'utf8');
    if (bytes.length > MAX_ARTIFACT_BYTES) throw new Error('GitHub artifact exceeds the admitted byte limit.');
    const body = {
      message: `Add bounded Tank Analysis result for ${work.analysisRequestId}`,
      content: bytes.toString('base64'),
      branch: this.branch,
    };
    try {
      await this.request({ method: 'PUT', endpoint: `repos/${this.repository}/contents/${path}`, body });
    } catch {
      // A simultaneous CREATE_ONLY write may win. Re-read and verify that
      // immutable artifact rather than ever sending an update SHA.
      const raced = await this.findExisting(work);
      if (raced) return raced;
      throw new Error('CREATE_ONLY GitHub artifact write failed.');
    }
    const commits = await this.history(path);
    if (commits.length !== 1) throw new Error('New GitHub artifact path does not have exactly one creation commit.');
    const commitSha = String(commits[0]?.sha || '').toLowerCase();
    const loaded = await this.readAtCommit(path, commitSha);
    const storedResult = assertArtifactBinding(loaded.artifact, work, { expectedResult: result });
    return { ...loaded, result: storedResult, created: true };
  }
}

export { assertArtifactBinding, contentSha256, gitBlobSha };
