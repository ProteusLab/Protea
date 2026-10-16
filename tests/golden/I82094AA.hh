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
#include "params/I82094AA.hh"
#include "sim/serialize.hh"
#include "dev/intpin.hh"
#include "arch/x86/intmessage.hh"
#include "arch/x86/interrupts.hh"
#include "arch/x86/regs/apic.hh"
#include "dev/x86/intdev.hh"
#include "sim/system.hh"
#include "cpu/base.hh"
#include "base/bitunion.hh"

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
// Bind a message by value while the interrupt transport owns the packet.
template <typename M, typename P>
std::function<void(P)> plodBindMessage(const std::function<void(M, P)>& callback, M message) {
    return [callback, message](P pkt) { callback(message, pkt); };
}

class I82094AA;

class I82094AA : public BasicPioDevice {
    std::function<void(TriggerIntMessage, Packet*)> lambda_0 = [this](TriggerIntMessage message, Packet* pkt) {
        message.vector = pkt->getLE<uint8_t>();
        signalInterrupt(message);
        delete(pkt);
    };

    uint8_t regSel;
    uint8_t initialApicId;
    uint8_t id;
    uint8_t arbId;
    uint64_t lowestPriorityOffset;
    std::array<uint64_t, 24> redirTable;
    std::array<bool, 24> pinStates;
    std::vector<IntSinkPinBase*> inputs;
    IntRequestPort<I82094AA> intRequestPort;
    std::function<void(TriggerIntMessage, Packet*)> ackCallback = lambda_0;

    uint32_t select = 0;
    uint32_t window = 0;


    uint32_t select_read() {
        return regSel;
    }

    void select_write(uint32_t data) {
        regSel = static_cast<uint8_t>(data);
    }

    uint32_t window_read() {
        return readReg(regSel);
    }

    void window_write(uint32_t data) {
        writeReg(regSel, data);
    }

    public:

    using Params = I82094AAParams;
    BitUnion64(RedirTableEntry)
        Bitfield<63, 32> topDW;
        Bitfield<55, 32> topReserved;
        Bitfield<31, 0> bottomDW;
        Bitfield<31, 17> bottomReserved;
        Bitfield<63, 56> dest;
        Bitfield<16> mask;
        Bitfield<15> trigger;
        Bitfield<14> remoteIRR;
        Bitfield<13> polarity;
        Bitfield<12> deliveryStatus;
        Bitfield<11> destMode;
        Bitfield<10, 8> deliveryMode;
        Bitfield<7, 0> vector;
    EndBitUnion(RedirTableEntry)

    bool recvResponse(PacketPtr pkt);
    void init() {
        BasicPioDevice::init();
        panic_if((intRequestPort.isConnected() == 0), "Int port not connected to anything");
    }

    void writeReg(uint8_t offset, uint32_t value) {
        if ((offset == 0)) {
            id = static_cast<uint8_t>((value >> 24));
        } else if ((offset == 1)) {
        } else if ((offset == 2)) {
            arbId = static_cast<uint8_t>((value >> 24));
        } else if (((offset >= 16) & (offset <= 64))) {
            int index;
            index = ((offset - 16) / 2);
            uint64_t entry;
            entry = redirTable[index];
            if (((offset % 2) != 0)) {
                entry = ((entry & 4294967295) | (static_cast<uint64_t>((value & 4278190080)) << 32));
            } else {
                entry = ((entry & 18446744069414584320ULL) | (value & 131071));
            }
            redirTable[index] = entry;
        } else {
            warn("Access to undefined I/O APIC register");
        }
    }

    uint32_t readReg(uint8_t offset) {
        if ((offset == 0)) {
            return (static_cast<uint32_t>(id) << 24);
        } else if ((offset == 1)) {
            return 1507348;
        } else if ((offset == 2)) {
            return (static_cast<uint32_t>(arbId) << 24);
        } else if (((offset >= 16) & (offset <= 64))) {
            int index;
            index = ((offset - 16) / 2);
            if (((offset % 2) != 0)) {
                return static_cast<uint32_t>((redirTable[index] >> 32));
            }
            return static_cast<uint32_t>(redirTable[index]);
        }
        warn("Access to undefined I/O APIC register");
        return 0;
    }

    void requestInterrupt(int line) {
        assert((line < 24));
        uint64_t entry;
        entry = redirTable[line];
        if ((((entry >> 16) & 1) != 0)) {
            return;
        }
        TriggerIntMessage message;
        message = TriggerIntMessage(0);
        message.destination = static_cast<uint32_t>((entry >> 56));
        message.deliveryMode = static_cast<uint32_t>(((entry >> 8) & 7));
        message.destMode = static_cast<uint32_t>(((entry >> 11) & 1));
        message.level = static_cast<uint32_t>(((entry >> 13) & 1));
        message.trigger = static_cast<uint32_t>(((entry >> 15) & 1));
        if ((message.deliveryMode == 7)) {
            Packet* pkt;
            pkt = buildIntAcknowledgePacket();
            intRequestPort.sendMessage(pkt, sys->isTimingMode(), plodBindMessage(ackCallback, message));
        } else {
            message.vector = static_cast<uint32_t>((entry & 255));
            signalInterrupt(message);
        }
    }

