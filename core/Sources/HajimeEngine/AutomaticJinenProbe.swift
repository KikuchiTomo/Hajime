/// Jinen モデルを「自動」にしたときの測定の途中の状態(AzooKeyConverterEngine.advanceAutomaticJinenDecision)．
/// 打鍵の合間に 1 歩ずつ進めるので，測ることを 1 歩ずつの単位(units)に分けて持つ
@MainActor
final class AutomaticJinenProbe {
    enum Unit {
        /// 文を変換する(打っているあいだに求め終えるので数えない)．続けて，その文節ごとの変換を測る
        case sentence(String)
        /// 文節を変換する(Zenzai だけの 1 歩として数える)
        case clause(String)
        /// jinen の大きさを試し始める(モデルを読むのは最初の合議の歩)
        case begin(JinenModel.Variant)
        /// 合議を 1 歩進める．その読みの合議を終えるまで先頭に残る．counted が false なら数えない(モデルの準備を含む 1 文目)
        case fusion(String, counted: Bool)
        /// 試した大きさの合議の 1 歩の p95 で決める
        case judge(JinenModel.Variant)
    }

    /// 測るための変換のセッション(入力に使うセッションと状態を混ぜない)
    let session: AzooKeyConverterSession
    var units: [Unit]
    /// まだ試していない大きさ(small から順に)
    private(set) var variants: [JinenModel.Variant]
    /// 試している大きさ
    private(set) var variant: JinenModel.Variant?
    var zenzaiTimes: [Duration] = []
    var fusionTimes: [Duration] = []
    private let readings: [String]
    private let warmUpReading: String

    init(session: AzooKeyConverterSession, readings: [String], warmUpReading: String, variants: [JinenModel.Variant]) {
        self.session = session
        self.readings = readings
        self.warmUpReading = warmUpReading
        self.variants = variants
        units = readings.map(Unit.sentence)
        planNextVariant()
    }

    /// 次の大きさを試す単位を足す．試す大きさが無ければ何も足さない(単位が尽きたら使わないに決まる)
    func planNextVariant() {
        guard !variants.isEmpty else { return }
        let next = variants.removeFirst()
        units += [.begin(next), .fusion(warmUpReading, counted: false)] + readings.map { .fusion($0, counted: true) } + [.judge(next)]
    }

    /// 大きさを試し始める．前の大きさの合議の結果と時間を捨てる
    func begin(_ variant: JinenModel.Variant) {
        self.variant = variant
        fusionTimes = []
        session.resetFusion()
    }
}
