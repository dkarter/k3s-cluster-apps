# OpenCode Plugins

To install dependencies:

```bash
bun install
```

## Debugging Plugins

```typescript
import { appendFile } from 'node:fs';

// debug logging, uncomment when developing
appendFile(
  __dirname + '/debug.log',
  JSON.stringify({ input, output }, undefined, 2),
  'utf8',
  () => {},
);
```
