/*
 * Copyright (c) 2021 Huawei International
 * Copyright (c) 2016-2018 ARM Limited
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

#include <array>
#include <cstring>
#include <functional>
#include <map>
#include <string>
#include <vector>
#include "base/logging.hh"
#include "dev/riscv/plic_device.hh"
#include "dev/virtio/base.hh"
#include "mem/packet_access.hh"
#include "params/RiscvMmioVirtIO.hh"

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

namespace gem5::RiscvISA {


class MmioVirtIO : public PlicIntDevice {
    uint32_t magic = 1953655158;
    uint32_t version = 1;
    uint32_t vendor_id = 6900;
    uint32_t align_size = 4096;
    uint32_t int_used_ring = 1;
    uint32_t int_config = 2;

    std::function<void()> lambda_0 = [this]() {
        kick();
    };

    uint32_t hostFeaturesSelect;
    uint32_t guestFeaturesSelect;
    uint32_t pageSize;
    uint32_t interruptStatus;
    VirtIODeviceBase* vio;
    std::function<void()> kickCallback = lambda_0;

    uint32_t magic_value = 0;
    uint32_t version_value = 0;
    uint32_t device_id = 0;
    uint32_t vendor = 0;
    uint32_t host_features = 0;
    uint32_t host_features_select = 0;
    uint32_t guest_features = 0;
    uint32_t guest_features_select = 0;
    uint32_t guest_page_size = 0;
    uint32_t queue_select = 0;
    uint32_t queue_num_max = 0;
    uint32_t queue_num = 0;
    uint32_t queue_align = 0;
    uint32_t queue_pfn = 0;
    uint32_t queue_notify = 0;
    uint32_t interrupt_status = 0;
    uint32_t interrupt_ack = 0;
    uint32_t status = 0;


    uint32_t magic_value_read() {
        return magic;
    }

    void magic_value_write(uint32_t data) { magic_value = data; }

    uint32_t version_value_read() {
        return version;
    }

    void version_value_write(uint32_t data) { version_value = data; }

    uint32_t device_id_read() {
        return vio->deviceId;
    }

    void device_id_write(uint32_t data) { device_id = data; }

    uint32_t vendor_read() {
        return vendor_id;
    }

    void vendor_write(uint32_t data) { vendor = data; }

    uint32_t host_features_read() {
        if ((hostFeaturesSelect == 0)) {
            return vio->deviceFeatures;
        }
        return 0;
    }

    void host_features_write(uint32_t data) { host_features = data; }

    uint32_t host_features_select_read() {
        return hostFeaturesSelect;
    }

    void host_features_select_write(uint32_t data) {
        hostFeaturesSelect = data;
    }

    uint32_t guest_features_read() {
        if ((guestFeaturesSelect == 0)) {
            return vio->getGuestFeatures();
        }
        return 0;
    }

    void guest_features_write(uint32_t data) {
        if ((guestFeaturesSelect == 0)) {
            vio->setGuestFeatures(data);
        } else if ((data != 0)) {
            warn("Setting unimplemented guest features register");
        }
    }

    uint32_t guest_features_select_read() {
        return hostFeaturesSelect;
    }

    void guest_features_select_write(uint32_t data) {
        guestFeaturesSelect = data;
    }

    uint32_t guest_page_size_read() {
        return pageSize;
    }

    void guest_page_size_write(uint32_t data) {
        panic_if((data != align_size), "Unhandled VirtIO page size");
        pageSize = data;
    }

    uint32_t queue_select_read() {
        return vio->getQueueSelect();
    }

    void queue_select_write(uint32_t data) {
        vio->setQueueSelect(data);
    }

    uint32_t queue_num_max_read() {
        return vio->getQueueSize();
    }

    void queue_num_max_write(uint32_t data) { queue_num_max = data; }

    uint32_t queue_num_read() {
        return vio->getQueueSize();
    }

    void queue_num_write(uint32_t data) {
        warn_once("Ignoring queue resize hint");
    }

    uint32_t queue_align_read() {
        return align_size;
    }

    void queue_align_write(uint32_t data) {
        panic_if((data != align_size), "Unhandled VirtIO alignment size");
    }

    uint32_t queue_pfn_read() {
        return vio->getQueueAddress();
    }

    void queue_pfn_write(uint32_t data) {
        vio->setQueueAddress(data);
    }

    void queue_notify_write(uint32_t data) {
        vio->onNotify(data);
    }

    uint32_t queue_notify_read() { return queue_notify; }

    uint32_t interrupt_status_read() {
        return interruptStatus;
    }

    void interrupt_status_write(uint32_t data) { interrupt_status = data; }

    void interrupt_ack_write(uint32_t data) {
        setInterrupts((interruptStatus & (~data)));
    }

    uint32_t interrupt_ack_read() { return interrupt_ack; }

    uint32_t status_read() {
        return vio->getDeviceStatus();
    }

    void status_write(uint32_t data) {
        panic_if((data > 255), "Unexpected status");
        vio->setDeviceStatus(data);
    }

    public:

    using Params = RiscvMmioVirtIOParams;
    void kick() {
        setInterrupts((interruptStatus | int_used_ring));
    }

    void setInterrupts(uint32_t value) {
        uint32_t old_ints;
        old_ints = interruptStatus;
        interruptStatus = value;
        if (((old_ints == 0) & (interruptStatus != 0))) {
            platform->postPciInt(_interruptID);
        } else if (((old_ints != 0) & (interruptStatus == 0))) {
            platform->clearPciInt(_interruptID);
        }
    }

    MmioVirtIO(const RiscvMmioVirtIOParams &params)
        : PlicIntDevice(params), hostFeaturesSelect(0), guestFeaturesSelect(0), pageSize(0), interruptStatus(0), vio(params.vio) {
        vio->registerKickCallback(kickCallback);
    }

    Tick read(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        if (daddr >= 256) {
            this->vio->readConfig(pkt, daddr - 256);
            return 0;
        }
        panic_if(!(pkt->getSize() == 4), "Unexpected access size");
        bool matched = false;
        uint32_t read_data = 0;
        bool has_data = false;
        if (!matched && (daddr == 0)) {
            matched = true;
            read_data = magic_value_read();
            has_data = true;
        }
        if (!matched && (daddr == 4)) {
            matched = true;
            read_data = version_value_read();
            has_data = true;
        }
        if (!matched && (daddr == 8)) {
            matched = true;
            read_data = device_id_read();
            has_data = true;
        }
        if (!matched && (daddr == 12)) {
            matched = true;
            read_data = vendor_read();
            has_data = true;
        }
        if (!matched && (daddr == 16)) {
            matched = true;
            read_data = host_features_read();
            has_data = true;
        }
        if (!matched && (daddr == 20)) {
            matched = true;
            read_data = host_features_select_read();
            has_data = true;
        }
        if (!matched && (daddr == 32)) {
            matched = true;
            read_data = guest_features_read();
            has_data = true;
        }
        if (!matched && (daddr == 36)) {
            matched = true;
            read_data = guest_features_select_read();
            has_data = true;
        }
        if (!matched && (daddr == 40)) {
            matched = true;
            read_data = guest_page_size_read();
            has_data = true;
        }
        if (!matched && (daddr == 48)) {
            matched = true;
            read_data = queue_select_read();
            has_data = true;
        }
        if (!matched && (daddr == 52)) {
            matched = true;
            read_data = queue_num_max_read();
            has_data = true;
        }
        if (!matched && (daddr == 56)) {
            matched = true;
            read_data = queue_num_read();
            has_data = true;
        }
        if (!matched && (daddr == 60)) {
            matched = true;
            read_data = queue_align_read();
            has_data = true;
        }
        if (!matched && (daddr == 64)) {
            matched = true;
            read_data = queue_pfn_read();
            has_data = true;
        }
        if (!matched && (daddr == 96)) {
            matched = true;
            read_data = interrupt_status_read();
            has_data = true;
        }
        if (!matched && (daddr == 112)) {
            matched = true;
            read_data = status_read();
            has_data = true;
        }
        if (!matched && (daddr == 80)) {
            matched = true;
            warn("Guest is trying to read a write-only register");
            read_data = 0;
            has_data = true;
        }
        if (!matched && (daddr == 100)) {
            matched = true;
            warn("Guest is trying to read a write-only register");
            read_data = 0;
            has_data = true;
        }
        panic_if(!matched, "Unhandled read address");
        pkt->makeResponse();
        if (has_data) pkt->setLE<uint32_t>(read_data);
        return 0;
    }

    Tick write(PacketPtr pkt) override {
        Addr daddr = pkt->getAddr() - pioAddr;
        if (daddr >= 256) {
            this->vio->writeConfig(pkt, daddr - 256);
            return 0;
        }
        panic_if(!(pkt->getSize() == 4), "Unexpected access size");
        pkt->makeResponse();
        bool matched = false;
        if (!matched && (daddr == 20)) {
            matched = true;
            host_features_select_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 32)) {
            matched = true;
            guest_features_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 36)) {
            matched = true;
            guest_features_select_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 40)) {
            matched = true;
            guest_page_size_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 48)) {
            matched = true;
            queue_select_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 56)) {
            matched = true;
            queue_num_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 60)) {
            matched = true;
            queue_align_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 64)) {
            matched = true;
            queue_pfn_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 80)) {
            matched = true;
            queue_notify_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 100)) {
            matched = true;
            interrupt_ack_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 112)) {
            matched = true;
            status_write(pkt->getLE<uint32_t>());
        }
        if (!matched && (daddr == 0)) {
            matched = true;
            warn("Guest is trying to write a read-only register");
        }
        if (!matched && (daddr == 4)) {
            matched = true;
            warn("Guest is trying to write a read-only register");
        }
        if (!matched && (daddr == 8)) {
            matched = true;
            warn("Guest is trying to write a read-only register");
        }
        if (!matched && (daddr == 12)) {
            matched = true;
            warn("Guest is trying to write a read-only register");
        }
        if (!matched && (daddr == 16)) {
            matched = true;
            warn("Guest is trying to write a read-only register");
        }
        if (!matched && (daddr == 52)) {
            matched = true;
            warn("Guest is trying to write a read-only register");
        }
        if (!matched && (daddr == 96)) {
            matched = true;
            warn("Guest is trying to write a read-only register");
        }
        panic_if(!matched, "Unhandled write address");
        return 0;
    }

    AddrRangeList getAddrRanges() const
    {
        AddrRangeList ranges;
        ranges.push_back(RangeSize(pioAddr, pioSize));
        return ranges;
    }

    void serialize(CheckpointOut& cp) const override {
        PlicIntDevice::serialize(cp);
    }

    void unserialize(CheckpointIn& cp) override {
        PlicIntDevice::unserialize(cp);
    }


    Port &getPort(const std::string &if_name, PortID idx=InvalidPortID)
    {
        return PlicIntDevice::getPort(if_name, idx);
    }

    void init()
    {
        PlicIntDevice::init();
    }
};

}
