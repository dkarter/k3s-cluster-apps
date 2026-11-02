// Uses only Node built-ins already present in the official Renovate image.
const { sign } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { spawnSync } = require('node:child_process');

function createJwt(appId, privateKey, now = Math.floor(Date.now() / 1000)) {
  if (!/^\d+$/.test(appId || '')) throw new Error('Invalid App ID');
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({
    iat: now - 60,
    exp: now + 540,
    iss: appId,
  })}`;
  return `${unsigned}.${sign('RSA-SHA256', Buffer.from(unsigned), privateKey).toString('base64url')}`;
}

async function installationToken(
  jwt,
  installationId,
  repositories,
  request = fetch,
) {
  if (!/^\d+$/.test(installationId || ''))
    throw new Error('Invalid installation ID');
  if (
    !Array.isArray(repositories) ||
    repositories.length !== 1 ||
    repositories[0] !== 'dkarter/k3s-cluster-apps'
  )
    throw new Error('Unexpected repository allowlist');
  const response = await request(
    `https://api.github.com/app/installations/${installationId}/access_tokens`,
    {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(30000),
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${jwt}`,
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'k3s-renovate',
      },
      body: JSON.stringify({ repositories: ['k3s-cluster-apps'] }),
    },
  );
  // Never include response bodies or request headers in errors/logs.
  if (!response.ok)
    throw new Error(`GitHub token request failed (${response.status})`);
  const { token } = await response.json();
  if (typeof token !== 'string' || !token)
    throw new Error('GitHub returned no token');
  return token;
}

async function main(
  env = process.env,
  request = fetch,
  run = spawnSync,
  read = readFileSync,
) {
  const repositories = JSON.parse(env.RENOVATE_REPOSITORIES);
  const jwt = createJwt(
    env.RENOVATE_APP_ID,
    read('/var/run/renovate-app/private-key.pem'),
  );
  const token = await installationToken(
    jwt,
    env.RENOVATE_INSTALLATION_ID,
    repositories,
    request,
  );
  const childEnv = { ...env, RENOVATE_TOKEN: token };
  delete childEnv.RENOVATE_APP_ID;
  delete childEnv.RENOVATE_INSTALLATION_ID;
  const result = run('renovate', [], {
    env: childEnv,
    stdio: 'inherit',
    timeout: 45 * 60 * 1000,
    killSignal: 'SIGKILL',
  });
  return result.error || result.signal ? 1 : (result.status ?? 1);
}

if (require.main === module) {
  main().then(
    (status) => {
      process.exitCode = status;
    },
    () => {
      console.error(
        'Renovate runner failed; check App configuration and connectivity.',
      );
      process.exitCode = 1;
    },
  );
}

module.exports = { createJwt, installationToken, main };
