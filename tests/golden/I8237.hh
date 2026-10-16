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
#include "params/I8237.hh"
#include "sim/serialize.hh"
#include "dev/reg_bank.hh"

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


class I8237 : public BasicPioDevice {
    uint64_t latency;
    uint8_t maskVal;
    uint8_t requestVal;
    uint8_t commandVal;
    uint8_t statusVal;
    uint8_t tempVal;
    bool highByte;
    std::array<uint8_t, 4> modes;

    std::vector<RegisterBankLE::Register<uint8_t>> channel;
    RegisterBankLE::Register<uint8_t> status_command{"status_command", 0};
    RegisterBankLE::Register<uint8_t> request{"request", 0};
    RegisterBankLE::Register<uint8_t> set_mask_bit{"set_mask_bit", 0};
    RegisterBankLE::Register<uint8_t> mode{"mode", 0};
    RegisterBankLE::Register<uint8_t> clear_flip_flop{"clear_flip_flop", 0};
    RegisterBankLE::Register<uint8_t> temporary_master_clear{"temporary_master_clear", 0};
    RegisterBankLE::Register<uint8_t> clear_mask{"clear_mask", 0};
    RegisterBankLE::Register<uint8_t> write_mask{"write_mask", 0};


    uint8_t channel_read(uint64_t cid) {
        panic("Read from i8237 channel unimplemented");
        return 0;
    }

    void channel_write(uint8_t data, uint64_t cid) {
        panic("Write to i8237 channel unimplemented");
    }

    uint8_t status_command_read() {
        return statusVal;
    }

    void status_command_write(uint8_t data) {
        commandVal = data;
    }

    uint8_t request_read() {
        panic("Illegal read from i8237 request register");
        return 0;
    }

    void request_write(uint8_t data) {
        uint8_t select;
        select = (data & 3);
        uint8_t bitVal;
        bitVal = ((data >> 2) & 1);
        panic_if((bitVal != 0), "Requesting i8237 DMA transfers is unimplemented");
        requestVal = ((requestVal & (~(static_cast<uint8_t>(1) << select))) | (bitVal << select));
    }

    uint8_t set_mask_bit_read() {
        panic("Illegal read from i8237 set mask register");
        return 0;
    }

    void set_mask_bit_write(uint8_t data) {
        uint8_t select;
        select = (data & 3);
        uint8_t bitVal;
        bitVal = ((data >> 2) & 1);
        panic_if((bitVal == 0), "Turning on i8237 channels unimplemented");
        maskVal = ((maskVal & (~(static_cast<uint8_t>(1) << select))) | (bitVal << select));
    }

    uint8_t mode_read() {
        panic("Illegal read from i8237 mode register");
        return 0;
    }

    void mode_write(uint8_t data) {
        modes[(data & 3)] = data;
    }

    uint8_t clear_flip_flop_read() {
        panic("Illegal read from i8237 clear flip-flop register");
        return 0;
    }

    void clear_flip_flop_write(uint8_t data) {
        highByte = 0;
    }

    uint8_t temporary_master_clear_read() {
        return tempVal;
    }

    void temporary_master_clear_write(uint8_t data) {
        reset();
    }

    uint8_t clear_mask_read() {
        panic("Illegal read from i8237 clear mask register");
        return 0;
    }

    void clear_mask_write(uint8_t data) {
        maskVal = 0;
    }

    uint8_t write_mask_read() {
        panic("Illegal read from i8237 write mask register");
        return 0;
    }

