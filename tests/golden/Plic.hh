/*
 * Copyright (c) 2021 Huawei International
 * Copyright (c) 2023 Google LLC
 * All rights reserved
 *
 * The license below extends only to copyright in the software and shall
 * not be construed as granting a license to any other intellectual
 * property including but not limited to intellectual property relating
 * to a hardware implementation of the functionality of the software
 * licensed hereunder.  You may use the software subject to the license
 * terms below provided that you ensure that this notice is replicated
 * unmodified and in its entirety in all distributions of the software,
 * modified or unmodified, in source code or in binary form.
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
#include "cpu/base.hh"
#include "dev/io_device.hh"
#include "dev/reg_bank.hh"
#include "mem/packet.hh"
#include "mem/packet_access.hh"
#include "params/Plic.hh"
#include "params/PlicBase.hh"
#include "sim/eventq.hh"
#include "sim/serialize.hh"
#include "sim/system.hh"

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

namespace gem5 {
class PlicBase : public BasicPioDevice {
  public:
    using Params = PlicBaseParams;
    PlicBase(const Params& params) : BasicPioDevice(params, params.pio_size) {}
    virtual void post(int src_id) = 0;
    virtual void clear(int src_id) = 0;
};

struct PlicContext {
    uint32_t hart;
    int interrupt;
};

struct PlicOutput {
    std::vector<uint32_t> maxID;
    std::vector<uint32_t> maxPriority;
};


class Plic : public PlicBase {
    int int_ext_machine = 11;
    int int_ext_super = 9;

    std::function<void()> lambda_0 = [this]() {
        updateOutput();
    };

    System* system;
    int nSrc;
    int nSrc32;
    std::vector<PlicContext> contextConfigs;
    uint64_t outputLatency;
    std::vector<uint32_t> pendingPriority;
    std::vector<std::vector<uint32_t>> effPriority;
    std::vector<uint32_t> lastID;
    PlicOutput output;
    std::map<uint64_t, PlicOutput> outputQueue;
    std::function<void()> updateCallback = lambda_0;
    EventFunctionWrapper update;

    std::vector<RegisterBankLE::Register<uint32_t>> priority;
    std::vector<RegisterBankLE::Register<uint32_t>> pending;
    std::vector<RegisterBankLE::Register<uint32_t>> enable;
    std::vector<RegisterBankLE::Register<uint32_t>> threshold;
    std::vector<RegisterBankLE::Register<uint32_t>> claim;


    void priority_write(uint32_t data, uint64_t cid) {
        priority[cid].get() = data;
        int word;
        word = (cid >> 5);
        int bit;
        bit = (cid & 31);
        if (((pending[word].get() >> bit) & 1)) {
            pendingPriority[cid] = data;
        } else {
            pendingPriority[cid] = 0;
        }
        for (int i = 0; i < contextConfigs.size(); ++i) {
            if (((enable[((i * nSrc32) + word)].get() >> bit) & 1)) {
                effPriority[i][cid] = pendingPriority[cid];
            } else {
                effPriority[i][cid] = 0;
            }
        }
    }

    uint32_t priority_read(uint64_t cid) { return priority[cid].get(); }

    uint32_t pending_read(uint64_t cid) { return pending[cid].get(); }

    void pending_write(uint32_t data, uint64_t cid) { pending[cid].get() = data; }

    void enable_write(uint32_t data, uint64_t cid) {
        enable[cid].get() = data;
        int context;
        context = (cid / nSrc32);
        int word;
        word = (cid % nSrc32);
        for (int i = 0; i < 32; ++i) {
            int src_id;
            src_id = ((word << 5) + i);
            if ((src_id < nSrc)) {
                if (((data >> i) & 1)) {
                    effPriority[context][src_id] = pendingPriority[src_id];
                } else {
                    effPriority[context][src_id] = 0;
                }
            }
        }
    }

    uint32_t enable_read(uint64_t cid) { return enable[cid].get(); }

    uint32_t threshold_read(uint64_t cid) { return threshold[cid].get(); }

    void threshold_write(uint32_t data, uint64_t cid) { threshold[cid].get() = data; }

    uint32_t claim_read(uint64_t cid) {
        if ((lastID[cid] == 0)) {
            uint32_t max_id;
            max_id = output.maxID[cid];
            int word;
            word = (max_id >> 5);
            int bit;
            bit = (max_id & 31);
            if (((pending[word].get() >> bit) & 1)) {
                lastID[cid] = max_id;
                clear(max_id);
                claim[cid].get() = max_id;
                return claim[cid].get();
            }
            return 0;
        }
        warn("PLIC claim repeated (not completed)");
        return lastID[cid];
    }

    void claim_write(uint32_t data, uint64_t cid) {
        claim[cid].get() = data;
        assert((lastID[cid] == data));
        lastID[cid] = 0;
        updateInt();
    }
    RegisterBankLE _registerBank;
    std::vector<std::unique_ptr<RegisterBankLE::RegisterRaz>> _registerGaps;
    void initRegisters() {
        struct Entry { Addr offset; RegisterBankLE::RegisterBase* reg; };
        std::vector<Entry> entries;
        const int64_t priority_count0 = nSrc;
        panic_if(priority_count0 < 0 || 4 < 4, "Invalid layout for priority");
        priority.reserve(priority_count0);
        {
            uint64_t cid = 0;
            for (int64_t i0 = 0; i0 < priority_count0; ++i0) {
                priority.emplace_back("priority" + std::to_string(i0), 0);
                auto& reg = priority.back();
                reg.reader([this, cid](auto&) { return priority_read(cid); });
                reg.writer([this, cid](auto&, const auto& data) { priority_write(data, cid); });
                entries.push_back({static_cast<Addr>(0 + i0 * 4), &reg});
                ++cid;
            }
        }
        {
            const Addr offset = 0 + priority_count0 * 4;
            const int64_t bytes = 4096 - priority_count0 * 4;
            panic_if(bytes < 0, "Register window overflows");
                _registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>("padding" + std::to_string(_registerGaps.size()), bytes));
                entries.push_back({offset, _registerGaps.back().get()});
        }
        const int64_t pending_count0 = nSrc32;
        panic_if(pending_count0 < 0 || 4 < 4, "Invalid layout for pending");
        pending.reserve(pending_count0);
        {
            uint64_t cid = 0;
            for (int64_t i0 = 0; i0 < pending_count0; ++i0) {
                pending.emplace_back("pending" + std::to_string(i0), 0);
                auto& reg = pending.back();
                reg.reader([this, cid](auto&) { return pending_read(cid); });
                reg.readonly();
                entries.push_back({static_cast<Addr>(4096 + i0 * 4), &reg});
                ++cid;
            }
        }
        {
            const Addr offset = 4096 + pending_count0 * 4;
            const int64_t bytes = 4096 - pending_count0 * 4;
            panic_if(bytes < 0, "Register window overflows");
                _registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>("padding" + std::to_string(_registerGaps.size()), bytes));
                entries.push_back({offset, _registerGaps.back().get()});
        }
        const int64_t enable_count0 = contextConfigs.size();
        panic_if(enable_count0 < 0 || 128 < 4, "Invalid layout for enable");
        const int64_t enable_count1 = nSrc32;
        panic_if(enable_count1 < 0 || 4 < 4, "Invalid layout for enable");
        enable.reserve(enable_count0 * enable_count1);
        {
            uint64_t cid = 0;
            for (int64_t i0 = 0; i0 < enable_count0; ++i0) {
                for (int64_t i1 = 0; i1 < enable_count1; ++i1) {
                    enable.emplace_back("enable" + std::to_string(i0) + "_" + std::to_string(i1), 0);
                    auto& reg = enable.back();
                    reg.reader([this, cid](auto&) { return enable_read(cid); });
                    reg.writer([this, cid](auto&, const auto& data) { enable_write(data, cid); });
                    entries.push_back({static_cast<Addr>(8192 + i0 * 128 + i1 * 4), &reg});
                    ++cid;
                }
                {
                    const Addr offset = 8192 + i0 * 128 + enable_count1 * 4;
                    const int64_t bytes = 128 - enable_count1 * 4;
                    panic_if(bytes < 0, "Register window overflows");
                        _registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>("padding" + std::to_string(_registerGaps.size()), bytes));
                        entries.push_back({offset, _registerGaps.back().get()});
                }
            }
        }
        {
            const Addr offset = 8192 + enable_count0 * 128;
            const int64_t bytes = 2088960 - enable_count0 * 128;
            panic_if(bytes < 0, "Register window overflows");
                _registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>("padding" + std::to_string(_registerGaps.size()), bytes));
                entries.push_back({offset, _registerGaps.back().get()});
        }
        const int64_t threshold_count0 = contextConfigs.size();
        panic_if(threshold_count0 < 0 || 4096 < 4, "Invalid layout for threshold");
        threshold.reserve(threshold_count0);
        {
            uint64_t cid = 0;
            for (int64_t i0 = 0; i0 < threshold_count0; ++i0) {
                threshold.emplace_back("threshold" + std::to_string(i0), 0);
                auto& reg = threshold.back();
                reg.reader([this, cid](auto&) { return threshold_read(cid); });
                reg.writer([this, cid](auto&, const auto& data) { threshold_write(data, cid); });
                entries.push_back({static_cast<Addr>(2097152 + i0 * 4096), &reg});
                ++cid;
            }
        }
        const int64_t claim_count0 = contextConfigs.size();
        panic_if(claim_count0 < 0 || 4096 < 4, "Invalid layout for claim");
        claim.reserve(claim_count0);
        {
            uint64_t cid = 0;
            for (int64_t i0 = 0; i0 < claim_count0; ++i0) {
                claim.emplace_back("claim" + std::to_string(i0), 0);
                auto& reg = claim.back();
                reg.reader([this, cid](auto&) { return claim_read(cid); });
                reg.writer([this, cid](auto&, const auto& data) { claim_write(data, cid); });
                entries.push_back({static_cast<Addr>(2097156 + i0 * 4096), &reg});
                ++cid;
            }
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

    using Params = PlicParams;
    void initContextFromNContexts(int count) {
        for (int i = 0; i < count; ++i) {
            if (((i % 2) == 0)) {
                PlicContext context;
                context.hart = (i >> 1);
                context.interrupt = int_ext_machine;
                contextConfigs.push_back(context);
                context.interrupt = int_ext_super;
                contextConfigs.push_back(context);
            }
        }
    }

    void initContextFromHartConfig(std::string config) {
        PlicContext context;
        context.hart = 0;
        for (int i = 0; i < config.size(); ++i) {
            uint8_t c;
            c = config.at(i);
            if ((c == 44)) {
                context.hart = (context.hart + 1);
            } else if ((c == 77)) {
                context.interrupt = int_ext_machine;
                contextConfigs.push_back(context);
            } else if ((c == 83)) {
                context.interrupt = int_ext_super;
                contextConfigs.push_back(context);
            } else {
                fatal_if(1, "hart_config should not contain this value");
            }
        }
    }

    void init() {
        nSrc32 = ((nSrc + 31) / 32);
        assert((pioSize >= (2097152 + (contextConfigs.size() * 4096))));
        assert((pioSize <= 67108864));
        initRegisters();
        pendingPriority.resize(nSrc, 0);
        effPriority.resize(contextConfigs.size());
        for (int i = 0; i < contextConfigs.size(); ++i) {
            effPriority[i].resize(nSrc, 0);
        }
        lastID.resize(contextConfigs.size(), 0);
        output.maxID.resize(contextConfigs.size(), 0);
        output.maxPriority.resize(contextConfigs.size(), 0);
        BasicPioDevice::init();
    }

    void post(int src_id) {
        assert(((src_id < nSrc) & (src_id >= 0)));
        int word;
        word = (src_id >> 5);
        int bit;
        bit = (src_id & 31);
        pending[word].get() = (pending[word].get() | (static_cast<uint32_t>(1) << bit));
        pendingPriority[src_id] = priority[src_id].get();
        for (int i = 0; i < contextConfigs.size(); ++i) {
            if (((enable[((i * nSrc32) + word)].get() >> bit) & 1)) {
                effPriority[i][src_id] = pendingPriority[src_id];
            } else {
                effPriority[i][src_id] = 0;
            }
        }
        propagateOutput();
    }

    void clear(int src_id) {
        assert(((src_id < nSrc) & (src_id >= 0)));
        int word;
        word = (src_id >> 5);
        int bit;
        bit = (src_id & 31);
        pending[word].get() = (pending[word].get() & (~(static_cast<uint32_t>(1) << bit)));
        pendingPriority[src_id] = 0;
        for (int i = 0; i < contextConfigs.size(); ++i) {
            effPriority[i][src_id] = 0;
        }
        propagateOutput();
    }

    void propagateOutput() {
        PlicOutput new_output;
        new_output.maxID.resize(contextConfigs.size(), 0);
        new_output.maxPriority.resize(contextConfigs.size(), 0);
        for (int i = 0; i < contextConfigs.size(); ++i) {
            uint32_t max_id;
            max_id = 0;
            uint32_t max_priority;
            max_priority = effPriority[i][0];
            for (int j = 1; j < nSrc; ++j) {
                if ((effPriority[i][j] > max_priority)) {
                    max_id = j;
                    max_priority = effPriority[i][j];
                }
            }
            new_output.maxID[i] = max_id;
            new_output.maxPriority[i] = max_priority;
        }
        uint64_t next_update;
        next_update = clockEdge(Cycles(outputLatency));
        outputQueue.insert_or_assign(next_update, new_output);
        if ((update.scheduled() == 0)) {
            schedule(update, next_update);
        }
    }

    void updateOutput() {
        output = protea::firstValue(outputQueue);
        protea::eraseFirst(outputQueue);
        if ((outputQueue.empty() == 0)) {
            schedule(update, protea::firstKey(outputQueue));
        }
        updateInt();
    }

    void updateInt() {
        for (int i = 0; i < contextConfigs.size(); ++i) {
            ThreadContext* tc;
            tc = system->threads[contextConfigs[i].hart];
            uint32_t max_id;
            max_id = output.maxID[i];
            uint32_t value;
            value = output.maxPriority[i];
            uint32_t limit;
            limit = threshold[i].get();
            if ((((value > limit) & (max_id > 0)) & (lastID[i] == 0))) {
                tc->getCpuPtr()->postInterrupt(tc->threadId(), contextConfigs[i].interrupt, 0);
            } else {
                tc->getCpuPtr()->clearInterrupt(tc->threadId(), contextConfigs[i].interrupt, 0);
            }
        }
    }

    void restoreOutputEvent() {
        if ((outputQueue.empty() == 0)) {
            schedule(update, protea::firstKey(outputQueue));
        }
    }

    Plic(const PlicParams &params)
        : PlicBase(params), system(params.system), nSrc(params.n_src), outputLatency(params.output_latency), update(updateCallback, (params.name + ".update")), _registerBank(params.name, pioAddr) {
        fatal_if(((params.hart_config != "") & (params.n_contexts != 0)), "the hart_config and n_contexts can't be set simultaneously");
        if ((params.n_contexts != 0)) {
            initContextFromNContexts(params.n_contexts);
        }
        if ((params.hart_config != "")) {
            initContextFromHartConfig(params.hart_config);
        }
    }

    Tick read(PacketPtr pkt) override {
        const bool is_atomic = protea::isAtomicSwap(pkt);
        readRegisters(pkt);
        if (is_atomic) {
            protea::applyAtomic(pkt);
            return write(pkt);
        }
        pkt->makeResponse();
        return this->pioDelay;
    }

    Tick write(PacketPtr pkt) override {
        writeRegisters(pkt);
        this->propagateOutput();
        this->updateInt();
        pkt->makeResponse();
        return this->pioDelay;
    }

    AddrRangeList getAddrRanges() const
    {
        AddrRangeList ranges;
        ranges.push_back(RangeSize(pioAddr, pioSize));
        return ranges;
    }

    void serialize(CheckpointOut& cp) const override {
        for (int i = 0; i < this->nSrc32; ++i) {
            paramOut(cp, ("pending" + std::to_string(i)), this->pending[i].get());
        }
        for (int i = 0; i < this->nSrc; ++i) {
            paramOut(cp, ("priority" + std::to_string(i)), this->priority[i].get());
        }
        for (int i = 0; i < this->contextConfigs.size(); ++i) {
            for (int j = 0; j < this->nSrc32; ++j) {
                paramOut(cp, ((("enable" + std::to_string(i)) + "_") + std::to_string(j)), this->enable[((i * this->nSrc32) + j)].get());
            }
            paramOut(cp, ("threshold" + std::to_string(i)), this->threshold[i].get());
            paramOut(cp, ("claim" + std::to_string(i)), this->claim[i].get());
        }
        {
            int i = 0;
            for (const auto& _plod_entry : this->outputQueue) {
                const auto& tick = _plod_entry.first;
                const auto& snapshot = _plod_entry.second;
                paramOut(cp, ("output_tick" + std::to_string(i)), tick);
                arrayParamOut(cp, ("output_id" + std::to_string(i)), snapshot.maxID);
                arrayParamOut(cp, ("output_pri" + std::to_string(i)), snapshot.maxPriority);
                ++i;
            }
            paramOut(cp, "n_outputs", static_cast<uint32_t>(this->outputQueue.size()));
        }
        arrayParamOut(cp, "output.maxID", this->output.maxID);
        arrayParamOut(cp, "output.maxPriority", this->output.maxPriority);
        arrayParamOut(cp, "pendingPriority", this->pendingPriority);
        for (int i = 0; i < this->contextConfigs.size(); ++i) {
            arrayParamOut(cp, ("effPriority" + std::to_string(i)), this->effPriority[i]);
        }
        arrayParamOut(cp, "lastID", this->lastID);
    }

    void unserialize(CheckpointIn& cp) override {
        for (int i = 0; i < this->nSrc32; ++i) {
            paramIn(cp, ("pending" + std::to_string(i)), this->pending[i].get());
        }
        for (int i = 0; i < this->nSrc; ++i) {
            paramIn(cp, ("priority" + std::to_string(i)), this->priority[i].get());
        }
        for (int i = 0; i < this->contextConfigs.size(); ++i) {
            for (int j = 0; j < this->nSrc32; ++j) {
                paramIn(cp, ((("enable" + std::to_string(i)) + "_") + std::to_string(j)), this->enable[((i * this->nSrc32) + j)].get());
            }
            paramIn(cp, ("threshold" + std::to_string(i)), this->threshold[i].get());
            paramIn(cp, ("claim" + std::to_string(i)), this->claim[i].get());
        }
        {
            uint32_t _plod_count;
            paramIn(cp, "n_outputs", _plod_count);
            for (int i = 0; i < _plod_count; ++i) {
                uint64_t tick{};
                PlicOutput snapshot{};
                paramIn(cp, ("output_tick" + std::to_string(i)), tick);
                arrayParamIn(cp, ("output_id" + std::to_string(i)), snapshot.maxID);
                arrayParamIn(cp, ("output_pri" + std::to_string(i)), snapshot.maxPriority);
                this->outputQueue.insert_or_assign(tick, snapshot);
            }
        }
        this->restoreOutputEvent();
        arrayParamIn(cp, "output.maxID", this->output.maxID);
        arrayParamIn(cp, "output.maxPriority", this->output.maxPriority);
        arrayParamIn(cp, "pendingPriority", this->pendingPriority);
        for (int i = 0; i < this->contextConfigs.size(); ++i) {
            arrayParamIn(cp, ("effPriority" + std::to_string(i)), this->effPriority[i]);
        }
        arrayParamIn(cp, "lastID", this->lastID);
        this->updateInt();
    }


    Port &getPort(const std::string &if_name, PortID idx=InvalidPortID)
    {
        return PlicBase::getPort(if_name, idx);
    }

};

}
