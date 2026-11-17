const assert = require('node:assert/strict');
const { generateKeyPairSync, verify } = require('node:crypto');
const { test } = require('node:test');
const {
  createJwt,
  installationToken,
  main,
} = require('../renovate/runner.cjs');

// Ephemeral test-only keypair; no local or remote credentials are accessed.
const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
});
const repositories = ['dkarter/k3s-cluster-apps'];
const env = {
  RENOVATE_APP_ID: '123',
  RENOVATE_INSTALLATION_ID: '456',
  RENOVATE_REPOSITORIES: JSON.stringify(repositories),
  RENOVATE_DRY_RUN: 'full',
};
const success = async () => ({
  ok: true,
  json: async () => ({ token: 'test-only-token' }),
});

test('JWT uses RS256, short expiry and clock-skew allowance', () => {
  const jwt = createJwt('123', privateKey, 1000);
  const [header, payload, signature] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), {
    alg: 'RS256',
    typ: 'JWT',
  });
  assert.deepEqual(JSON.parse(Buffer.from(payload, 'base64url')), {
    iat: 940,
    exp: 1540,
    iss: '123',
  });
  assert.ok(
    verify(
      'RSA-SHA256',
      Buffer.from(`${header}.${payload}`),
      publicKey,
      Buffer.from(signature, 'base64url'),
    ),
  );
  assert.throws(() => createJwt('', privateKey), /Invalid App ID/);
});

test('token request is scoped to the one repository and cannot redirect', async () => {
  const token = await installationToken(
    'test-jwt',
    '456',
    repositories,
    async (url, options) => {
      assert.equal(
        url,
        'https://api.github.com/app/installations/456/access_tokens',
      );
      assert.equal(options.method, 'POST');
      assert.equal(options.redirect, 'error');
      assert.equal(options.headers.Authorization, 'Bearer test-jwt');
      assert.deepEqual(JSON.parse(options.body), {
        repositories: ['k3s-cluster-apps'],
      });
      assert.ok(options.signal instanceof AbortSignal);
      return success();
    },
  );
  assert.equal(token, 'test-only-token');
});

test('invalid installation IDs and repository lists fail before network access', async () => {
  const unexpected = async () => assert.fail('Unexpected network request');
  await assert.rejects(
    installationToken('jwt', '../other', repositories, unexpected),
    /Invalid installation ID/,
  );
  for (const list of [
    [],
    ['other/repo'],
    [...repositories, 'other/repo'],
    'other/repo',
  ]) {
    await assert.rejects(
      installationToken('jwt', '456', list, unexpected),
      /Unexpected repository allowlist/,
    );
  }
});

test('HTTP failures do not expose response content and missing tokens fail closed', async () => {
  await assert.rejects(
    installationToken('jwt', '456', repositories, async () => ({
      ok: false,
      status: 403,
      json: () => assert.fail('Must not read error body'),
    })),
    /^Error: GitHub token request failed \(403\)$/,
  );
  await assert.rejects(
    installationToken('jwt', '456', repositories, async () => ({
      ok: true,
      json: async () => ({}),
    })),
    /GitHub returned no token/,
  );
});

test('runner passes token only in child environment and preserves dry-run mode', async () => {
  const status = await main(
    env,
    success,
    (command, args, options) => {
      assert.equal(command, 'renovate');
      assert.deepEqual(args, []);
      assert.equal(options.env.RENOVATE_TOKEN, 'test-only-token');
      assert.equal(options.env.RENOVATE_DRY_RUN, 'full');
      assert.equal(options.env.RENOVATE_APP_ID, undefined);
      assert.equal(options.env.RENOVATE_INSTALLATION_ID, undefined);
      assert.equal(options.timeout, 2700000);
      assert.equal(options.killSignal, 'SIGKILL');
      assert.equal(options.stdio, 'inherit');
      return { status: 0 };
    },
    (path) => {
      assert.equal(path, '/var/run/renovate-app/private-key.pem');
      return privateKey;
    },
  );
  assert.equal(status, 0);
  assert.equal(env.RENOVATE_TOKEN, undefined);
});

test('child errors, signals and nonzero exits fail the job', async () => {
  for (const result of [
    { status: 7 },
    { signal: 'SIGKILL' },
    { error: new Error('test') },
    {},
  ]) {
    assert.notEqual(
      await main(
        env,
        success,
        () => result,
        () => privateKey,
      ),
      0,
    );
  }
});

test('failed authentication never starts Renovate', async () => {
  await assert.rejects(
    main(
      env,
      async () => ({ ok: false, status: 401 }),
      () => {
        assert.fail('Renovate must not start');
      },
      () => privateKey,
    ),
    /GitHub token request failed/,
  );
});
