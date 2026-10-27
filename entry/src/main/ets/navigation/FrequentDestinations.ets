import { NavigationHistory, NavigationRecord } from './NavigationHistory';
import { navigationRecordCity } from './VisitedCities';

export interface FrequentDestination {
  key: string;
  name: string;
  address: string;
  city: string;
  visits: number;
  lastArrivedAt: number;
}

function normalized(value: string): string { return value.toLowerCase().replace(/\s+/g, ''); }

// Derive from existing local history; do not persist a second set of personal
// places or infer that a cancelled/unfinished navigation reached its destination.
export function frequentDestinations(records: NavigationRecord[]): FrequentDestination[] {
  const places: FrequentDestination[] = [];
  const seen: string[] = [];
  records.forEach((record: NavigationRecord) => {
    if (!NavigationHistory.valid(record) || record.status !== 'arrived' || seen.indexOf(record.id) >= 0) { return; }
    seen.push(record.id);
    const city = navigationRecordCity(record);
    // Exact name + city + address keeps branches and same-name cities separate.
    const key = JSON.stringify([normalized(record.destination), city, normalized(record.address)]);
    let place = places.find((item: FrequentDestination) => item.key === key);
    if (!place) {
      place = { key, name: record.destination.trim(), address: record.address.trim(), city,
        visits: 0, lastArrivedAt: 0 };
      places.push(place);
    }
    place.visits += 1;
    if (record.endedAt > place.lastArrivedAt) {
      place.name = record.destination.trim(); place.address = record.address.trim();
      place.lastArrivedAt = record.endedAt;
    }
  });
  return places.sort((a: FrequentDestination, b: FrequentDestination) => b.visits - a.visits ||
    b.lastArrivedAt - a.lastArrivedAt || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)).slice(0, 5);
}

export function frequentDestinationQuery(place: FrequentDestination): string {
  return (place.city ? place.city + ' ' : '') + place.name;
}
