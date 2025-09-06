import type { Plugin } from '@opencode-ai/plugin';

export const LintPlugin: Plugin = async ({ $ }) => {
  return {
    'tool.execute.after': async (input, output) => {
      if (
        ['write', 'edit'].includes(input.tool) &&
        /\.ya?ml$/.test(output.title)
      ) {
        const { stdout, stderr, exitCode } =
          await $`task validate:file -- ${output.title}`.nothrow().quiet();
        if (exitCode !== 0) {
          throw new Error(
            `Linting failed for ${output.title}:\n${stdout.toString()}\n${stderr.toString()}`,
          );
        }
      }
    },
  };
};
