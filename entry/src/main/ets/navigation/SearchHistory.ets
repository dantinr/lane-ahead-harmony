export class SearchRecord {
  query: string;
  searchedAt: number;
  constructor(query: string, searchedAt: number) { this.query = query; this.searchedAt = searchedAt; }
}

class SearchHistoryFile {
  version: number = 1;
  records: SearchRecord[] = [];
}

export class SearchHistory {
  static readonly LIMIT: number = 20;
  records: SearchRecord[] = [];

  remember(query: string, now: number = Date.now()): void {
    const text = query.trim().replace(/\s+/g, ' ');
    if (!text || text.length > 120 || !Number.isSafeInteger(now) || now <= 0) { return; }
    this.records = this.records.filter((record: SearchRecord) => record.query.toLowerCase() !== text.toLowerCase());
    this.records.unshift(new SearchRecord(text, now));
    this.records = this.records.slice(0, SearchHistory.LIMIT);
  }

  remove(query: string): void {
    this.records = this.records.filter((record: SearchRecord) => record.query !== query);
  }

  restore(text: string): boolean {
    try {
      if (text.length > 64000) { return false; }
      const file = JSON.parse(text) as SearchHistoryFile;
      if (!file || file.version !== 1 || !Array.isArray(file.records) || file.records.length > SearchHistory.LIMIT ||
        !file.records.every((record: SearchRecord) => record !== null && typeof record === 'object' &&
          typeof record.query === 'string' && record.query.length > 0 && record.query.length <= 120 &&
          record.query === record.query.trim().replace(/\s+/g, ' ') &&
          Number.isSafeInteger(record.searchedAt) && record.searchedAt > 0)) { return false; }
      const names = file.records.map((record: SearchRecord) => record.query.toLowerCase());
      if (names.some((name: string, index: number) => names.indexOf(name) !== index)) { return false; }
      this.records = file.records.map((record: SearchRecord) => new SearchRecord(record.query, record.searchedAt))
        .sort((a: SearchRecord, b: SearchRecord) => b.searchedAt - a.searchedAt);
      return true;
    } catch { return false; }
  }

  serialize(): string {
    const file = new SearchHistoryFile(); file.records = this.records;
    return JSON.stringify(file);
  }
}
