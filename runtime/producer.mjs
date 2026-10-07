import { validateTankAnalysisResult } from './result-validator.mjs';
import { pinnedSkillLock } from './pinned-skill.mjs';
import { acquireAttemptLock } from './attempt-lock.mjs';
import { PRODUCER_IDENTITY, ARTIFACT_REPOSITORY, ARTIFACT_SCHEMA, ARTIFACT_NAMESPACE, journalArtifactPath } from './github-artifact-store.mjs';

export const PRODUCER_ADAPTER_KEY = 'draneka_intelligence_nonprod';
export const PRODUCER_ADAPTER_VERSION = 'codex-cli-tank-analysis-v3';
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

export function validateWorkIdentity(work, expectedAdapter = { key: PRODUCER_ADAPTER_KEY, version: PRODUCER_ADAPTER_VERSION }) {
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
      work.attemptState !== 'READY' || work.jobState !== 'DISPATCH_AUTHORIZED' || work.requestState !== 'PROCESSING' ||
      work.analysisType !== 'TANK_ANALYSIS' || work.adapterKey !== expectedAdapter.key ||
      work.adapterVersion !== expectedAdapter.version || work.resultSchemaVersion !== 'af.journal.intelligence.work-result.v1' ||
      !Number.isFinite(Date.parse(work.deadlineAt || '')) || Date.parse(work.deadlineAt) <= Date.now()) {
    throw new Error('Eligible Journal work is stale or outside the admitted producer contract.');
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
  return fields.every((field) => String(work[field]) === String(current[field])) &&
    current.attemptState === 'READY' && current.jobState === 'DISPATCH_AUTHORIZED' && current.requestState === 'PROCESSING';
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
  return {
    producerIdentity: PRODUCER_IDENTITY,
    producerRuntime: 'draneka-intelligence-nonprod-local',
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
  const work = validateWorkIdentity(rawWork);
  if (work.producerSourceCommit !== sourceIdentity.commit || work.producerSourceTree !== sourceIdentity.tree) {
    return { status: 'ADMISSION_SOURCE_MISMATCH' };
  }
  const lock = await lockFactory(work.attemptId);
  if (!lock) return { status: 'DUPLICATE_SCAN_SKIPPED' };
  try {
    const before = await journal.current(work.attemptId);
    if (!sameExecution(work, before)) return { status: 'STALE_BEFORE_EXECUTION' };
    const prior = await artifactStore.findExisting(work);
    if (prior) return { status: 'EXISTING_ARTIFACT_VERIFIED', artifact: prior };

    const skill = await skillResolver();
    if (skill.name !== pinnedSkillLock.name || skill.version !== pinnedSkillLock.version ||
        skill.sourceCommit !== pinnedSkillLock.sourceCommit || skill.schemaVersion !== pinnedSkillLock.schemaVersion) {
      return { status: 'PINNED_SKILL_MISMATCH' };
    }
    const execution = await executor({ skill, work, onExecutorPid: lock.updateExecutorPid || (async () => {}) });
    const validation = validateTankAnalysisResult(execution.result, {
      expectedAnalysisRequestId: work.analysisRequestId,
      expectedQuestion: work.question,
      allowExternalResearch: false,
    });
    if (!validation.valid) return { status: 'INVALID_STRUCTURED_RESULT', errorCodes: validation.errors.slice(0, 12) };

    const after = await journal.current(work.attemptId);
    if (!sameExecution(work, after)) return { status: 'STALE_AFTER_EXECUTION' };
    const provenance = createExecutionProvenance({ sourceIdentity, executor: execution.executor, work, skill });
    const artifact = await artifactStore.createOnly({ work, result: execution.result, executionProvenance: provenance, createdAt: now().toISOString() });
    return { status: artifact.created ? 'ARTIFACT_CREATED' : 'EXISTING_ARTIFACT_VERIFIED', artifact };
  } finally {
    await lock.release();
  }
}

export function artifactPathForWork(work) {
  return journalArtifactPath(work);
}

export function redactBoundedContextForTest(context) {
  return redactBoundedContext(context);
}
