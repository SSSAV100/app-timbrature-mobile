import { createHmac, timingSafeEqual } from 'node:crypto';
import { config } from './config';

// Pass dell'app per il login con utente e password: JWT HS256 firmato con la
// chiave del Key Vault. Contiene cliente, dipendente e risorsa (per il Service).

export interface AppClaims {
  sub: string; // Employee No.
  cust: string; // codice azienda
  res: string; // Resource No. (filtro degli interventi Service)
  iat: number;
  exp: number;
}

export const TOKEN_DAYS = 30;

const b64url = (data: Buffer | string) =>
  Buffer.from(data).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

function sign(input: string): string {
  return b64url(createHmac('sha256', config.jwtSigningKey).update(input).digest());
}

export function issueToken(claims: Omit<AppClaims, 'iat' | 'exp'>): { token: string; expiresAt: number } {
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + TOKEN_DAYS * 24 * 3600;
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({ ...claims, iat, exp }));
  const token = `${header}.${payload}.${sign(`${header}.${payload}`)}`;
  return { token, expiresAt: exp };
}

/** Claims del pass, oppure null se mancante, falsificato o scaduto. */
export function verifyToken(authorization: string | null): AppClaims | null {
  const match = /^Bearer\s+(.+)$/i.exec(authorization ?? '');
  if (!match) return null;
  const parts = match[1].split('.');
  if (parts.length !== 3) return null;
  const expected = Buffer.from(sign(`${parts[0]}.${parts[1]}`));
  const actual = Buffer.from(parts[2]);
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) return null;
  try {
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')) as AppClaims;
    if (!claims.sub || !claims.cust || claims.exp < Date.now() / 1000) return null;
    return claims;
  } catch {
    return null;
  }
}
