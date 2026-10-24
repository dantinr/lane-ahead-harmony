import { http } from '@kit.NetworkKit';
import { RouteTransport } from './RoutePlanning';

export class HttpRouteTransport implements RouteTransport {
  private active: http.HttpRequest[] = [];

  async get(url: string): Promise<string> {
    const request = http.createHttp();
    this.active.push(request);
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 15000,
        usingCache: false
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        throw new Error('地图服务响应异常');
      }
      return response.result;
    } catch {
      throw new Error('地图服务连接失败，请检查网络后重试');
    } finally {
      // cancelAll already destroys removed requests.
      if (this.active.includes(request)) {
        this.active = this.active.filter((item: http.HttpRequest) => item !== request);
        request.destroy();
      }
    }
  }

  cancelAll(): void {
    const requests = this.active;
    this.active = [];
    requests.forEach((request: http.HttpRequest) => request.destroy());
  }
}
