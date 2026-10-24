import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export class MapConfiguration {
  webKey: string = '';
  harmonyKey: string = '';
}

export function loadMapConfiguration(context: common.UIAbilityContext): MapConfiguration {
  try {
    const bytes = context.resourceManager.getRawFileContentSync('map-keys.json');
    const config = JSON.parse(util.TextDecoder.create('utf-8').decodeWithStream(bytes)) as MapConfiguration;
    if (/^[a-f0-9]{32}$/i.test(config.webKey) && /^[a-f0-9]{32}$/i.test(config.harmonyKey)) {
      return config;
    }
  } catch {
    // Never surface raw resources or parsing errors containing a key.
  }
  return new MapConfiguration();
}
