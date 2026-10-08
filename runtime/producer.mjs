import { validateTankAnalysisResult } from './result-validator.mjs';
import { pinnedSkillLock } from './pinned-skill.mjs';
import { acquireAttemptLock } from './attempt-lock.mjs';
import { ARTIFACT_REPOSITORY, ARTIFACT_SCHEMA, ARTIFACT_NAMESPACE, journalArtifactPath } from './github-artifact-store.mjs';
import { adapterContractForWork, NONPROD_CODEX_ADAPTER } from './adapter-contract.mjs';

export const PRODUCER_ADAPTER_KEY = NONPROD_CODEX_ADAPTER.key;
export const PRODUCER_ADAPTER_VERSION = NONPROD_CODEX_ADAPTER.version;
export const MAX_BOUNDED_CONTEXT_BYTES = 60_000;

const IDENTITY_KEY = /^(?:accountId|ownerUserId|userId|tankId|analysisRequestId|executionJobId|attemptId|account_id|owner_user_id|user_id|tank_id|analysis_request_id|execution_job_id|attempt_id)$/i;
const SECRET_KEY = /password|secret|credential|token|authorization/i;
const EXECUTOR_PROVENANCE_KEYS = ['executionId', 'identity', 'model', 'version'];

function validateExecutorProvenance(executor) {
  if (!isPlainObject(executor) ||
      JSON.stringify(Object.keys(executor).sort()) !== JSON.stringify(EXECUTOR_PROVENANCE_KEYS) ||
      executor.identity !== 'codex-cli' ||
      typeof executor.version !== 'string' || executor.version.length > 128 ||
      !/^codex-cli \d+\.\d+\.\d+$/.test(executor.version) ||
      !(executor.model === null || (typeof executor.model === 'string' && executor.model.length > 0 && executor.model.length <= 128 && !/[\u0000-\u001f\u007f]/.test(executor.model))) ||
      typeof executor.executionId !== 'string' || !/^[A-Za-z0-9._:-]{1,128}$/.test(executor.executionId)) {
    throw new Error('Codex CLI executor provenance is missing or invalid.');
  }
  return executor;
}

function isPlainObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function redactBoundedContext(value, depth = 0) {
  if (depth > 12) throw new Error('Journal context exceeds the admitted nesting bound.');
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Journal context includes a non-finite number.');
    return value;
  }
  if (Array.isArray(value)) {
    if (value.length > 1000) throw new Error('Journal context exceeds the admitted item limit.');
    return value.map((item) => redactBoundedContext(item, depth + 1));
  }
  if (!isPlainObject(value)) throw new Error('Journal context is not plain JSON data.');
  const entries = Object.entries(value).filter(([key]) => !IDENTITY_KEY.test(key));
  if (entries.some(([key]) => SECRET_KEY.test(key))) throw new Error('Journal context includes a secret-bearing field.');
  return Object.fromEntries(entries.map(([key, child]) => [key, redactBoundedContext(child, depth + 1)]));
}

