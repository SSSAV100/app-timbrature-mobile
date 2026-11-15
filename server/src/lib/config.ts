// Configurazione del server, dalle impostazioni della Function App (i segreti
// arrivano dal Key Vault tramite riferimenti @Microsoft.KeyVault(...)).

export interface Customer {
  tenantId: string;
  environment: string;
  companyId: string;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Impostazione mancante: ${name}`);
  return value;
}

export const config = {
  get bcClientId(): string {
    return required('BC_CLIENT_ID');
  },
  get bcClientSecret(): string {
    return required('BC_CLIENT_SECRET');
  },
  get jwtSigningKey(): string {
    return required('JWT_SIGNING_KEY');
  },
};

/** Cliente dal codice azienda inserito nell'app (maiuscolo/minuscolo indifferente). */
export function getCustomer(code: string): Customer | undefined {
  const customers = JSON.parse(required('CUSTOMERS')) as Record<string, Customer>;
  const key = Object.keys(customers).find((k) => k.toUpperCase() === code.trim().toUpperCase());
  return key ? customers[key] : undefined;
}