    void write_mask_write(uint8_t data) {
        maskVal = (data & 15);
    }
    RegisterBankLE _registerBank;
    std::vector<std::unique_ptr<RegisterBankLE::RegisterRaz>> _registerGaps;
    void initRegisters() {
        struct Entry { Addr offset; RegisterBankLE::RegisterBase* reg; };
        std::vector<Entry> entries;
        const int64_t channel_count0 = 8;
        panic_if(channel_count0 < 0 || 1 < 1, "Invalid layout for channel");
        channel.reserve(channel_count0);
        {
            uint64_t cid = 0;
            for (int64_t i0 = 0; i0 < channel_count0; ++i0) {
                channel.emplace_back("channel" + std::to_string(i0), 0);
                auto& reg = channel.back();
                reg.reader([this, cid](auto&) { return channel_read(cid); });
                reg.writer([this, cid](auto&, const auto& data) { channel_write(data, cid); });
                entries.push_back({static_cast<Addr>(0 + i0 * 1), &reg});
                ++cid;
            }
        }
        {
            auto& reg = status_command;
            reg.reader([this](auto&) { return status_command_read(); });
            reg.writer([this](auto&, const auto& data) { status_command_write(data); });
            entries.push_back({static_cast<Addr>(8), &reg});
        }
        {
            auto& reg = request;
            reg.reader([this](auto&) { return request_read(); });
            reg.writer([this](auto&, const auto& data) { request_write(data); });
            entries.push_back({static_cast<Addr>(9), &reg});
        }
        {
            auto& reg = set_mask_bit;
            reg.reader([this](auto&) { return set_mask_bit_read(); });
            reg.writer([this](auto&, const auto& data) { set_mask_bit_write(data); });
            entries.push_back({static_cast<Addr>(10), &reg});
        }
        {
            auto& reg = mode;
            reg.reader([this](auto&) { return mode_read(); });
            reg.writer([this](auto&, const auto& data) { mode_write(data); });
            entries.push_back({static_cast<Addr>(11), &reg});
        }
        {
            auto& reg = clear_flip_flop;
            reg.reader([this](auto&) { return clear_flip_flop_read(); });
            reg.writer([this](auto&, const auto& data) { clear_flip_flop_write(data); });
            entries.push_back({static_cast<Addr>(12), &reg});
        }
        {
            auto& reg = temporary_master_clear;
            reg.reader([this](auto&) { return temporary_master_clear_read(); });
            reg.writer([this](auto&, const auto& data) { temporary_master_clear_write(data); });
            entries.push_back({static_cast<Addr>(13), &reg});
        }
        {
            auto& reg = clear_mask;
            reg.reader([this](auto&) { return clear_mask_read(); });
            reg.writer([this](auto&, const auto& data) { clear_mask_write(data); });
            entries.push_back({static_cast<Addr>(14), &reg});
        }
        {
            auto& reg = write_mask;
            reg.reader([this](auto&) { return write_mask_read(); });
            reg.writer([this](auto&, const auto& data) { write_mask_write(data); });
            entries.push_back({static_cast<Addr>(15), &reg});
        }
        std::stable_sort(entries.begin(), entries.end(), [](auto a, auto b) { return a.offset < b.offset; });
        Addr next = 0;
        for (auto entry : entries) {
            panic_if(entry.offset < next || entry.offset > pioSize || entry.reg->size() > pioSize - entry.offset, "Invalid register layout");
            if (entry.offset > next) {
                _registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>("reserved" + std::to_string(_registerGaps.size()), entry.offset - next));
                _registerBank.addRegister(*_registerGaps.back());
            }
            _registerBank.addRegister(*entry.reg);
            next = entry.offset + entry.reg->size();
        }
        if (next < pioSize) {
            _registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>("reserved" + std::to_string(_registerGaps.size()), pioSize - next));
            _registerBank.addRegister(*_registerGaps.back());
        }
    }
    void readRegisters(PacketPtr pkt) {
        _registerBank.read(pkt->getAddr(), pkt->getPtr<void>(), pkt->getSize());
    }
    void writeRegisters(PacketPtr pkt) {
        _registerBank.write(pkt->getAddr(), pkt->getPtr<void>(), pkt->getSize());
    }

    public:

    using Params = I8237Params;
    using Register = RegisterBankLE::Register8;
    void init() {
        BasicPioDevice::init();
    }

    void reset() {
        maskVal = 15;
        requestVal = 0;
        commandVal = 0;
        statusVal = 0;
        tempVal = 0;
        highByte = 0;
    }

    I8237(const I8237Params &params)
        : BasicPioDevice(params, 16), latency(params.pio_latency), _registerBank(params.name, pioAddr) {
        for (int i = 0; i < 4; ++i) {
            modes[i] = 0;
        }
        initRegisters();
        reset();
    }

    Tick read(PacketPtr pkt) override {
        readRegisters(pkt);
        pkt->makeAtomicResponse();
        return this->latency;
    }

    Tick write(PacketPtr pkt) override {
        writeRegisters(pkt);
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
        paramOut(cp, "maskReg", this->maskVal);
    }

    void unserialize(CheckpointIn& cp) override {
        paramIn(cp, "maskReg", this->maskVal);
    }


    Port &getPort(const std::string &if_name, PortID idx=InvalidPortID)
    {
        return BasicPioDevice::getPort(if_name, idx);
    }

};

}
