import { describe, expect, test } from 'bun:test';
import plugin from '../env-protection';

type ToolEvent = { tool: string; input: Record<string, string> };

describe('env protection', () => {
  test('registers a V2 before-execution hook and blocks protected inputs', async () => {
    let before: ((event: ToolEvent) => void) | undefined;
    await plugin.setup({
      tool: {
        hook: async (name: string, callback: (event: ToolEvent) => void) => {
          expect(name).toBe('execute.before');
          before = callback;
          return { dispose: async () => {} };
        },
      },
    } as Parameters<typeof plugin.setup>[0]);

    expect(plugin.id).toBe('env-protection');
    expect(before).toBeDefined();
    const run = (tool: string, input: Record<string, string>) => before!({ tool, input });

    expect(() => run('read', { path: '/project/.env.local' })).toThrow('Do not read .env files');
    expect(() => run('read', { filePath: '/project/.env' })).toThrow('Do not read .env files');
    expect(() => run('shell', { command: 'cat .env' })).toThrow('Do not read .env files');
    expect(() => run('grep', { include: '**/.env*' })).toThrow('Do not read .env files');
    expect(() => run('shell', { command: 'kubectl get secret' })).toThrow('Do not read kubernetes secrets');
    expect(() => run('shell', { command: 'gh auth token' })).toThrow('Do not read github tokens');
    expect(() => run('shell', { command: 'gh auth status --show-token' })).toThrow('Do not read github tokens');
    expect(() => run('shell', { command: 'gcloud secrets list' })).toThrow('Do not read gcloud secrets');
    expect(() => run('read', { path: '/project/values.yaml' })).not.toThrow();
    expect(() => run('shell', { command: 'git status' })).not.toThrow();
  });
});