export function validateWorkIdentity(work, expectedAdapter = NONPROD_CODEX_ADAPTER) {
  if (!isPlainObject(work)) throw new Error('Eligible Journal work is malformed.');
  for (const field of ['analysisRequestId', 'executionJobId', 'attemptId', 'accountId', 'tankId', 'contextFingerprint', 'providerAdmissionId']) {
    if (typeof work[field] !== 'string' || !work[field].trim()) throw new Error(`Eligible Journal work is missing ${field}.`);
  }
  for (const field of ['analysisRequestId', 'executionJobId', 'attemptId', 'accountId', 'tankId', 'providerAdmissionId']) {
    if (!/^[0-9a-f-]{36}$/i.test(work[field])) throw new Error(`Eligible Journal work has an invalid ${field}.`);
  }
  if (!/^[0-9a-f]{64}$/i.test(work.contextFingerprint) ||
      !Number.isSafeInteger(work.requestRevision) || work.requestRevision < 1 ||
      !Number.isSafeInteger(work.processingCycle) || work.processingCycle < 1 ||
      work.attemptState !== expectedAdapter.attemptState || work.jobState !== expectedAdapter.jobState || work.requestState !== 'PROCESSING' ||
      work.analysisType !== 'TANK_ANALYSIS' || work.adapterKey !== expectedAdapter.key ||
      work.adapterVersion !== expectedAdapter.version || work.resultSchemaVersion !== 'af.journal.intelligence.work-result.v1' ||
      !Number.isFinite(Date.parse(work.deadlineAt || '')) || Date.parse(work.deadlineAt) <= Date.now()) {
    throw new Error('Eligible Journal work is stale or outside the admitted producer contract.');
  }
  if (expectedAdapter.authoritativeExecutionId &&
      (work.claimedBy !== 'codex-cli' || typeof work.claimToken !== 'string' || !/^[0-9a-f-]{36}$/i.test(work.claimToken) ||
       typeof work.executorExecutionId !== 'string' || !/^[0-9a-f]{64}$/i.test(work.executorExecutionId) ||
       !Number.isFinite(Date.parse(work.claimExpiresAt || '')) || Date.parse(work.claimExpiresAt) <= Date.now())) {
    throw new Error('Codex CLI work lacks an active Journal-issued claim and executor identity.');
  }
  if (typeof work.question !== 'string' || !work.question.trim() || work.question.length > 2048 ||
      !isPlainObject(work.boundedContext) || !Array.isArray(work.evidenceManifest) ||
      !Array.isArray(work.materialDependencyManifest) ||
      !/^[0-9a-f]{40}$/.test(work.producerSourceCommit || '') || !/^[0-9a-f]{40}$/.test(work.producerSourceTree || '')) {
    throw new Error('Eligible Journal work context or source binding is invalid.');
  }
  const safeContext = redactBoundedContext(work.boundedContext);
  const safeEvidenceManifest = redactBoundedContext(work.evidenceManifest);
  const safeDependencies = redactBoundedContext(work.materialDependencyManifest);
  const boundedPayload = { question: work.question, boundedContext: safeContext, evidenceManifest: safeEvidenceManifest, materialDependencyManifest: safeDependencies };
  if (Buffer.byteLength(JSON.stringify(boundedPayload), 'utf8') > MAX_BOUNDED_CONTEXT_BYTES) throw new Error('Journal context exceeds the admitted byte limit.');
  return Object.freeze({ ...work, boundedContext: safeContext, evidenceManifest: safeEvidenceManifest, materialDependencyManifest: safeDependencies });
}

function sameExecution(work, current) {
  if (!current) return false;
  const fields = [
    'analysisRequestId', 'executionJobId', 'attemptId', 'accountId', 'tankId',
    'requestRevision', 'processingCycle', 'contextFingerprint', 'providerAdmissionId',
    'adapterKey', 'adapterVersion', 'resultSchemaVersion', 'deadlineAt',
    'producerSourceCommit', 'producerSourceTree',
  ];
  const adapter = adapterContractForWork(work);
  return fields.every((field) => String(work[field]) === String(current[field])) &&
    current.attemptState === adapter.attemptState && current.jobState === adapter.jobState && current.requestState === 'PROCESSING' &&
    (!adapter.authoritativeExecutionId || (current.claimedBy === work.claimedBy && current.executorExecutionId === work.executorExecutionId &&
      String(current.claimExpiresAt) === String(work.claimExpiresAt) && Date.parse(current.claimExpiresAt || '') > Date.now()));
}

function skillProvenance(skill) {
  return {
    name: skill.name,
    version: skill.version,
    sourceRepository: skill.repository,
    sourceCommit: skill.sourceCommit,
    schemaVersion: skill.schemaVersion,
    sourceFileSha256: Object.fromEntries(Object.entries(pinnedSkillLock.files).map(([name, sha256]) => [
      name.replace('skills/draneka-tank-analysis/', ''),
      sha256,
    ])),
  };
}

export function createExecutionProvenance({ sourceIdentity, executor, work, skill = pinnedSkillLock }) {
  validateExecutorProvenance(executor);
  const adapter = adapterContractForWork(work);
  return {
    producerIdentity: adapter.producerIdentity,
    producerRuntime: adapter.producerRuntime,
    producerSource: { ...sourceIdentity },
    executor: { ...executor },
    skill: skillProvenance(skill),
    executionBinding: {
      analysisRequestId: work.analysisRequestId,
      executionJobId: work.executionJobId,
      attemptId: work.attemptId,
      requestRevision: work.requestRevision,
      processingCycle: work.processingCycle,
      contextFingerprint: work.contextFingerprint,
      providerAdmissionId: work.providerAdmissionId,
      adapterKey: work.adapterKey,
      adapterVersion: work.adapterVersion,
    },
    artifactRepository: ARTIFACT_REPOSITORY,
    artifactNamespace: ARTIFACT_NAMESPACE,
    artifactSchema: ARTIFACT_SCHEMA,
  };
}

