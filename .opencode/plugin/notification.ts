import type { Plugin } from '@opencode-ai/plugin';
import notifier from 'node-notifier';
import path from 'path';

export const NotificationPlugin: Plugin = async () => {
  return {
    event: async ({ event }) => {
      // Send notification on session completion
      if (event.type === 'session.idle') {
        notifier.notify({
          title: 'OpenCode',
          message: 'All done!',
          // icon doesn't seem to work on macOS, but contentImage does (though
          // it's on the right side and in addition to the terminal icon)
          icon: path.join(__dirname, 'images/opencode.png'),
          contentImage: path.join(__dirname, 'images/opencode.png'),
          sound: true,
        });
      }
    },
  };
};
