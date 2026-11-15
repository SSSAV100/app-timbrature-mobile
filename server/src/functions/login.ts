import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { getCustomer } from '../lib/config';
import { bcFetch, odataString } from '../lib/bc';
import { verifyPassword } from '../lib/password';
import { issueToken } from '../lib/token';

// POST /api/login  { company, username, password }
// Verifica utente e password sulla scheda dipendente SwissSalary (appLogins in
// BC) e restituisce il pass personale dell'app.

interface AppLogin {
  employeeId: string;
  login: string;
  passwordHash: string;
  passwordSalt: string;
  resourceNo: string;
}

const failed = (): HttpResponseInit => ({
  status: 401,
  jsonBody: { error: 'Codice azienda, nome utente o password non corretti.' },
});

export async function login(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  let body: { company?: string; username?: string; password?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return { status: 400, jsonBody: { error: 'Richiesta non valida.' } };
  }
  const company = (body.company ?? '').trim();
  const username = (body.username ?? '').trim();
  const password = body.password ?? '';
  if (!company || !username || !password) return failed();

  const customer = getCustomer(company);
  if (!customer) {
    // Stesso messaggio di una password sbagliata: non si rivela se il codice esiste.
    await new Promise((r) => setTimeout(r, 400));
    return failed();
  }

  try {
    // In BC il nome utente è un campo Code: sempre maiuscolo.
    const response = await bcFetch(customer, `appLogins?$filter=login eq ${odataString(username.toUpperCase())}`, {
      method: 'GET',
    });
    if (!response.ok) {
      context.error(`appLogins ${response.status}: ${await response.text()}`);
      return { status: 502, jsonBody: { error: 'Business Central non raggiungibile, riprovare più tardi.' } };
    }
    const rows = ((await response.json()) as { value: AppLogin[] }).value ?? [];
    const user = rows[0];
    if (!user || !verifyPassword(password, user.passwordSalt, user.passwordHash)) {
      await new Promise((r) => setTimeout(r, 400));
      return failed();
    }

    const { token, expiresAt } = issueToken({ sub: user.employeeId, cust: company.toUpperCase(), res: user.resourceNo ?? '' });
    context.log(`Login ok: ${company.toUpperCase()} / ${user.employeeId}`);
    return { status: 200, jsonBody: { token, expiresAt, employeeId: user.employeeId } };
  } catch (e) {
    context.error(e);
    return { status: 502, jsonBody: { error: 'Business Central non raggiungibile, riprovare più tardi.' } };
  }
}

app.http('login', { methods: ['POST'], authLevel: 'anonymous', route: 'login', handler: login });
