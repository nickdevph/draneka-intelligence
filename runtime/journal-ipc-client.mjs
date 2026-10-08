import http from 'node:http';

export class JournalProducerIpcClient {
  constructor(socketPath, { timeoutMs = 5000 } = {}) {
    if (typeof socketPath !== 'string' || !socketPath.startsWith('/')) throw new TypeError('A local Journal producer socket path is required.');
    this.socketPath = socketPath;
    this.timeoutMs = timeoutMs;
  }

  async request(method, requestPath, body = undefined) {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    return new Promise((resolve, reject) => {
      const request = http.request({
        socketPath: this.socketPath,
        path: requestPath,
        method,
        headers: payload ? { 'content-type': 'application/json', 'content-length': payload.length } : {},
        timeout: this.timeoutMs,
      }, (response) => {
        const chunks = [];
        let size = 0;
        response.on('data', (chunk) => {
          size += chunk.length;
          if (size > 150_000) {
            request.destroy(new Error('Journal producer response exceeded its bounded limit.'));
            return;
          }
          chunks.push(chunk);
        });
        response.on('end', () => {
          let data;
          try { data = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch {
            reject(new Error('Journal producer returned malformed JSON.'));
            return;
          }
          resolve({ status: Number(response.statusCode || 0), data });
        });
      });
      request.on('timeout', () => request.destroy(new Error('Journal producer request timed out.')));
      request.on('error', reject);
      if (payload) request.write(payload);
      request.end();
    });
  }

  async scan(excludeAttemptIds = []) {
    const response = await this.request('POST', '/v1/producer/scan', { excludeAttemptIds });
    if (response.status !== 200) throw new Error(`Journal producer scan failed (${response.status}).`);
    return response.data.work || null;
  }

  async current(attemptId) {
    const response = await this.request('GET', `/v1/producer/work/${encodeURIComponent(attemptId)}/current`);
    if (response.status === 404 || response.status === 409) return null;
    if (response.status !== 200) throw new Error(`Journal producer currentness check failed (${response.status}).`);
    return response.data.work || null;
  }
}
