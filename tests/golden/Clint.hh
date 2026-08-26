#pragma once

#include "arch/riscv/system.hh"
#include "cpu/base.hh"
#include "mem/packet.hh"
#include "mem/packet_access.hh"
#include "sim/system.hh"
#include "arch/riscv/interrupts.hh"
#include "dev/intpin.hh"
#include "dev/io_device.hh"
#include "dev/mc146818.hh"
#include "dev/reg_bank.hh"

namespace protea {
    template <typename BVTD, typename BVTS>
    void _insert(BVTD& dest, uint32_t lsb, uint32_t size, BVTS src) {
        BVTD cleaner = ~((((BVTD)1 << size) - 1) << lsb);
        BVTD data = ((BVTD)src & (((BVTD)1 << size) - 1)) << lsb;
        dest &= cleaner;
        dest |= data;
    }
    
    template <typename BVT>
    BVT _extract(BVT op, uint32_t lsb, uint32_t size) {
        return (op >> lsb) & (((BVT)1 << size) - 1);
    }
}

namespace gem5 {

class Terminal;
class Platform;

class Clint : public BasicPioDevice {
    int int_rtc = 0;
    int int_reset = 1;
    int int_timer_machine = 7;
    int int_software_machine = 3;
    
    std::function<void(bool)> lambda_0 = [this](bool newVal) {
        if (newVal) {
            doReset();
        }
    };
    
    std::function<void(bool)> resetLambda = lambda_0;
    System* system;
    uint32_t nThread;
    IntSinkPinClint signal;
    SignalSinkPortBool reset;
    bool resetMtimecmp;
    uint64_t resetValue;
    
    std::array<uint32_t, 4096> msip;
    std::array<uint64_t, 4096> mtimecmp;
    uint64_t mtime = 0;
    
    
    void msip_write(uint32_t data, int cid) {
        msip[cid] = (data & 1);
        msip_update(cid);
    }
    
    uint32_t msip_read(int cid) {
        return msip[cid];
    }
    
    void msip_update(int cid) {
        ThreadContext* tc;
        tc = system->threads[cid];
        if (msip[cid]) {
            tc->getCpuPtr()->postInterrupt(tc->threadId(), int_software_machine, 0);
        } else {
            tc->getCpuPtr()->clearInterrupt(tc->threadId(), int_software_machine, 0);
        }
    }
    
    void mtimecmp_write(uint64_t data, int cid) {
        mtimecmp[cid] = data;
    }
    
    uint64_t mtimecmp_read(int cid) {
        return mtimecmp[cid];
    }
    
    uint64_t mtime_read() { return mtime; }
    
    void mtime_write(uint64_t data) { mtime = data; }
    
    public:
    
    void raiseInterruptPin(int id) {
        if ((id == int_rtc)) {
            mtime = (mtime + 1);
        }
        for (int cid = 0; cid < nThread; ++cid) {
            ThreadContext* tc;
            tc = system->threads[cid];
            uint64_t mtimecmpv;
            mtimecmpv = mtimecmp[cid];
            if ((mtime >= mtimecmpv)) {
                tc->getCpuPtr()->postInterrupt(tc->threadId(), int_timer_machine, 0);
            } else {
                tc->getCpuPtr()->clearInterrupt(tc->threadId(), int_timer_machine, 0);
            }
        }
    }
    
    void reg_init() {
        mtime = 0;
        for (int cid = 0; cid < 4096; ++cid) {
            msip[cid] = 0;
            mtimecmp[cid] = resetValue;
        }
    }
    
    void doReset() {
        mtime = 0;
        for (int cid = 0; cid < 4096; ++cid) {
            if (resetMtimecmp) {
                mtimecmp[cid] = resetValue;
            }
            msip[cid] = 0;
            msip_update(cid);
        }
        raiseInterruptPin(int_reset);
    }
    
    Clint(const ClintParams &params)
        : BasicPioDevice(params, params.pio_size), system(params.system), nThread(params.num_threads), signal((params.name + ".signal"), 0, this, int_rtc), reset((params.name + ".reset")), resetMtimecmp(params.reset_mtimecmp), resetValue(params.mtimecmp_reset_value) {
        reset.onChange(resetLambda);
    }
    
    Tick read(PacketPtr pkt) override {
        uint64_t daddr = pkt->getAddr() - pioAddr;
        uint8_t* data_ptr = pkt->getPtr<uint8_t>();
        
        if (0 <= daddr && daddr < 0 + 16384) {
            uint64_t cid = (daddr - 0) / 4;
            uint32_t read_data = msip_read(cid);
            std::memcpy(data_ptr, &read_data, 4);
        }
        if (16384 <= daddr && daddr < 16384 + 32768) {
            uint64_t cid = (daddr - 16384) / 8;
            uint64_t read_data = mtimecmp_read(cid);
            std::memcpy(data_ptr, &read_data, 8);
        }
        if (49144 <= daddr && daddr < 49144 + 8) {
            uint64_t read_data = mtime_read();
            std::memcpy(data_ptr, &read_data, 8);
        }
        
        bool is_atomic = pkt->isAtomicOp() && pkt->cmd == MemCmd::SwapReq;
        
        if (is_atomic) {
            (*(pkt->getAtomicOp()))(pkt->getPtr<uint8_t>());
            return write(pkt);
        } else {
            pkt->makeResponse();
            return pioDelay;
        }
    }
    
    Tick write(PacketPtr pkt) {
        Addr daddr = pkt->getAddr() - pioAddr;
        uint8_t* data_ptr = pkt->getPtr<uint8_t>();
        
        if (0 <= daddr && daddr < 0 + 16384) {
            uint32_t write_data;
            std::memcpy(&write_data, data_ptr, 4);
            uint64_t cid = (daddr - 0) / 4;
            msip_write(write_data, cid);
        }
        if (16384 <= daddr && daddr < 16384 + 32768) {
            uint64_t write_data;
            std::memcpy(&write_data, data_ptr, 8);
            uint64_t cid = (daddr - 16384) / 8;
            mtimecmp_write(write_data, cid);
        }
        if (49144 <= daddr && daddr < 49144 + 8) {
            uint64_t write_data;
            std::memcpy(&write_data, data_ptr, 8);
            mtime_write(write_data);
        }
        
        pkt->makeResponse();
        return pioDelay;
    }
    
    AddrRangeList getAddrRanges() const
    {
        AddrRangeList ranges;
        ranges.push_back(RangeSize(pioAddr, pioSize));
        return ranges;
    }
    
    void serialize(CheckpointOut &cp) const override {}
    void unserialize(CheckpointIn &cp) override {}
    
    Port &getPort(const std::string &if_name, PortID idx)
    {
        if (if_name == "int_pin")
        return signal;
        else if (if_name == "reset")
        return reset;
        else
        return BasicPioDevice::getPort(if_name, idx);
    }
    
    void init()
    {
        reg_init();
        BasicPioDevice::init();
        
        RiscvSystem *rv_sys = dynamic_cast<RiscvSystem *>(system);
        if (rv_sys != nullptr) {
        rv_sys->setClint(this);
        } else {
        warn("Set Clint to RiscvSystem failed.");
        }
    }
};

}