export async function executeEligibleWork({
  work: rawWork,
  journal,
  artifactStore,
  executor,
  sourceIdentity,
  skillResolver,
  lockFactory = acquireAttemptLock,
  now = () => new Date(),
}) {
  const adapter = adapterContractForWork(rawWork);
  const work = validateWorkIdentity(rawWork, adapter);
  if (work.producerSourceCommit !== sourceIdentity.commit || work.producerSourceTree !== sourceIdentity.tree) {
    return { status: 'ADMISSION_SOURCE_MISMATCH' };
  }
  const lock = await lockFactory(work.attemptId);
  if (!lock) return { status: 'DUPLICATE_SCAN_SKIPPED' };
  try {
    const before = await journal.current(work.attemptId, work.claimToken);
    if (!sameExecution(work, before)) return { status: 'STALE_BEFORE_EXECUTION' };
    const prior = await artifactStore.findExisting(work);
    if (prior) {
      await reconcileClaimedCodexArtifact(adapter, journal, work);
      return { status: 'EXISTING_ARTIFACT_VERIFIED', artifact: prior };
    }

    const skill = await skillResolver();
    if (skill.name !== pinnedSkillLock.name || skill.version !== pinnedSkillLock.version ||
        skill.sourceCommit !== pinnedSkillLock.sourceCommit || skill.schemaVersion !== pinnedSkillLock.schemaVersion) {
      return { status: 'PINNED_SKILL_MISMATCH' };
    }
    const modelWork = { ...work };
    for (const key of ['claimToken', 'claimTokenHash', 'claim_token', 'claim_token_hash', 'executorExecutionId', 'accountId', 'tankId']) delete modelWork[key];
    const execution = await executor({ skill, work: modelWork, onExecutorPid: lock.updateExecutorPid || (async () => {}) });
    const validation = validateTankAnalysisResult(execution.result, {
      expectedAnalysisRequestId: work.analysisRequestId,
      expectedQuestion: work.question,
      allowExternalResearch: false,
    });
    if (!validation.valid) return { status: 'INVALID_STRUCTURED_RESULT', errorCodes: validation.errors.slice(0, 12) };

    const after = await journal.current(work.attemptId, work.claimToken);
    if (!sameExecution(work, after)) return { status: 'STALE_AFTER_EXECUTION' };
    const provenanceExecutor = adapter.authoritativeExecutionId
      ? { ...execution.executor, executionId: work.executorExecutionId }
      : execution.executor;
    const provenance = createExecutionProvenance({ sourceIdentity, executor: provenanceExecutor, work, skill });
    const artifact = await artifactStore.createOnly({ work, result: execution.result, executionProvenance: provenance, createdAt: now().toISOString() });
    await reconcileClaimedCodexArtifact(adapter, journal, work);
    return { status: artifact.created ? 'ARTIFACT_CREATED' : 'EXISTING_ARTIFACT_VERIFIED', artifact };
  } finally {
    await lock.release();
  }
}

async function reconcileClaimedCodexArtifact(adapter, journal, work) {
  if (!adapter.authoritativeExecutionId) return;
  if (!journal || typeof journal.reconcile !== 'function') {
    throw new Error('The claimed Codex CLI artifact requires Journal-owned reconciliation.');
  }
  const acceptance = await journal.reconcile(work.attemptId, work.claimToken);
  if (!acceptance || acceptance.accepted !== true || acceptance.attemptId !== work.attemptId ||
      acceptance.analysisRequestId !== work.analysisRequestId) {
    throw new Error('Journal did not accept the exact current Codex CLI artifact.');
  }
}

export function artifactPathForWork(work) {
  return journalArtifactPath(work);
}

export function redactBoundedContextForTest(context) {
  return redactBoundedContext(context);
}
