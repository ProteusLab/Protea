#pragma once
#include "gem5_stub.hh"
#include "base/bitunion.hh"

namespace gem5 {
class IntSourcePinBase : public Port {
  public:
    std::string pinName;
    int id, raises = 0, lowers = 0;
    bool high = false;
    template <typename D> IntSourcePinBase(const std::string& name, int index, D*) : pinName(name), id(index) {}
    void raise() { ++raises; high = true; }
    void lower() { ++lowers; high = false; }
};
class IntSinkPinBase : public Port {
  public:
    int id;
    bool high = false;
    std::function<void(int)> onRaise, onLower;
    template <typename D> IntSinkPinBase(const std::string&, int index, D* dev) : id(index),
        onRaise([dev](int i) { dev->raiseInterruptPin(i); }),
        onLower([dev](int i) { dev->lowerInterruptPin(i); }) {}
    int getId() const { return id; }
    bool state() const { return high; }
    void set(bool value) { if (value != high) { high = value; (value ? onRaise : onLower)(id); } }
};
template <typename D> using IntSourcePin = IntSourcePinBase;
template <typename D> using IntSinkPin = IntSinkPinBase;
namespace ps2 {
class Device {
  public:
    std::deque<uint8_t> pending;
    std::vector<uint8_t> writes;
    std::vector<uint8_t> response;
    void hostWrite(uint8_t data) { writes.push_back(data); for (auto b : response) pending.push_back(b); }
    bool hostDataAvailable() const { return !pending.empty(); }
    uint8_t hostRead() { assert(!pending.empty()); auto data = pending.front(); pending.pop_front(); return data; }
};
}
namespace enums { enum X86I8259CascadeMode { I8259Master, I8259Slave, I8259Single }; }
namespace X86ISA {
class I8259;
constexpr Addr PhysAddrIntA = 0xa000000000000000ULL;
constexpr int APIC_LOGICAL_DESTINATION = 3;
class Interrupts : public BaseInterrupts {
  public:
    uint32_t logicalDestination = 0;
    int initialApicId = 0;
    uint32_t readReg(int reg) { assert(reg == APIC_LOGICAL_DESTINATION); return logicalDestination << 24; }
    int getInitialApicId() { return initialApicId; }
};
BitUnion32(TriggerIntMessage)
    Bitfield<7, 0> destination;
    Bitfield<15, 8> vector;
    Bitfield<18, 16> deliveryMode;
    Bitfield<19> destMode;
    Bitfield<20> level;
    Bitfield<21> trigger;
EndBitUnion(TriggerIntMessage)
namespace delivery_mode { enum IntDeliveryMode { Fixed=0, LowestPriority=1, ExtInt=7 }; }
inline PacketPtr buildIntAcknowledgePacket() { return new Packet(PhysAddrIntA, 1); }
inline PacketPtr buildIntTriggerPacket(int id, TriggerIntMessage message) {
    auto pkt = new Packet(0xb000000000000000ULL + id, 4); pkt->setLE<uint32_t>(message); return pkt;
}
struct InterruptRecord { Tick tick; Addr address; uint32_t message; bool timing; };
inline std::vector<InterruptRecord> interruptRecords;
inline std::function<uint8_t()> acknowledge = [] { return 0x41; };
template <typename D> class IntRequestPort : public Port {
  public:
    Tick latency;
    bool connected = true;
    std::vector<std::unique_ptr<EventFunctionWrapper>> pending;
    IntRequestPort(const std::string&, SimObject*, D*, Tick delay) : latency(delay) {}
    bool isConnected() const { return connected; }
    void sendMessage(PacketPtr pkt, bool timing, std::function<void(PacketPtr)> callback = [](PacketPtr pkt) { delete pkt; }) {
        auto deliver = [pkt, timing, callback] {
            if (pkt->getAddr() == PhysAddrIntA) pkt->setLE<uint8_t>(acknowledge());
            interruptRecords.push_back({curTick(), pkt->getAddr(), pkt->payload.size() == 1 ? pkt->getLE<uint8_t>() : pkt->getLE<uint32_t>(), timing});
            callback(pkt);
        };
        if (timing) {
            pending.push_back(std::make_unique<EventFunctionWrapper>(deliver));
            gem5::schedule(*pending.back(), curTick() + latency);
        } else deliver();
    }
};
}
class I8237Params : public SimObjectParams {};
class I8254Params : public SimObjectParams { public: int port_int_pin_connection_count = 2; };
class I8042Params : public SimObjectParams {
  public:
    Addr data_port = 0x60, command_port = 0x64;
    ps2::Device* mouse = nullptr;
    ps2::Device* keyboard = nullptr;
    int port_mouse_int_pin_connection_count = 2, port_keyboard_int_pin_connection_count = 2;
};
class I8259Params : public SimObjectParams {
  public:
    enums::X86I8259CascadeMode mode = enums::I8259Single;
    X86ISA::I8259* slave = nullptr;
    int port_output_connection_count = 2, port_inputs_connection_count = 8;
};
class I82094AAParams : public SimObjectParams {
  public:
    int apic_id = 1;
    Tick int_latency = 5;
    int port_inputs_connection_count = 24;
};
}
