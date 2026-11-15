import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hashPassword, verifyPassword } from '../src/lib/password';

test('verifica password: corretta e sbagliata', () => {
  const salt = 'abc123';
  const hash = hashPassword('segreta1', salt);
  assert.equal(hash.length, 64);
  assert.ok(verifyPassword('segreta1', salt, hash));
  assert.ok(verifyPassword('segreta1', salt, hash.toUpperCase()));
  assert.ok(!verifyPassword('sbagliata', salt, hash));
});
