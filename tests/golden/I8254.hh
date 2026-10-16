/*
 * Copyright (c) 2008 The Regents of The University of Michigan
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met: redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer;
 * redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution;
 * neither the name of the copyright holders nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#pragma once

#include <algorithm>
#include <array>
#include <cassert>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include "base/logging.hh"
#include "dev/io_device.hh"
#include "mem/packet_access.hh"
#include "params/I8254.hh"
#include "sim/serialize.hh"
#include "dev/intpin.hh"
#include "dev/intel_8254_timer.hh"

namespace protea {
    #ifndef PROTEA_PLOD_BIT_HELPERS
    #define PROTEA_PLOD_BIT_HELPERS
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
#endif
}

#ifndef PROTEA_PLOD_COLLECTION_HELPERS
#define PROTEA_PLOD_COLLECTION_HELPERS
namespace protea {
    template <typename M> auto firstKey(const M& m) { return m.begin()->first; }
    template <typename M> auto firstValue(const M& m) { return m.begin()->second; }
    template <typename M> void eraseFirst(M& m) { m.erase(m.begin()); }
    template <typename C> uint32_t loadWord(C& cp, const std::string& key) {
        uint32_t value; paramIn(cp, key, value); return value;
    }
    template <typename C> uint64_t loadTick(C& cp, const std::string& key) {
        uint64_t value; paramIn(cp, key, value); return value;
    }
    template <typename P> bool isAtomicSwap(P* pkt) {
        return pkt->isAtomicOp() && pkt->cmd == gem5::MemCmd::SwapReq;
    }
    template <typename P> void applyAtomic(P* pkt) {
        (*(pkt->getAtomicOp()))(pkt->template getPtr<uint8_t>());
    }
}
#endif

namespace gem5::X86ISA {
// Connect the shared PIT engine's virtual hook to a PLOD callback.
class CallbackIntel8254Timer : public Intel8254Timer {
    std::function<void(unsigned)> callback;
    void counterInterrupt(unsigned num) override { callback(num); }
  public:
    CallbackIntel8254Timer(EventManager* owner, const std::string& name,
                          std::function<void(unsigned)> cb)
        : Intel8254Timer(owner, name), callback(std::move(cb)) {}
};


class I8254 : public BasicPioDevice {
    std::function<void(uint32_t)> lambda_0 = [this](uint32_t num) {
        counterInterrupt(num);
    };

    uint64_t latency;
    std::function<void(uint32_t)> counterCallback = lambda_0;
    CallbackIntel8254Timer pit;
    std::vector<IntSourcePinBase*> intPin;

    std::array<uint8_t, 3> counter;
    uint8_t control = 0;


    uint8_t counter_read(uint64_t cid) {
        return pit.readCounter(static_cast<uint32_t>(cid));
    }

    void counter_write(uint8_t data, uint64_t cid) {
        pit.writeCounter(static_cast<uint32_t>(cid), data);
    }

    uint8_t control_read() {
        return 255;
    }

    void control_write(uint8_t data) {
        pit.writeControl(data);
    }

    public:

    using Params = I8254Params;
    void counterInterrupt(uint32_t num) {
        if ((num == 0)) {
            for (int i = 0; i < intPin.size(); ++i) {
                intPin[i]->raise();
                intPin[i]->lower();
            }
        }
    }

    bool outputHigh(uint32_t num) {
        return pit.outputHigh(num);
    }

    uint8_t readCounter(uint32_t num) {
        return pit.readCounter(num);
    }

    void writeCounter(uint32_t num, uint8_t data) {
        pit.writeCounter(num, data);
    }

    void writeControl(uint8_t data) {
        pit.writeControl(data);
    }

    void startup() {
        pit.startup();
    }

    I8254(const I8254Params &params)
        : BasicPioDevice(params, 4), latency(params.pio_latency), pit(this, params.name, counterCallback) {
        for (int i = 0; i < params.port_int_pin_connection_count; ++i) {
            intPin.push_back(new IntSourcePinBase((((name() + ".int_pin[") + std::to_string(i)) + "]"), i, this));
        }
    }

    Tick read(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        assert(pkt->getSize() == 1);
        bool matched = false;
        if (!matched && ((daddr - 0) < 3 && (daddr - 0) % 1 == 0)) {
            matched = true;
            uint64_t cid = (daddr - 0) / 1;
            pkt->setLE<uint8_t>(counter_read(cid));
        }
        if (!matched && (daddr == 3)) {
            matched = true;
            pkt->setLE<uint8_t>(control_read());
        }
        panic_if(!matched, "Unhandled read address");
        pkt->makeAtomicResponse();
        return this->latency;
    }

    Tick write(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        assert(pkt->getSize() == 1);
        bool matched = false;
        if (!matched && ((daddr - 0) < 3 && (daddr - 0) % 1 == 0)) {
            matched = true;
            uint64_t cid = (daddr - 0) / 1;
            counter_write(pkt->getLE<uint8_t>(), cid);
        }
        if (!matched && (daddr == 3)) {
            matched = true;
            control_write(pkt->getLE<uint8_t>());
        }
        panic_if(!matched, "Unhandled write address");
        pkt->makeAtomicResponse();
        return this->latency;
    }

    AddrRangeList getAddrRanges() const
    {
        AddrRangeList ranges;
        ranges.push_back(RangeSize(pioAddr, pioSize));
        return ranges;
    }

    void serialize(CheckpointOut& cp) const override {
        this->pit.serialize("pit", cp);
    }

    void unserialize(CheckpointIn& cp) override {
        this->pit.unserialize("pit", cp);
    }


    Port &getPort(const std::string &if_name, PortID idx=InvalidPortID)
    {
        if (if_name == "int_pin") return *intPin.at(idx);
        return BasicPioDevice::getPort(if_name, idx);
    }

    void init()
    {
        BasicPioDevice::init();
    }
};

}
