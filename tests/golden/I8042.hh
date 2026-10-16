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
#include "params/I8042.hh"
#include "sim/serialize.hh"
#include "dev/intpin.hh"
#include "dev/ps2/device.hh"

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


class I8042 : public PioDevice {
    uint16_t no_command = 65535;

    uint64_t latency;
    uint64_t dataPort;
    uint64_t commandPort;
    uint8_t statusReg;
    uint8_t commandByte;
    uint8_t dataReg;
    uint16_t lastCommand;
    std::vector<IntSourcePinBase*> mouseIntPin;
    std::vector<IntSourcePinBase*> keyboardIntPin;
    ps2::Device* mouse;
    ps2::Device* keyboard;

    uint8_t output_buffer = 0;
    uint8_t input_buffer = 0;
    uint8_t status = 0;
    uint8_t command = 0;


    uint8_t output_buffer_read() {
        uint8_t data;
        data = dataReg;
        statusReg = (statusReg & 222);
        if (keyboard->hostDataAvailable()) {
            writeData(keyboard->hostRead(), 0);
        } else if (mouse->hostDataAvailable()) {
            writeData(mouse->hostRead(), 1);
        }
        return data;
    }

    void output_buffer_write(uint8_t data) { output_buffer = data; }

    void input_buffer_write(uint8_t data) {
        statusReg = (statusReg & 247);
        if ((lastCommand == no_command)) {
            keyboard->hostWrite(data);
            if (keyboard->hostDataAvailable()) {
                writeData(keyboard->hostRead(), 0);
            }
        } else if ((lastCommand == 212)) {
            mouse->hostWrite(data);
            if (mouse->hostDataAvailable()) {
                writeData(mouse->hostRead(), 1);
            }
        } else if ((lastCommand == 96)) {
            commandByte = data;
        } else if ((lastCommand == 211)) {
            writeData(data, 1);
        } else if ((lastCommand == 210)) {
            writeData(data, 0);
        } else if ((lastCommand == 209)) {
            panic_if(((data & 1) != 1), "Reset bit should be 1");
        } else {
            panic("Data written for unrecognized i8042 command");
        }
        lastCommand = no_command;
    }

    uint8_t input_buffer_read() { return input_buffer; }

    uint8_t status_read() {
        return statusReg;
    }

    void status_write(uint8_t data) { status = data; }

    void command_write(uint8_t data) {
        statusReg = (statusReg | 8);
        panic_if(((data > 32) & (data < 64)), "Unimplemented i8042 read controller RAM");
        panic_if(((data > 96) & (data < 128)), "Unimplemented i8042 write controller RAM");
        panic_if(((data >= 240) & (data < 254)), "Unimplemented i8042 pulse output bit");
        if ((data == 32)) {
            writeData(commandByte, 0);
        } else if ((((((data == 96) | (data == 209)) | (data == 210)) | (data == 211)) | (data == 212))) {
            lastCommand = data;
        } else if ((data == 167)) {
            commandByte = (commandByte | 32);
        } else if ((data == 168)) {
            commandByte = (commandByte & 223);
        } else if (((data == 169) | (data == 171))) {
            writeData(0, 0);
        } else if ((data == 170)) {
            commandByte = (commandByte | 116);
            statusReg = (statusReg | 4);
            writeData(85, 0);
        } else if ((data == 173)) {
            commandByte = (commandByte | 16);
        } else if ((data == 174)) {
            commandByte = (commandByte & 239);
        } else if (((((((((((((data == 164) | (data == 165)) | (data == 166)) | (data == 172)) | (data == 192)) | (data == 193)) | (data == 194)) | (data == 208)) | (data == 221)) | (data == 223)) | (data == 224)) | (data == 254))) {
            panic("Unimplemented i8042 command");
        } else {
            warn("Write to unknown i8042 command port");
        }
    }

    uint8_t command_read() { return command; }

    public:

    using Params = I8042Params;
    AddrRangeList getAddrRanges() const {
        AddrRangeList ranges;
        ranges.push_back(RangeSize(dataPort, 1));
        ranges.push_back(RangeSize(commandPort, 1));
        return ranges;
    }

