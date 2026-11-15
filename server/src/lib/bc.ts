import { config, Customer } from './config';

// Chiamate a Business Central con l'identità tecnica del server
// (client credentials sull'applicazione Entra multi-tenant).

const tokenCache = new Map<string, { token: string; expiresAt: number }>();

async function getBcToken(tenantId: string): Promise<string> {
  const cached = tokenCache.get(tenantId);
  if (cached && cached.expiresAt > Date.now() + 60_000) return cached.token;

  const response = await fetch(`https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: config.bcClientId,
      client_secret: config.bcClientSecret,
      scope: 'https://api.businesscentral.dynamics.com/.default',
    }),
  });
  if (!response.ok) {
    throw new Error(`Token BC non ottenuto (${response.status}): ${await response.text()}`);
  }
  const data = (await response.json()) as { access_token: string; expires_in: number };
  tokenCache.set(tenantId, { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 });
  return data.access_token;
}

export function bcBaseUrl(customer: Customer): string {
  return (
    `https://api.businesscentral.dynamics.com/v2.0/${customer.tenantId}/${customer.environment}` +
    `/api/salarysolution/timbrature/v1.0/companies(${customer.companyId})`
  );
}

export async function bcFetch(
  customer: Customer,
  pathAndQuery: string,
  init: { method: string; body?: string; ifMatch?: string },
): Promise<Response> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${await getBcToken(customer.tenantId)}`,
    Accept: 'application/json',
  };
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';
  if (init.ifMatch) headers['If-Match'] = init.ifMatch;
  return fetch(`${bcBaseUrl(customer)}/${pathAndQuery}`, { method: init.method, headers, body: init.body });
}

/** Valore stringa per un $filter OData (apici raddoppiati). */
export const odataString = (value: string) => `'${value.replace(/'/g, "''")}'`;
