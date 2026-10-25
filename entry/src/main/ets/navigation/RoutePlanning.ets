import { resolvePlaceSearch } from './SearchScope';

// A planning step is NOT a physical junction. Keep it separate from Guidance.Junction.
export class Place {
  id: string;
  name: string;
  address: string;
  location: string;

  constructor(id: string, name: string, address: string, location: string) {
    const coords: string[] = location.split(',');
    if (coords.length !== 2 || coords.some((value: string) => value.trim().length === 0) ||
      !Number.isFinite(Number(coords[0])) || !Number.isFinite(Number(coords[1])) ||
      Math.abs(Number(coords[0])) > 180 || Math.abs(Number(coords[1])) > 90 ||
      name.trim().length === 0) {
      throw new Error('地点坐标或名称无效，请重新选择地点');
    }
    this.id = id;
    this.name = name;
    this.address = address;
    // AMap search and driving both use GCJ-02; never mix these with raw GPS coordinates.
    this.location = Number(coords[0]).toFixed(6) + ',' + Number(coords[1]).toFixed(6);
  }
}

export class PlanningStep {
  instruction: string;
  road: string;
  distanceMeters: number;

  constructor(instruction: string, road: string, distanceMeters: number) {
    this.instruction = instruction;
    this.road = road;
    this.distanceMeters = distanceMeters;
  }
}

export class PlannedRoute {
  id: string;
  destination: string;
  distanceMeters: number;
  durationSeconds: number | undefined;
  steps: PlanningStep[];

  constructor(id: string, destination: string, distanceMeters: number,
    durationSeconds: number | undefined, steps: PlanningStep[]) {
    this.id = id;
    this.destination = destination;
    this.distanceMeters = distanceMeters;
    this.durationSeconds = durationSeconds;
    this.steps = steps;
  }
}

interface AMapResponse {
  status: string;
  infocode?: string;
}

interface AMapPoi {
  id?: string;
  name?: string;
  address?: string | string[];
  location?: string;
  pname?: string | string[];
  cityname?: string | string[];
  adname?: string | string[];
}

interface AMapSearchResponse extends AMapResponse {
  pois?: AMapPoi[];
}

interface AddressComponent {
  city?: string | string[];
  province?: string | string[];
}

interface ReverseAddress {
  addressComponent?: AddressComponent;
}

interface AMapCityResponse extends AMapResponse {
  regeocode?: ReverseAddress;
}

interface AMapCost {
  duration?: string | number;
}

interface AMapStep {
  instruction?: string;
  road_name?: string;
  step_distance?: string | number;
}

interface AMapPath {
  distance?: string | number;
  cost?: AMapCost;
  steps?: AMapStep[];
}

interface AMapRouteData {
  paths?: AMapPath[];
}

interface AMapDrivingResponse extends AMapResponse {
  route?: AMapRouteData;
}

function checkResponse(response: AMapResponse): void {
  if (response === null || typeof response !== 'object') {
    throw new Error('地图服务返回格式异常，请重试');
  }
  if (response.status !== '1') {
    // Never echo arbitrary server text, request URLs, or keys into the UI or logs.
    switch (response.infocode) {
      case '10001':
      case '10002':
      case '10005':
      case '10006':
      case '10007':
      case '10008':
      case '10009':
      case '10012':
      case '10013':
        throw new Error('地图密钥或访问权限有误，请检查 Web 服务 Key 的配置');
      case '10003':
      case '10004':
      case '10010':
      case '10014':
      case '10019':
      case '10020':
      case '10021':
        throw new Error('地图服务调用次数受限，请稍后再试');
      default:
        throw new Error('地图服务未能完成请求，请检查地点或稍后重试');
    }
  }
}

function nonnegativeNumber(value: string | number | undefined): number | undefined {
  if ((typeof value !== 'string' && typeof value !== 'number') ||
    (typeof value === 'string' && value.trim().length === 0)) {
    return undefined;
  }
  const number: number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : undefined;
}

export function decodeCity(body: string): string {
  let response: AMapCityResponse;
  try { response = JSON.parse(body) as AMapCityResponse; } catch {
    throw new Error('城市信息返回格式异常，请重新定位');
  }
  checkResponse(response);
  const component = response.regeocode?.addressComponent;
  const city = typeof component?.city === 'string' ? component.city.trim() : '';
  if (city && city.length <= 80) { return city; }
  const province = typeof component?.province === 'string' ? component.province.trim() : '';
  if (['北京市', '上海市', '天津市', '重庆市'].indexOf(province) >= 0) { return province; }
  throw new Error('未能识别当前城市，请重新定位或手动填写');
}