    void writeData(uint8_t newData, bool fromMouse) {
        dataReg = newData;
        statusReg = ((statusReg & 223) | 1);
        if (fromMouse) {
            statusReg = (statusReg | 32);
        }
        if (((fromMouse == 0) & ((commandByte & 1) != 0))) {
            for (int i = 0; i < keyboardIntPin.size(); ++i) {
                keyboardIntPin[i]->raise();
                keyboardIntPin[i]->lower();
            }
        } else if ((fromMouse & ((commandByte & 2) != 0))) {
            for (int i = 0; i < mouseIntPin.size(); ++i) {
                mouseIntPin[i]->raise();
                mouseIntPin[i]->lower();
            }
        }
    }

    I8042(const I8042Params &params)
        : PioDevice(params), latency(params.pio_latency), dataPort(params.data_port), commandPort(params.command_port), statusReg(16), commandByte(112), dataReg(0), lastCommand(no_command), mouse(params.mouse), keyboard(params.keyboard) {
        fatal_if((mouse == 0), "The i8042 model requires a mouse instance");
        fatal_if((keyboard == 0), "The i8042 model requires a keyboard instance");
        for (int i = 0; i < params.port_keyboard_int_pin_connection_count; ++i) {
            keyboardIntPin.push_back(new IntSourcePinBase((((name() + ".keyboard_int_pin[") + std::to_string(i)) + "]"), i, this));
        }
        for (int i = 0; i < params.port_mouse_int_pin_connection_count; ++i) {
            mouseIntPin.push_back(new IntSourcePinBase((((name() + ".mouse_int_pin[") + std::to_string(i)) + "]"), i, this));
        }
    }

    Tick read(PacketPtr pkt) override {
        assert(pkt->getSize() == 1);
        bool matched = false;
        if (!matched && (pkt->getAddr() == this->dataPort)) {
            matched = true;
            pkt->setLE<uint8_t>(output_buffer_read());
        }
        if (!matched && (pkt->getAddr() == this->commandPort)) {
            matched = true;
            pkt->setLE<uint8_t>(status_read());
        }
        if (!matched && (pkt->getAddr() == this->dataPort)) {
            matched = true;
            panic("Forbidden read access");
        }
        if (!matched && (pkt->getAddr() == this->commandPort)) {
            matched = true;
            panic("Forbidden read access");
        }
        panic_if(!matched, "Unhandled read address");
        pkt->makeAtomicResponse();
        return this->latency;
    }

    Tick write(PacketPtr pkt) override {
        assert(pkt->getSize() == 1);
        bool matched = false;
        if (!matched && (pkt->getAddr() == this->dataPort)) {
            matched = true;
            input_buffer_write(pkt->getLE<uint8_t>());
        }
        if (!matched && (pkt->getAddr() == this->commandPort)) {
            matched = true;
            command_write(pkt->getLE<uint8_t>());
        }
        if (!matched && (pkt->getAddr() == this->dataPort)) {
            matched = true;
            panic("Forbidden write access");
        }
        if (!matched && (pkt->getAddr() == this->commandPort)) {
            matched = true;
            panic("Forbidden write access");
        }
        panic_if(!matched, "Unhandled write address");
        pkt->makeAtomicResponse();
        return this->latency;
    }

    void serialize(CheckpointOut& cp) const override {
        paramOut(cp, "dataPort", this->dataPort);
        paramOut(cp, "commandPort", this->commandPort);
        paramOut(cp, "statusReg", this->statusReg);
        paramOut(cp, "commandByte", this->commandByte);
        paramOut(cp, "dataReg", this->dataReg);
        paramOut(cp, "lastCommand", this->lastCommand);
    }

    void unserialize(CheckpointIn& cp) override {
        paramIn(cp, "dataPort", this->dataPort);
        paramIn(cp, "commandPort", this->commandPort);
        paramIn(cp, "statusReg", this->statusReg);
        paramIn(cp, "commandByte", this->commandByte);
        paramIn(cp, "dataReg", this->dataReg);
        paramIn(cp, "lastCommand", this->lastCommand);
    }


    Port &getPort(const std::string &if_name, PortID idx=InvalidPortID)
    {
        if (if_name == "mouse_int_pin") return *mouseIntPin.at(idx);
        if (if_name == "keyboard_int_pin") return *keyboardIntPin.at(idx);
        return PioDevice::getPort(if_name, idx);
    }

    void init()
    {
        PioDevice::init();
    }
};

}
