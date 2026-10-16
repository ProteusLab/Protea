/*
 * Copyright (c) 2004-2005 The Regents of The University of Michigan
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
#include "params/I8259.hh"
#include "sim/serialize.hh"
#include "dev/intpin.hh"
#include "arch/x86/x86_traits.hh"
#include "base/bitfield.hh"
#include "enums/X86I8259CascadeMode.hh"

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

class I8259;

class I8259 : public BasicPioDevice {
    std::array<bool, 8> pinStates;
    uint64_t latency;
    std::vector<IntSourcePinBase*> output;
    std::vector<IntSinkPinBase*> inputs;
    int mode;
    I8259* slave;
    uint8_t irr;
    uint8_t isr;
    uint8_t imr;
    uint8_t vectorOffset;
    bool cascadeMode;
    uint8_t cascadeBits;
    bool edgeTriggered;
    bool readIRR;
    bool expectICW4;
    int initControlWord;
    bool autoEOI;

    uint8_t inta = 0;
    uint8_t command = 0;
    uint8_t mask = 0;


    uint8_t inta_read() {
        assert(((mode == 0) | (mode == 2)));
        return static_cast<uint8_t>(getVector());
    }

    void inta_write(uint8_t data) { inta = data; }

    uint8_t command_read() {
        if (readIRR) {
            return irr;
        }
        return isr;
    }

    void command_write(uint8_t data) {
        if (((data & 16) != 0)) {
            imr = 0;
            edgeTriggered = ((data >> 3) & 1);
            cascadeMode = ((data & 2) == 0);
            expectICW4 = (data & 1);
            if ((expectICW4 == 0)) {
                autoEOI = 0;
            }
            initControlWord = 1;
        } else if ((((data >> 3) & 3) == 0)) {
            uint8_t operation;
            operation = (data >> 5);
            if ((operation == 1)) {
                handleEOI(findMsbSet(isr));
            } else if ((operation == 3)) {
                handleEOI((data & 7));
            }
        } else if ((((data >> 3) & 3) == 1)) {
            if (((data & 2) != 0)) {
                readIRR = (data & 1);
            }
        }
    }

    uint8_t mask_read() {
        return imr;
    }

    void mask_write(uint8_t data) {
        if ((initControlWord == 0)) {
            imr = data;
        } else if ((initControlWord == 1)) {
            vectorOffset = (data & 248);
            if (cascadeMode) {
                initControlWord = (initControlWord + 1);
            } else {
                cascadeBits = 0;
                initControlWord = 0;
            }
        } else if ((initControlWord == 2)) {
            if ((mode == 0)) {
                cascadeBits = data;
            } else {
                cascadeBits = (data & 7);
            }
            if (expectICW4) {
                initControlWord = (initControlWord + 1);
            } else {
                initControlWord = 0;
            }
        } else if ((initControlWord == 3)) {
            autoEOI = ((data >> 1) & 1);
            initControlWord = 0;
        }
    }

    public:

    using Params = I8259Params;
    AddrRangeList getAddrRanges() const {
        AddrRangeList ranges;
        ranges.push_back(RangeSize(pioAddr, pioSize));
        if (((mode == 0) | (mode == 2))) {
            ranges.push_back(RangeSize(PhysAddrIntA, 1));
        }
        return ranges;
    }

    void init() {
        BasicPioDevice::init();
        for (int i = 0; i < inputs.size(); ++i) {
            pinStates[inputs[i]->getId()] = inputs[i]->state();
        }
    }

    void maskAll() {
        imr = 255;
    }

    void unmaskAll() {
        imr = 0;
    }

    void handleEOI(int line) {
        isr = (isr & (~(static_cast<uint8_t>(1) << line)));
        if ((irr != 0)) {
            requestInterrupt(findMsbSet(irr));
        }
    }

    void requestInterrupt(int line) {
        if (((isr >> line) == 0)) {
            if ((output.empty() == 0)) {
                for (int i = 0; i < output.size(); ++i) {
                    output[i]->raise();
                    output[i]->lower();
                }
            } else {
                warn("Received interrupt but didn't have anyone to tell about it");
            }
        }
    }

    void signalInterrupt(int line) {
        fatal_if((line >= 8), "I8259 interrupt line does not exist");
        if ((((imr >> line) & 1) == 0)) {
            irr = (irr | (static_cast<uint8_t>(1) << line));
            requestInterrupt(line);
        }
    }

    void raiseInterruptPin(int number) {
        fatal_if((number >= 8), "I8259 interrupt line does not exist");
        if ((pinStates[number] == 0)) {
            signalInterrupt(number);
        }
        pinStates[number] = 1;
    }

    void lowerInterruptPin(int number) {
        fatal_if((number >= 8), "I8259 interrupt line does not exist");
        pinStates[number] = 0;
    }

    int getVector() {
        int line;
        line = findMsbSet(irr);
        irr = (irr & (~(static_cast<uint8_t>(1) << line)));
        if (autoEOI) {
            handleEOI(line);
        } else {
            isr = (isr | (static_cast<uint8_t>(1) << line));
        }
        if ((slave != 0)) {
            if ((((cascadeBits >> line) & 1) != 0)) {
                return slave->getVector();
            }
        }
        return (line | vectorOffset);
    }

    I8259(const I8259Params &params)
        : BasicPioDevice(params, 2), latency(params.pio_latency), mode(params.mode), slave(params.slave), irr(0), isr(0), imr(0), vectorOffset(0), cascadeMode(0), cascadeBits(0), edgeTriggered(1), readIRR(1), expectICW4(0), initControlWord(0), autoEOI(0) {
        for (int i = 0; i < 8; ++i) {
            pinStates[i] = 0;
        }
        for (int i = 0; i < params.port_output_connection_count; ++i) {
            output.push_back(new IntSourcePinBase((((name() + ".output[") + std::to_string(i)) + "]"), i, this));
        }
        panic_if((params.port_inputs_connection_count > 8), "I8259 only supports 8 inputs");
        for (int i = 0; i < params.port_inputs_connection_count; ++i) {
            inputs.push_back(new IntSinkPinBase((((name() + ".inputs[") + std::to_string(i)) + "]"), i, this));
        }
    }

    Tick read(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        assert(pkt->getSize() == 1);
        bool matched = false;
        if ((pkt->getAddr() == PhysAddrIntA)) {
            matched = true;
            pkt->setLE<uint8_t>(inta_read());
        }
        if ((daddr == 0)) {
            matched = true;
            pkt->setLE<uint8_t>(command_read());
        }
        if ((daddr == 1)) {
            matched = true;
            pkt->setLE<uint8_t>(mask_read());
        }
        pkt->makeAtomicResponse();
        return this->latency;
    }

    Tick write(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        assert(pkt->getSize() == 1);
        bool matched = false;
        if ((daddr == 0)) {
            matched = true;
            command_write(pkt->getLE<uint8_t>());
        }
        if ((daddr == 1)) {
            matched = true;
            mask_write(pkt->getLE<uint8_t>());
        }
        if (!matched && (pkt->getAddr() == PhysAddrIntA)) {
            matched = true;
        }
        pkt->makeAtomicResponse();
        return this->latency;
    }

    void serialize(CheckpointOut& cp) const override {
        arrayParamOut(cp, "pinStates", this->pinStates);
        paramOut(cp, "mode", this->mode);
        paramOut(cp, "IRR", this->irr);
        paramOut(cp, "ISR", this->isr);
        paramOut(cp, "IMR", this->imr);
        paramOut(cp, "vectorOffset", this->vectorOffset);
        paramOut(cp, "cascadeMode", this->cascadeMode);
        paramOut(cp, "cascadeBits", this->cascadeBits);
        paramOut(cp, "edgeTriggered", this->edgeTriggered);
        paramOut(cp, "readIRR", this->readIRR);
        paramOut(cp, "expectICW4", this->expectICW4);
        paramOut(cp, "initControlWord", this->initControlWord);
        paramOut(cp, "autoEOI", this->autoEOI);
    }

    void unserialize(CheckpointIn& cp) override {
        arrayParamIn(cp, "pinStates", this->pinStates);
        paramIn(cp, "mode", this->mode);
        paramIn(cp, "IRR", this->irr);
        paramIn(cp, "ISR", this->isr);
        paramIn(cp, "IMR", this->imr);
        paramIn(cp, "vectorOffset", this->vectorOffset);
        paramIn(cp, "cascadeMode", this->cascadeMode);
        paramIn(cp, "cascadeBits", this->cascadeBits);
        paramIn(cp, "edgeTriggered", this->edgeTriggered);
        paramIn(cp, "readIRR", this->readIRR);
        paramIn(cp, "expectICW4", this->expectICW4);
        paramIn(cp, "initControlWord", this->initControlWord);
        paramIn(cp, "autoEOI", this->autoEOI);
    }


    Port &getPort(const std::string &if_name, PortID idx=InvalidPortID)
    {
        if (if_name == "inputs") return *inputs.at(idx);
        if (if_name == "output") return *output.at(idx);
        return BasicPioDevice::getPort(if_name, idx);
    }

};

}
