import { SEARCH_CITIES } from './SearchCities';

export interface PlaceSearchScope {
  keyword: string;
  city: string;
  region: string;
  explicitCity: boolean;
}

// A short city name needs a separator: 北京路、南京饭店 are ordinary POI names.
// A complete administrative name can be joined directly: 北京市望京花园.
export function resolvePlaceSearch(query: string, defaultCity: string): PlaceSearchScope {
  const keyword = query.trim().replace(/\s+/g, ' ');
  if (!keyword) { throw new Error('请输入地点名称或地址'); }
  let matchedName = '';
  let matchedRegion = '';
  let matchedPrefix = '';
  SEARCH_CITIES.forEach((entry: string) => {
    const parts = entry.split(':');
    const name = parts[0];
    const shortName = name.endsWith('市') ? name.slice(0, -1) : name;
    let prefix = '';
    if (keyword.startsWith(name)) { prefix = name; }
    else if (keyword === shortName || keyword.startsWith(shortName + ' ')) { prefix = shortName; }
    if (prefix.length > matchedPrefix.length) {
      matchedName = name;
      matchedRegion = parts[1];
      matchedPrefix = prefix;
    }
  });
  if (matchedPrefix) {
    return {
      keyword: keyword.slice(matchedPrefix.length).trim() || matchedName,
      city: matchedName, region: matchedRegion, explicitCity: true
    };
  }
  const city = defaultCity.trim();
  if (!city) { throw new Error('请填写搜索城市，或在关键词前加城市，如“北京 望京花园”'); }
  return { keyword, city, region: city, explicitCity: false };
}
