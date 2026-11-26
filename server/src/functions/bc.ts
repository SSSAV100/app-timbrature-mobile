import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { getCustomer } from '../lib/config';
import { bcFetch, odataString } from '../lib/bc';
import { verifyToken } from '../lib/token';

// /api/bc/{entitySet...}: le chiamate dell'app (login utente e password)
// inoltrate al BC del cliente, a nome del dipendente del pass.
// - lettura: il server filtra per il dipendente dove serve (BC non ha l'utente);
// - inserimento: il server mette employeeId nel corpo (BC lo accetta solo dal server);
// - approvazioni e appLogins non sono disponibili da qui.

// Insiemi di entità permessi e filtro per dipendente da imporre in lettura.
const READ_FILTER: Record<string, ((emp: string, res: string) => string) | null> = {
  me: (emp) => `employeeId eq ${odataString(emp)}`,
  vacationBalances: (emp) => `employeeNo eq ${odataString(emp)}`,
  serviceAssignments: (_emp, res) => `resourceNo eq ${odataString(res || '-')}`,
  assignedProjects: null,
  assignedJobTasks: null,
  workTypes: null,
  materialItems: null,
  companyBranding: null,
  pendingApprovals: null,
  vacationApprovers: null,
  vacationApprovals: null,
  absenceStatuses: (emp) => `employeeNo eq ${odataString(emp)}`,
};

const WRITE_SETS = new Set([
  'timeEntries',
  'timePunches',
  'absenceRequests',
  'expenseReports',
  'serviceEvents',
  'serviceHours',
  'serviceMaterials',
  'serviceAttachments',
  'projectReports',
  'projectReportMaterials',
  'projectAttachments',
  'lunchBreaks',
  'projectReportLabor',
]);

export async function bcProxy(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  const claims = verifyToken(request.headers.get('authorization'));
  if (!claims) return { status: 401, jsonBody: { error: 'Sessione scaduta, rifare il login.' } };
  const customer = getCustomer(claims.cust);
  if (!customer) return { status: 401, jsonBody: { error: 'Azienda non più configurata.' } };

  const path = request.params.path ?? '';
  const entitySet = path.split(/[(/?]/)[0];
  const method = request.method.toUpperCase();

  try {
    let response: Response;
    if (method === 'GET') {
      if (!(entitySet in READ_FILTER)) return { status: 404, jsonBody: { error: 'Risorsa non disponibile.' } };
      const query = new URLSearchParams(request.query);
      const filter = READ_FILTER[entitySet];
      if (filter) query.set('$filter', filter(claims.sub, claims.res));
      const qs = query.toString().replace(/%24/g, '$');
      response = await bcFetch(customer, qs ? `${path}?${qs}` : path, { method });
    } else if (method === 'POST' && WRITE_SETS.has(entitySet) && path === entitySet) {
      const body = (await request.json()) as Record<string, unknown>;
      body.employeeId = claims.sub;
      response = await bcFetch(customer, path, { method, body: JSON.stringify(body) });
    } else {
      // Es. PATCH approvalDecisions: le approvazioni sono solo per gli utenti BC.
      return { status: 403, jsonBody: { error: 'Operazione non disponibile con il login utente e password.' } };
    }

    const text = await response.text();
    if (!response.ok) context.warn(`${method} ${entitySet} -> ${response.status}: ${text.slice(0, 500)}`);
    return {
      status: response.status,
      headers: { 'Content-Type': response.headers.get('content-type') ?? 'application/json' },
      body: text,
    };
  } catch (e) {
    context.error(e);
    return { status: 502, jsonBody: { error: 'Business Central non raggiungibile, riprovare più tardi.' } };
  }
}

app.http('bc', {
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
  authLevel: 'anonymous',
  route: 'bc/{*path}',
  handler: bcProxy,
});
