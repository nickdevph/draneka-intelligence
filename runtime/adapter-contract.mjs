export const NONPROD_CODEX_ADAPTER = Object.freeze({
  key: 'draneka_intelligence_nonprod',
  version: 'codex-cli-tank-analysis-v3',
  producerIdentity: 'draneka_intelligence_nonprod',
  producerRuntime: 'draneka-intelligence-nonprod-local',
  claimMode: 'scan',
  attemptState: 'READY',
  jobState: 'DISPATCH_AUTHORIZED',
  authoritativeExecutionId: false,
});

export const PRODUCTION_CODEX_CLI_ADAPTER = Object.freeze({
  key: 'codex_cli',
  version: 'codex-cli-tank-analysis-v1',
  producerIdentity: 'codex_cli',
  producerRuntime: 'draneka-intelligence-local-codex-cli',
  claimMode: 'claim',
  attemptState: 'CLAIMED',
  jobState: 'CLAIMED',
  authoritativeExecutionId: true,
});

const ADAPTERS = new Map([
  [NONPROD_CODEX_ADAPTER.key, NONPROD_CODEX_ADAPTER],
  [PRODUCTION_CODEX_CLI_ADAPTER.key, PRODUCTION_CODEX_CLI_ADAPTER],
]);

export function adapterContractForWork(work) {
  const adapter = ADAPTERS.get(String(work?.adapterKey || ''));
  if (!adapter || adapter.version !== work?.adapterVersion) {
    throw new Error('Journal work is outside a known Codex adapter contract.');
  }
  return adapter;
}