    void signalInterrupt(TriggerIntMessage message) {
        std::vector<int> apics;
        int numContexts;
        numContexts = sys->threads.size();
        if ((message.destMode == 0)) {
            panic_if((message.deliveryMode == 1), "Lowest priority delivery unsupported in physical destination mode");
            if ((message.destination == 255)) {
                for (int i = 0; i < numContexts; ++i) {
                    apics.push_back(i);
                }
            } else {
                apics.push_back(message.destination);
            }
        } else {
            for (int i = 0; i < numContexts; ++i) {
                BaseInterrupts* base;
                base = sys->threads[i]->getCpuPtr()->getInterruptController(0);
                Interrupts* lapic;
                lapic = dynamic_cast<Interrupts*>(base);
                if ((((lapic->readReg(APIC_LOGICAL_DESTINATION) >> 24) & message.destination) != 0)) {
                    apics.push_back(lapic->getInitialApicId());
                }
            }
            if (((message.deliveryMode == 1) & (apics.size() != 0))) {
                uint64_t modOffset;
                modOffset = (lowestPriorityOffset % apics.size());
                lowestPriorityOffset = (lowestPriorityOffset + 1);
                int selected;
                selected = apics[modOffset];
                apics.clear();
                apics.push_back(selected);
            }
        }
        for (int i = 0; i < apics.size(); ++i) {
            Packet* pkt;
            pkt = buildIntTriggerPacket(apics[i], message);
            intRequestPort.sendMessage(pkt, sys->isTimingMode());
        }
    }

    void raiseInterruptPin(int number) {
        assert((number < 24));
        if ((pinStates[number] == 0)) {
            requestInterrupt(number);
        }
        pinStates[number] = 1;
    }

    void lowerInterruptPin(int number) {
        assert((number < 24));
        pinStates[number] = 0;
    }

    I82094AA(const I82094AAParams &params)
        : BasicPioDevice(params, 20), regSel(0), initialApicId(params.apic_id), id(params.apic_id), arbId(params.apic_id), lowestPriorityOffset(0), intRequestPort((name() + ".int_request"), this, this, params.int_latency) {
        assert((params.apic_id < 255));
        for (int i = 0; i < 24; ++i) {
            redirTable[i] = 65536;
            pinStates[i] = 0;
        }
        for (int i = 0; i < params.port_inputs_connection_count; ++i) {
            inputs.push_back(new IntSinkPinBase((((name() + ".inputs[") + std::to_string(i)) + "]"), i, this));
        }
    }

    Tick read(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        assert(pkt->getSize() == 4);
        bool matched = false;
        if (!matched && (daddr == 0)) {
            matched = true;
            pkt->setLE<uint32_t>(select_read());
        }
        if (!matched && (daddr == 16)) {
            matched = true;
            pkt->setLE<uint32_t>(window_read());
        }
        panic_if(!matched, "Unhandled read address");
        pkt->makeAtomicResponse();
        return this->pioDelay;
    }

    Tick write(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        assert(pkt->getSize() == 4);
        bool matched = false;
        if (!matched && (daddr == 0)) {
            matched = true;
            select_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 16)) {
            matched = true;
            window_write(pkt->getLE<uint32_t>());
        }
        panic_if(!matched, "Unhandled write address");
        pkt->makeAtomicResponse();
        return this->pioDelay;
    }

    AddrRangeList getAddrRanges() const
    {
        AddrRangeList ranges;
        ranges.push_back(RangeSize(pioAddr, pioSize));
        return ranges;
    }

    void serialize(CheckpointOut& cp) const override {
        paramOut(cp, "regSel", this->regSel);
        paramOut(cp, "initialApicId", this->initialApicId);
        paramOut(cp, "id", this->id);
        paramOut(cp, "arbId", this->arbId);
        paramOut(cp, "lowestPriorityOffset", this->lowestPriorityOffset);
        arrayParamOut(cp, "redirTableArray", this->redirTable);
        arrayParamOut(cp, "pinStates", this->pinStates);
    }

    void unserialize(CheckpointIn& cp) override {
        paramIn(cp, "regSel", this->regSel);
        paramIn(cp, "initialApicId", this->initialApicId);
        paramIn(cp, "id", this->id);
        paramIn(cp, "arbId", this->arbId);
        paramIn(cp, "lowestPriorityOffset", this->lowestPriorityOffset);
        arrayParamIn(cp, "redirTableArray", this->redirTable);
        arrayParamIn(cp, "pinStates", this->pinStates);
    }


    Port &getPort(const std::string &if_name, PortID idx=InvalidPortID)
    {
        if (if_name == "int_requestor") return intRequestPort;
        if (if_name == "inputs") return *inputs.at(idx);
        return BasicPioDevice::getPort(if_name, idx);
    }

};

}
