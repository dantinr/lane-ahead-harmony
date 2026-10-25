// The native bridge can preserve a 64-bit integer as bigint despite the SDK's
// number declaration. Never convert a native ID to Number: adjacent IDs can collide.
export function exactRouteId(value: number | bigint | string): string {
  if (typeof value === 'number') {
    return Number.isSafeInteger(value) && value >= 0 ? value.toString() : '';
  }
  if (typeof value !== 'bigint' && typeof value !== 'string') { return ''; }
  const text = value.toString();
  return /^(0|[1-9]\d{0,39})$/.test(text) ? text : '';
}
