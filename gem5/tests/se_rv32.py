# Mini RV32 SE config
# Usage: gem5.opt se_rv32.py <atomic|timing|minor|o3> <binary> [max_insts]
import sys
import m5
from m5.objects import *

cpu_cls = {"atomic": RiscvAtomicSimpleCPU, "timing": RiscvTimingSimpleCPU,
           "minor": RiscvMinorCPU, "o3": RiscvO3CPU}[sys.argv[1]]
binary = sys.argv[2]

system = System()
system.clk_domain = SrcClockDomain(clock="1GHz", voltage_domain=VoltageDomain())
system.mem_mode = "atomic" if sys.argv[1] == "atomic" else "timing"
system.mem_ranges = [AddrRange("512MB")]
system.cpu = cpu_cls()
system.cpu.isa = [RiscvISA(riscv_type="RV32", enable_rvv=False)]
system.cpu.max_insts_any_thread = int(sys.argv[3]) if len(sys.argv) > 3 else 0
system.membus = SystemXBar()
system.cpu.icache_port = system.membus.cpu_side_ports
system.cpu.dcache_port = system.membus.cpu_side_ports
system.cpu.createInterruptController()
system.mem_ctrl = MemCtrl(dram=DDR3_1600_8x8(range=system.mem_ranges[0]))
system.mem_ctrl.port = system.membus.mem_side_ports
system.system_port = system.membus.cpu_side_ports

system.workload = SEWorkload.init_compatible(binary)
process = Process(cmd=[binary])
system.cpu.workload = process
system.cpu.createThreads()

root = Root(full_system=False, system=system)
m5.instantiate()
ev = m5.simulate()
print("EXIT:", ev.getCause(), ev.getCode())
