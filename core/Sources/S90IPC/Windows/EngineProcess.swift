#if os(Windows)
import WinSDK

/// エンジンのプロセスの扱い(Windows)
public enum EngineProcess {
    /// 変換は打鍵ごとに CPU を使い，Zenzai は何本ものスレッドで推論してそろうのを待つ．窓の無いプロセスは Windows に
    /// 省電力(EcoQoS)の扱いを受けやすく，速さの違うコアを混ぜた CPU では遅いコアに回されて 1 キーが延びる．
    /// 省電力の扱いから外し，速さを優先してもらう
    public static func requestFullExecutionSpeed() {
        var state = PROCESS_POWER_THROTTLING_STATE()
        state.Version = ULONG(PROCESS_POWER_THROTTLING_CURRENT_VERSION)
        state.ControlMask = ULONG(PROCESS_POWER_THROTTLING_EXECUTION_SPEED)
        state.StateMask = 0
        _ = SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &state, DWORD(MemoryLayout<PROCESS_POWER_THROTTLING_STATE>.size))
    }
}
#endif
