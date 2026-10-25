import { Place } from './RoutePlanning';

export interface SearchOrigin {
  longitude: number;
  latitude: number;
  receivedAt: number;
}

export interface DestinationSearchRequest {
  id: number;
  city: string;
  webKey: string;
  origin?: SearchOrigin;
}

// Transient page handoff. Keys and the selected coordinates never enter router parameters or storage.
export class DestinationSearchSession {
  private sequence: number = 0;
  private pending: DestinationSearchRequest | undefined = undefined;
  private selected: Place | undefined = undefined;

  begin(city: string, webKey: string, origin?: SearchOrigin): number {
    this.sequence += 1;
    this.pending = { id: this.sequence, city: city, webKey: webKey, origin: origin };
    this.selected = undefined;
    return this.sequence;
  }

  request(id: number): DestinationSearchRequest | undefined {
    return this.pending?.id === id ? this.pending : undefined;
  }

  select(id: number, place: Place): boolean {
    if (!this.request(id)) { return false; }
    this.selected = place;
    return true;
  }

  finish(id: number): Place | undefined {
    if (!this.request(id)) { return undefined; }
    const result = this.selected;
    this.pending = undefined;
    this.selected = undefined;
    return result;
  }
}

export const destinationSearchSession: DestinationSearchSession = new DestinationSearchSession();
