import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

// Also prepare defaults for builds launched directly from DevEco Studio.
execFileSync(process.execPath, [join(__dirname, 'scripts/prepare-local-config.cjs')], { stdio: 'inherit' });

export default {
  system: appTasks,
  plugins: []
};
