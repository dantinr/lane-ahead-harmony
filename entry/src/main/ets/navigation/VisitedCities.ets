import { NavigationHistory, NavigationRecord } from './NavigationHistory';
import { SEARCH_CITIES } from './SearchCities';

export function knownSearchCity(value: string): string {
  const name = value.trim();
  const entry = SEARCH_CITIES.find((item: string) => {
    const city = item.split(':')[0];
    return name === city || (city.endsWith('市') && name === city.slice(0, -1));
  });
  return entry ? entry.split(':')[0] : '';
}

function cityFromAddress(value: string): string {
  // Older records have only an address. Accept an administrative prefix, never
  // a city-like word inside a street, business name or arbitrary destination.
  const address = value.trim().replace(
    /^(?:[^省]{2,6}省|内蒙古自治区|广西壮族自治区|西藏自治区|宁夏回族自治区|新疆维吾尔自治区)\s*/, '');
  const entry = SEARCH_CITIES.find((item: string) => address.startsWith(item.split(':')[0]));
  return entry ? entry.split(':')[0] : '';
}

export function navigationRecordCity(record: NavigationRecord): string {
  return knownSearchCity(record.city || '') || cityFromAddress(record.address);
}

export function visitedSearchCities(records: NavigationRecord[]): string[] {
  const cities: string[] = [];
  records.filter((record: NavigationRecord) => NavigationHistory.valid(record) && record.status === 'arrived')
    .sort((a: NavigationRecord, b: NavigationRecord) => b.endedAt - a.endedAt)
    .forEach((record: NavigationRecord) => {
      const city = navigationRecordCity(record);
      if (city && cities.indexOf(city) < 0) { cities.push(city); }
    });
  return cities;
}
