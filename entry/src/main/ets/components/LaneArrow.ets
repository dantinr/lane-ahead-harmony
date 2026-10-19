import { Lane, Turn } from '../navigation/Guidance';

@Component
export struct LaneArrow {
  @Prop lane: Lane = new Lane([Turn.STRAIGHT]);
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private branch(turn: Turn, color: string): void {
    const ctx = this.context;
    ctx.strokeStyle = color;
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(24, 49);
    if (turn === Turn.STRAIGHT) {
      ctx.lineTo(24, 12);
      ctx.moveTo(17, 20);
      ctx.lineTo(24, 12);
      ctx.lineTo(31, 20);
    } else if (turn === Turn.LEFT) {
      ctx.lineTo(24, 28);
      ctx.quadraticCurveTo(24, 21, 17, 21);
      ctx.lineTo(8, 21);
      ctx.moveTo(15, 14);
      ctx.lineTo(8, 21);
      ctx.lineTo(15, 28);
    } else if (turn === Turn.RIGHT) {
      ctx.lineTo(24, 28);
      ctx.quadraticCurveTo(24, 21, 31, 21);
      ctx.lineTo(40, 21);
      ctx.moveTo(33, 14);
      ctx.lineTo(40, 21);
      ctx.lineTo(33, 28);
    } else {
      ctx.lineTo(24, 23);
      ctx.bezierCurveTo(24, 9, 8, 9, 8, 23);
      ctx.lineTo(8, 31);
      ctx.moveTo(2, 24);
      ctx.lineTo(8, 31);
      ctx.lineTo(14, 24);
    }
    ctx.stroke();
  }

  private paint(): void {
    this.context.clearRect(0, 0, 48, 60);
    this.lane.directions.forEach((turn: Turn) => this.branch(turn, '#719184'));
    // Highlight the recommended branch, not every arrow in a mixed-direction lane.
    this.lane.recommendedDirections.forEach((turn: Turn) => this.branch(turn, '#B5F489'));
  }

  build() {
    Column({ space: 2 }) {
      Canvas(this.context)
        .width(48)
        .height(60)
        .onReady(() => this.paint())
      Text(this.lane.recommendedDirections.length > 0 ? '推荐' : ' ')
        .fontSize(10)
        .fontColor('#B5F489')
    }
    .width(56)
    .padding({ top: 2, bottom: 5 })
    .borderRadius(10)
    .backgroundColor(this.lane.recommendedDirections.length > 0 ? '#284B35' : '#142B23')
    .accessibilityText(this.lane.directions.join('、') +
      (this.lane.recommendedDirections.length > 0 ? '，推荐' + this.lane.recommendedDirections.join('、') : ''))
  }
}
