import { AMapRouteService, Place } from './RoutePlanning';
import { resolvePlaceSearch } from './SearchScope';
import { knownSearchCity } from './VisitedCities';

export interface DestinationPlaceSearchOptions {
  query: string;
  city: string;
  visitedCities: string[];
  allowFallback: boolean;
}

export interface DestinationPlaceSearchResult {
  places: Place[];
  city: string;
  explicitCity: boolean;
  usedVisitedCity: boolean;
  checkedVisitedCities: number;
}

// Empty results may widen the scope; network, authorization and quota failures
// must propagate. Check cancellation before and after every city request.
export async function searchDestinationPlaces(service: AMapRouteService,
  options: DestinationPlaceSearchOptions, isCurrent: () => boolean,
  onFallback: (city: string) => void): Promise<DestinationPlaceSearchResult | undefined> {
  if (!isCurrent()) { return undefined; }
  const scope = resolvePlaceSearch(options.query, options.city);
  const places = await service.search(options.query, options.city);
  if (!isCurrent()) { return undefined; }
  const result: DestinationPlaceSearchResult = {
    places: places, city: scope.city, explicitCity: scope.explicitCity,
    usedVisitedCity: false, checkedVisitedCities: 0
  };
  if (places.length > 0 || scope.explicitCity || !options.allowFallback) { return result; }
  const checked: string[] = [knownSearchCity(scope.city) || scope.city];
  for (let i = 0; i < options.visitedCities.length; i++) {
    const city = knownSearchCity(options.visitedCities[i]);
    if (!city || checked.indexOf(city) >= 0) { continue; }
    if (!isCurrent()) { return undefined; }
    checked.push(city);
    onFallback(city);
    if (!isCurrent()) { return undefined; }
    const matches = await service.search(scope.keyword, city);
    if (!isCurrent()) { return undefined; }
    result.checkedVisitedCities += 1;
    if (matches.length > 0) {
      result.places = matches;
      result.city = city;
      result.usedVisitedCity = true;
      return result;
    }
  }
  return result;
}
