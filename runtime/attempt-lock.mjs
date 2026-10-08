import { link, mkdir, open, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

const LOCK_ROOT = path.join(os.tmpdir(), 'draneka-intelligence-nonprod-producer-locks');

async function pidIsAlive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code === 'EPERM';
  }
}

export async function acquireAttemptLock(attemptId, { root = LOCK_ROOT, pid = process.pid, now = Date.now() } = {}) {
  if (typeof attemptId !== 'string' || !/^[0-9a-f-]{36}$/i.test(attemptId)) throw new TypeError('Attempt identity is invalid.');
  await mkdir(root, { recursive: true, mode: 0o700 });
  const lockPath = path.join(root, `${attemptId}.lock`);
  const identity = { pid, startedAt: now, nonce: randomUUID(), hostname: os.hostname() };
  for (let retry = 0; retry < 3; retry += 1) {
    const temporaryPath = `${lockPath}.${identity.nonce}.tmp`;
    try {
      const handle = await open(temporaryPath, 'wx', 0o600);
      await handle.writeFile(JSON.stringify(identity));
      await handle.sync();
      await handle.close();
      await link(temporaryPath, lockPath);
      await rm(temporaryPath, { force: true });
      return {
        identity,
        async updateExecutorPid(executorPid) {
          const current = JSON.parse(await readFile(lockPath, 'utf8'));
          if (current.nonce !== identity.nonce) return;
          const updated = `${lockPath}.${identity.nonce}.update`;
          try {
            await writeFile(updated, JSON.stringify({ ...current, executorPid }), { mode: 0o600, flag: 'wx' });
            await rename(updated, lockPath);
          } catch (error) {
            await rm(updated, { force: true });
            throw error;
          }
        },
        async release() {
          try {
            const current = JSON.parse(await readFile(lockPath, 'utf8'));
            if (current.nonce === identity.nonce) await rm(lockPath, { force: true });
          } catch { /* a stale or externally recovered lock is already gone */ }
        },
      };
    } catch (error) {
      await rm(temporaryPath, { force: true });
      if (error?.code !== 'EEXIST') throw error;
      let prior;
      try {
        const [raw, details] = await Promise.all([readFile(lockPath, 'utf8'), stat(lockPath)]);
        prior = JSON.parse(raw);
        const ownerAlive = await pidIsAlive(Number(prior.pid));
        const executorAlive = await pidIsAlive(Number(prior.executorPid));
        if (!ownerAlive && !executorAlive && Date.now() - details.mtimeMs > 1000) {
          await rm(lockPath, { force: true });
          continue;
        }
      } catch (readError) {
        if (readError?.code === 'ENOENT') continue;
        try {
          const details = await stat(lockPath);
          if (Date.now() - details.mtimeMs > 1000) await rm(lockPath, { force: true });
        } catch { /* another process already replaced the lock */ }
        continue;
      }
      return null;
    }
  }
  return null;
}

export function attemptLockRoot() {
  return LOCK_ROOT;
}
