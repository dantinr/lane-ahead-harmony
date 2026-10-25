export class SearchCity {
  city: string = '';
  status: string = '定位后自动识别当前城市，也可手动填写';
  private revision: number = 0;
  private awaitingFix: boolean = false;

  begin(): void {
    this.revision += 1;
    this.awaitingFix = true;
    this.city = '';
    this.status = '正在识别当前城市…';
  }

  manual(city: string): void {
    this.cancel();
    this.city = city;
    this.status = city.trim() ? '已手动选择搜索城市，重新定位可恢复当前城市' : '请填写城市或点击重新定位';
  }

  cancel(): void { this.revision += 1; this.awaitingFix = false; }

  async located(longitude: number, latitude: number,
    lookup: (longitude: number, latitude: number) => Promise<string>): Promise<boolean> {
    if (!this.awaitingFix) { return false; }
    this.awaitingFix = false;
    const revision = this.revision;
    try {
      const city = await lookup(longitude, latitude);
      if (revision !== this.revision) { return false; }
      if (!city.trim()) { throw new Error('missing city'); }
      this.city = city;
      this.status = '当前城市：' + city;
    } catch {
      if (revision !== this.revision) { return false; }
      this.city = '';
      this.status = '未能识别当前城市，请重新定位或手动填写';
    }
    return true;
  }
}
