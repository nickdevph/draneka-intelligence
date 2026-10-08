import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const runtimeDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(runtimeDirectory, '..');
const lock = JSON.parse(await readFile(path.join(runtimeDirectory, 'skill-lock.json'), 'utf8'));

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export async function resolvePinnedTankAnalysisSkill({ root = repositoryRoot } = {}) {
  const files = {};
  for (const [relativePath, expectedSha256] of Object.entries(lock.files)) {
    const workingPath = path.resolve(root, relativePath);
    const content = await readFile(workingPath);
    const actualSha256 = sha256(content);
    if (actualSha256 !== expectedSha256) throw new Error(`Pinned Tank Analysis support file mismatch: ${relativePath}.`);
    const committedContent = execFileSync('git', ['-C', root, 'show', `${lock.sourceCommit}:${relativePath}`], { encoding: 'buffer', stdio: ['ignore', 'pipe', 'ignore'] });
    if (sha256(committedContent) !== expectedSha256 || !committedContent.equals(content)) {
      throw new Error(`Pinned Tank Analysis source commit mismatch: ${relativePath}.`);
    }
    files[relativePath] = content.toString('utf8');
  }
  const schema = JSON.parse(files['skills/draneka-tank-analysis/schemas/tank-analysis-result.schema.json']);
  if (schema.properties?.schema_version?.const !== lock.schemaVersion) throw new Error('Pinned Tank Analysis result schema identity mismatch.');
  const skillText = files['skills/draneka-tank-analysis/SKILL.md'];
  if (!/^name:\s*draneka-tank-analysis\s*$/m.test(skillText) || !/^  version:\s*["']?0\.1\.0["']?\s*$/m.test(skillText)) {
    throw new Error('Pinned Tank Analysis skill name or version mismatch.');
  }
  return Object.freeze({ ...lock, files, schema });
}

export async function captureProducerSourceIdentity({ root = repositoryRoot } = {}) {
  const text = (args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  if (text(['status', '--porcelain=v1'])) throw new Error('Producer source worktree must be clean before runtime execution.');
  const commit = text(['rev-parse', 'HEAD']);
  const tree = text(['rev-parse', 'HEAD^{tree}']);
  const branch = text(['branch', '--show-current']);
  if (!/^[0-9a-f]{40}$/.test(commit) || !/^[0-9a-f]{40}$/.test(tree) || !branch || branch === 'main') {
    throw new Error('Producer source identity is incomplete or not an implementation candidate.');
  }
  return Object.freeze({ repository: 'nickdevph/draneka-intelligence', branch, commit, tree });
}

export const pinnedSkillLock = lock;
