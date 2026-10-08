import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.resolve(directory, '../skills/draneka-tank-analysis/schemas/tank-analysis-result.schema.json');
const schema = JSON.parse(await readFile(schemaPath, 'utf8'));
// The pinned canonical schema is Draft 2020-12 valid, but uses conditional
// array keywords without repeating the outer property type inside `if`.
// Keep schema validation strict while allowing that valid composition.
const ajv = new Ajv2020({ allErrors: true, strict: true, strictTypes: false, validateFormats: true });
addFormats(ajv);
const validateSchema = ajv.compile(schema);

const REFERENCE_FIELDS = [
  ['findings', 'basis'],
  ['hypotheses', 'evidence_for'],
  ['hypotheses', 'evidence_against'],
  ['recommended_actions', 'basis'],
];

function isPlainObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function semanticErrors(result, { expectedAnalysisRequestId, expectedQuestion, allowExternalResearch }) {
  const errors = [];
  const evidence = Array.isArray(result?.evidence) ? result.evidence : [];
  const evidenceIds = evidence.map((item) => item?.id);
  if (evidenceIds.some((id) => typeof id !== 'string' || !id.trim()) || new Set(evidenceIds).size !== evidenceIds.length) {
    errors.push('EVIDENCE_IDS_NOT_UNIQUE');
  }
  for (const [arrayName, fieldName] of REFERENCE_FIELDS) {
    const items = Array.isArray(result?.[arrayName]) ? result[arrayName] : [];
    for (const item of items) {
      for (const reference of Array.isArray(item?.[fieldName]) ? item[fieldName] : []) {
        if (evidenceIds.filter((id) => id === reference).length !== 1) errors.push('EVIDENCE_REFERENCE_NOT_UNIQUE');
      }
    }
  }
  const ranks = Array.isArray(result?.hypotheses) ? result.hypotheses.map((item) => item?.rank) : [];
  if (ranks.some((rank, index) => rank !== index + 1) || new Set(ranks).size !== ranks.length) errors.push('HYPOTHESIS_RANKS_INVALID');
  const externalSources = Array.isArray(result?.provenance?.external_sources) ? result.provenance.external_sources : [];
  const externalIds = externalSources.map((source) => source?.id);
  if (new Set(externalIds).size !== externalIds.length) errors.push('EXTERNAL_SOURCE_IDS_NOT_UNIQUE');
  for (const item of evidence.filter((candidate) => candidate?.source_class === 'external_source')) {
    if (!item.source_ref || externalIds.filter((id) => id === item.source_ref).length !== 1) errors.push('EXTERNAL_SOURCE_REF_INVALID');
  }
  const usesExternal = evidence.some((item) => item?.source_class === 'external_source') ||
    result?.provenance?.knowledge_classes_used?.includes?.('external_source');
  if (usesExternal && !allowExternalResearch) errors.push('EXTERNAL_RESEARCH_NOT_AUTHORIZED');
  if (result?.request?.request_id !== expectedAnalysisRequestId) errors.push('REQUEST_ID_MISMATCH');
  if (result?.request?.question !== expectedQuestion) errors.push('QUESTION_MISMATCH');
  if (result?.request?.tank_id !== null) errors.push('TANK_ID_NOT_REDACTED');
  if (result?.skill?.name !== 'draneka-tank-analysis' || result?.skill?.version !== '0.1.0') errors.push('SKILL_IDENTITY_MISMATCH');
  return [...new Set(errors)];
}

export function validateTankAnalysisResult(result, options = {}) {
  const { expectedAnalysisRequestId, expectedQuestion, allowExternalResearch = false } = options;
  if (!isPlainObject(result)) return { valid: false, errors: ['RESULT_NOT_OBJECT'] };
  const schemaValid = validateSchema(result);
  const errors = [
    ...(schemaValid ? [] : (validateSchema.errors || []).map((error) => `SCHEMA:${error.instancePath || '/'}:${error.keyword}`)),
    ...semanticErrors(result, { expectedAnalysisRequestId, expectedQuestion, allowExternalResearch }),
  ];
  return { valid: errors.length === 0, errors };
}

export async function loadTankAnalysisSchema() {
  return JSON.parse(await readFile(schemaPath, 'utf8'));
}
