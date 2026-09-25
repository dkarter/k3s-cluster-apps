import { Plugin } from '@opencode/plugin';

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

export default Plugin.define({
  id: 'env-protection',
  async setup(ctx) {
    await ctx.tool.hook('execute.before', (event) => {
      const input = event.input as {
        path?: string;
        filePath?: string;
        command?: string;
        include?: string;
      };
      const command = input.command ?? '';

      forbiddenFilePatterns.forEach(({ regex, msg }) => {
        const readingForbiddenPathDirectly =
          event.tool === 'read' && regex.test(input.path ?? input.filePath ?? '');

        const readingForbiddenPathViaBash =
          (event.tool === 'shell' || event.tool === 'bash') &&
          /(cat|bat|rg|grep)/.test(command) &&
          regex.test(command);

        const readingForbiddenPathViaGrep =
          event.tool === 'grep' && regex.test(input.include ?? '');

        if (
          readingForbiddenPathDirectly ||
          readingForbiddenPathViaBash ||
          readingForbiddenPathViaGrep
        ) {
          throw new Error(msg);
        }
      });

      forbiddenCommandPatterns.forEach(({ regex, msg }) => {
        if ((event.tool === 'shell' || event.tool === 'bash') && regex.test(command)) {
          throw new Error(msg);
        }
      });
    });
  },
});
