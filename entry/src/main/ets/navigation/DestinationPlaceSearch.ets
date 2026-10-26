import { AMapRouteService, Place } from './RoutePlanning';
import { resolvePlaceSearch } from './SearchScope';
import { knownSearchCity } from './VisitedCities';

export interface DestinationPlaceSearchOptions {
  query: string;
  city: string;
  visitedCities: string[];
  allowFallback: boolean;
  previousDestinations?: string[];
}

export interface DestinationPlaceSearchResult {
  places: Place[];
  city: string;
  explicitCity: boolean;
  usedVisitedCity: boolean;
  checkedVisitedCities: number;
  matchedByName: boolean;
  warning: string;
}

function normalizedName(value: string): string { return value.toLowerCase().replace(/\s+/g, ''); }

function nameMatch(place: Place, keyword: string): number {
  const name = normalizedName(place.name);
  const query = normalizedName(keyword);
  return name === query ? 2 : name.indexOf(query) >= 0 ? 1 : 0;
}

function rankedPlaces(places: Place[], keyword: string, previous: string[]): Place[] {
  const visited = previous.map((name: string) => normalizedName(name));
  return places.slice().sort((a: Place, b: Place) => nameMatch(b, keyword) - nameMatch(a, keyword) ||
    Number(visited.indexOf(normalizedName(b.name)) >= 0) - Number(visited.indexOf(normalizedName(a.name)) >= 0));
}

// A successful response can contain only loosely related POIs. Widen the scope
// until a name matches, while keeping the current city's related results as a
// fallback. Check cancellation before and after every city request.
export async function searchDestinationPlaces(service: AMapRouteService,
  options: DestinationPlaceSearchOptions, isCurrent: () => boolean,
  onFallback: (city: string) => void): Promise<DestinationPlaceSearchResult | undefined> {
  if (!isCurrent()) { return undefined; }
  const scope = resolvePlaceSearch(options.query, options.city);
  const places = await service.search(options.query, options.city);
  if (!isCurrent()) { return undefined; }
  const previous = options.previousDestinations || [];
  const result: DestinationPlaceSearchResult = {
    places: rankedPlaces(places, scope.keyword, previous), city: scope.city, explicitCity: scope.explicitCity,
    usedVisitedCity: false, checkedVisitedCities: 0,
    matchedByName: places.some((place: Place) => nameMatch(place, scope.keyword) > 0), warning: ''
  };
  if (result.matchedByName || scope.explicitCity || !options.allowFallback) { return result; }
  const checked: string[] = [knownSearchCity(scope.city) || scope.city];
  for (let i = 0; i < options.visitedCities.length; i++) {
    const city = knownSearchCity(options.visitedCities[i]);
    if (!city || checked.indexOf(city) >= 0) { continue; }
    if (!isCurrent()) { return undefined; }
    checked.push(city);
    onFallback(city);
    if (!isCurrent()) { return undefined; }
    let matches: Place[];
    try { matches = await service.search(scope.keyword, city); } catch (error) {
      if (!isCurrent()) { return undefined; }
      if (result.places.length === 0) { throw new Error((error as Error).message || '搜索失败，请重试'); }
      result.warning = '去过城市查询未完成：' + ((error as Error).message || '搜索失败，请重试');
      return result;
    }
    if (!isCurrent()) { return undefined; }
    result.checkedVisitedCities += 1;
    const matchedByName = matches.some((place: Place) => nameMatch(place, scope.keyword) > 0);
    if (matchedByName || (result.places.length === 0 && matches.length > 0)) {
      result.places = rankedPlaces(matches, scope.keyword, previous);
      result.city = city;
      result.usedVisitedCity = true;
      result.matchedByName = matchedByName;
      if (matchedByName) { return result; }
    }
  }
  return result;
}
