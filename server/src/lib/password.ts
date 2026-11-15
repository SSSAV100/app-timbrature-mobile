import { createHmac, timingSafeEqual } from 'node:crypto';

// Stesso calcolo di "SS App Credential Mgt" in BC: HMAC-SHA256 con chiave =
// sale, ripetuto ITERATIONS volte, ogni passo in esadecimale minuscolo.
export const ITERATIONS = 5000;

export function hashPassword(password: string, salt: string): string {
  let hash = createHmac('sha256', salt).update(password, 'utf8').digest('hex');
  for (let i = 2; i <= ITERATIONS; i++) {
    hash = createHmac('sha256', salt).update(hash, 'utf8').digest('hex');
  }
  return hash;
}

export function verifyPassword(password: string, salt: string, expectedHash: string): boolean {
  if (!salt || !expectedHash) return false;
  const actual = Buffer.from(hashPassword(password, salt), 'utf8');
  const expected = Buffer.from(expectedHash.toLowerCase(), 'utf8');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
