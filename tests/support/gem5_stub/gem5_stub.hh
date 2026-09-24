#pragma once

#include <array>
#include <cstdint>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

namespace gem5
{

using Tick = uint64_t;
using Addr = uint64_t;
using PortID = int;

namespace sim_clock
{
    namespace as_int
    {
        constexpr Tick ns = 1000;
    }
}

inline Tick curTick() { return 0; }
inline void warn(const std::string &) {}

class Event
{
  public:
    virtual ~Event() = default;
    bool scheduled() const { return false; }
    void process() {}
};

class EventFunctionWrapper : public Event
{
  public:
    EventFunctionWrapper(std::function<void()> f, const std::string &n = "") {}
};

class SerialDevice
{
  public:
    virtual ~SerialDevice() = default;
    virtual bool dataAvailable() { return false; }
    virtual uint8_t readData() { return 0; }
    virtual void writeData(uint8_t) {}
};

class Platform
{
  public:
    void postConsoleInt() {}
    void clearConsoleInt() {}
};

class Terminal;

inline void schedule(Event *, Tick) {}
inline void reschedule(Event *, Tick) {}
inline void deschedule(Event *) {}

struct MemCmd
{
    enum Value { SwapReq, ReadReq, WriteReq };
    Value v = ReadReq;
    bool operator==(Value other) const { return v == other; }
};

class AtomicOp
{
  public:
    void operator()(uint8_t *) {}
};

class Packet
{
  public:
    Addr getAddr() const { return 0; }
    template <typename T> T *getPtr() { return nullptr; }
    bool isAtomicOp() const { return false; }
    AtomicOp *getAtomicOp() { return nullptr; }
    void makeResponse() {}
    MemCmd cmd{};
};

using PacketPtr = Packet *;

struct AddrRange {};
using AddrRangeList = std::vector<AddrRange>;

inline AddrRange RangeSize(Addr, Addr) { return {}; }

class Port
{
  public:
    virtual ~Port() = default;
};

class CheckpointOut;
class CheckpointIn;

class SimObjectParams
{
  public:
    std::string name;
};

class SimObject
{
  public:
    virtual ~SimObject() = default;
    virtual void init() {}
    virtual Port &getPort(const std::string &if_name, PortID idx);
    virtual void serialize(CheckpointOut &cp) const {}
    virtual void unserialize(CheckpointIn &cp) {}
};

class BasicPioDevice : public SimObject
{
  public:
    BasicPioDevice(const SimObjectParams &p, Addr size) : pioSize(size) {}
    Addr pioAddr = 0;
    Addr pioSize = 0;
    Tick pioDelay = 0;
    virtual Tick read(PacketPtr pkt) = 0;
    virtual Tick write(PacketPtr pkt) = 0;
};

class ThreadContext;
class BaseCPU
{
  public:
    virtual ~BaseCPU() = default;
    void postInterrupt(int, int, int) {}
    void clearInterrupt(int, int, int) {}
};

class ThreadContext
{
  public:
    BaseCPU *getCpuPtr() { return nullptr; }
    int threadId() const { return 0; }
};

class System
{
  public:
    virtual ~System() = default;
    class Threads
    {
      public:
        ThreadContext *operator[](int) { return nullptr; }
    };
    Threads threads;
};

class RiscvSystem : public System
{
  public:
    void setClint(SimObject *) {}
};

class IntSinkPinClint : public Port
{
  public:
    IntSinkPinClint(const std::string &, int, SimObject *, int) {}
};

class SignalSinkPortBool : public Port
{
  public:
    SignalSinkPortBool(const std::string &) {}
    void onChange(std::function<void(bool)>) {}
};

class ClintParams : public SimObjectParams
{
  public:
    uint64_t mtimecmp_reset_value = 0;
    uint32_t num_threads = 0;
    uint64_t pio_size = 0;
    bool reset_mtimecmp = false;
    uint32_t port_int_pin_connection_count = 0;
    uint32_t port_reset_connection_count = 0;
    System *system = nullptr;
};

class Uart8250Params : public SimObjectParams
{
  public:
    uint64_t pio_size = 0;
};

class ns16550Params : public SimObjectParams
{
  public:
    uint64_t pio_size = 0;
};

} // namespace gem5
