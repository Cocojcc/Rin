import Darwin
import Foundation

final class CPUReader {
    private var previous: [[UInt32]] = []

    func read() -> CPUSample {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUSample() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(count))
        for core in 0..<Int(count) {
            var ticks = [UInt32](repeating: 0, count: states)
            for s in 0..<states { ticks[s] = UInt32(bitPattern: info[core * states + s]) }
            current.append(ticks)
        }

        var sample = CPUSample()
        sample.coreKinds = SystemInfo.coreKinds.count == current.count
            ? SystemInfo.coreKinds
            : [CoreKind](repeating: .performance, count: current.count)

        if previous.count == current.count {
            var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
            var perCore: [Double] = [], perUser: [Double] = [], perSystem: [Double] = []
            for (now, before) in zip(current, previous) {
                let u = UInt64(now[Int(CPU_STATE_USER)] &- before[Int(CPU_STATE_USER)])
                let s = UInt64(now[Int(CPU_STATE_SYSTEM)] &- before[Int(CPU_STATE_SYSTEM)])
                let i = UInt64(now[Int(CPU_STATE_IDLE)] &- before[Int(CPU_STATE_IDLE)])
                let n = UInt64(now[Int(CPU_STATE_NICE)] &- before[Int(CPU_STATE_NICE)])
                user += u; system += s; idle += i; nice += n
                let total = u + s + i + n
                perCore.append(total > 0 ? Double(u + s + n) / Double(total) : 0)
                perUser.append(total > 0 ? Double(u + n) / Double(total) : 0)
                perSystem.append(total > 0 ? Double(s) / Double(total) : 0)
            }
            let total = user + system + idle + nice
            if total > 0 {
                sample.user = Double(user + nice) / Double(total)
                sample.system = Double(system) / Double(total)
                sample.total = sample.user + sample.system
            }
            sample.perCore = perCore
            sample.perCoreUser = perUser
            sample.perCoreSystem = perSystem
        } else {
            sample.perCore = [Double](repeating: 0, count: current.count)
        }
        previous = current

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { sample.load = (loads[0], loads[1], loads[2]) }
        return sample
    }
}
