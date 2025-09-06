import type { Plugin } from '@opencode-ai/plugin';

type Pattern = {
  regex: RegExp;
  msg: string;
};

const forbiddenFilePatterns: Pattern[] = [
  {
    regex: /\.env/,
    msg: 'Do not read .env files',
  },
];

const forbiddenCommandPatterns: Pattern[] = [
  {
    regex: /kubectl .*get .*secret/,
    msg: 'Do not read kubernetes secrets',
  },
  {
    regex: /gcloud .*secrets/,
    msg: 'Do not read gcloud secrets',
  },
  {
    regex: /gh auth token/,
    msg: 'Do not read github tokens',
  },
  {
    regex: /gh auth status --show-token/,
    msg: 'Do not read github tokens',
  },
];

export const EnvProtectionPlugin: Plugin = async () => {
  return {
    'tool.execute.before': async (input, output) => {
      forbiddenFilePatterns.forEach(({ regex, msg }) => {
        const readingForbiddenPathDirectly =
          input.tool === 'read' && regex.test(output.args.filePath);

        const readingForbiddenPathViaBash =
          input.tool === 'bash' &&
          /(cat|bat|rg|grep)/.test(output.args.command) &&
          regex.test(output.args.command);

        const readingForbiddenPathViaGrep =
          input.tool === 'grep' && /(\.env)/.test(output.args.include);

        if (
          readingForbiddenPathDirectly ||
          readingForbiddenPathViaBash ||
          readingForbiddenPathViaGrep
        ) {
          throw new Error(msg);
        }
      });

      forbiddenCommandPatterns.forEach(({ regex, msg }) => {
        if (input.tool === 'bash' && regex.test(output.args.command)) {
          throw new Error(msg);
        }
      });
    },
  };
};