export function decodePlaces(body: string): Place[] {
  let response: AMapSearchResponse;
  try {
    response = JSON.parse(body) as AMapSearchResponse;
  } catch {
    throw new Error('地图服务返回格式异常，请重试');
  }
  checkResponse(response);
  if (!Array.isArray(response.pois)) {
    throw new Error('地图服务未返回有效地点列表，请重试');
  }
  const result: Place[] = [];
  response.pois.forEach((poi: AMapPoi) => {
    if (poi === null || typeof poi.name !== 'string' || typeof poi.location !== 'string') {
      return;
    }
    try {
      const city = typeof poi.cityname === 'string' && poi.cityname ? poi.cityname :
        typeof poi.pname === 'string' ? poi.pname : '';
      const district = typeof poi.adname === 'string' && poi.adname !== city ? poi.adname : '';
      const region = city + district;
      const address = typeof poi.address === 'string' ? poi.address : '';
      const displayAddress = region && address && !address.startsWith(region) ? region + ' · ' + address :
        address || region;
      const place = new Place(typeof poi.id === 'string' ? poi.id : '', poi.name, displayAddress, poi.location);
      if (!result.some((existing: Place) => existing.id === place.id &&
        existing.location === place.location)) {
        result.push(place);
      }
    } catch {
      // POIs without routable coordinates are not selectable.
    }
  });
  return result;
}

export function decodeRoutes(body: string, destination: string, requestId: string): PlannedRoute[] {
  let response: AMapDrivingResponse;
  try {
    response = JSON.parse(body) as AMapDrivingResponse;
  } catch {
    throw new Error('地图服务返回格式异常，请重试');
  }
  checkResponse(response);
  if (!response.route || !Array.isArray(response.route.paths)) {
    throw new Error('地图服务未返回有效路线列表，请重试');
  }
  const routes: PlannedRoute[] = [];
  response.route.paths.forEach((path: AMapPath, index: number) => {
    if (path === null) {
      throw new Error('地图服务返回路线格式异常');
    }
    const distance = nonnegativeNumber(path.distance);
    if (distance === undefined || distance === 0 || !Array.isArray(path.steps)) {
      throw new Error('地图服务返回路线距离或分段异常');
    }
    const steps: PlanningStep[] = path.steps.map((step: AMapStep) => {
      if (step === null) {
        throw new Error('地图服务返回路线分段异常');
      }
      const stepDistance = nonnegativeNumber(step.step_distance);
      if (stepDistance === undefined || typeof step.instruction !== 'string') {
        throw new Error('地图服务返回路线分段异常');
      }
      return new PlanningStep(step.instruction,
        typeof step.road_name === 'string' ? step.road_name : '', stepDistance);
    });
    routes.push(new PlannedRoute('amap-' + requestId + '-' + index, destination,
      distance, path.cost ? nonnegativeNumber(path.cost.duration) : undefined, steps));
  });
  return routes;
}

export interface RouteTransport {
  get(url: string): Promise<string>;
}

export class AMapRouteService {
  private transport: RouteTransport;
  private key: string;
  private sequence: number = 0;

  constructor(transport: RouteTransport, key: string) {
    if (!/^[a-fA-F0-9]{32}$/.test(key.trim())) {
      throw new Error('请填写 32 位高德 Web 服务 Key');
    }
    this.transport = transport;
    this.key = key.trim();
  }

  async search(keyword: string, city: string): Promise<Place[]> {
    const scope = resolvePlaceSearch(keyword, city);
    const url: string = 'https://restapi.amap.com/v5/place/text?key=' + encodeURIComponent(this.key) +
      '&keywords=' + encodeURIComponent(scope.keyword) + '&region=' + encodeURIComponent(scope.region) +
      '&city_limit=true&page_size=10&page_num=1';
    return decodePlaces(await this.transport.get(url));
  }

  async cityAt(longitude: number, latitude: number): Promise<string> {
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude) || Math.abs(longitude) > 180 ||
      Math.abs(latitude) > 90 || (longitude === 0 && latitude === 0)) {
      throw new Error('定位坐标无效，请重新定位');
    }
    // Coordinates come from the map SDK's GCJ-02 location source, not system GPS.
    const location = longitude.toFixed(6) + ',' + latitude.toFixed(6);
    const url = 'https://restapi.amap.com/v3/geocode/regeo?key=' + encodeURIComponent(this.key) +
      '&location=' + encodeURIComponent(location) + '&extensions=base&output=JSON';
    return decodeCity(await this.transport.get(url));
  }

  async plan(origin: Place, destination: Place): Promise<PlannedRoute[]> {
    if (origin.location === destination.location) {
      throw new Error('起点和终点相同，请选择不同地点');
    }
    this.sequence += 1;
    const requestId: string = Date.now() + '-' + this.sequence;
    const url: string = 'https://restapi.amap.com/v5/direction/driving?key=' + encodeURIComponent(this.key) +
      '&origin=' + encodeURIComponent(origin.location) + '&destination=' + encodeURIComponent(destination.location) +
      '&origin_id=' + encodeURIComponent(origin.id) + '&destination_id=' + encodeURIComponent(destination.id) +
      '&strategy=32&show_fields=cost';
    return decodeRoutes(await this.transport.get(url), destination.name, requestId);
  }
}
