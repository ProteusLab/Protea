#pragma once

// Executable test environment for generated devices and source gem5 fixtures.
// Scheduling, packets, IRQs and checkpoints are observable; register accesses
// use the unchanged gem5 RegisterBank implementation in dev/reg_bank.hh.
#include <algorithm>
#include <array>
#include <bit>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <functional>
#include <deque>
#include <cstdio>
#include "base/bitfield.hh"
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

#define DPRINTF(...) do {} while (0)
#define DPRINTFR(...) do {} while (0)
#define panic_if(condition, ...) do { if (condition) gem5::panic(__VA_ARGS__); } while (0)
#define fatal_if(condition, ...) do { if (condition) gem5::fatal(__VA_ARGS__); } while (0)
#define warn_once(...) do { static bool emitted = false; if (!emitted) { emitted = true; gem5::warn(__VA_ARGS__); } } while (0)
#define SERIALIZE_SCALAR(value) gem5::paramOut(cp, #value, value)
#define UNSERIALIZE_SCALAR(value) gem5::paramIn(cp, #value, value)
#define SERIALIZE_ARRAY(value, size) gem5::arrayParamOut(cp, #value, value, size)
#define UNSERIALIZE_ARRAY(value, size) gem5::arrayParamIn(cp, #value, value, size)
#define SERIALIZE_ENUM(value) gem5::paramOut(cp, #value, static_cast<int>(value))
#define UNSERIALIZE_ENUM(value) do { int v; gem5::paramIn(cp, #value, v); value = static_cast<decltype(value)>(v); } while (0)
#define SERIALIZE_CONTAINER(value) gem5::arrayParamOut(cp, #value, value)
#define UNSERIALIZE_CONTAINER(value) gem5::arrayParamIn(cp, #value, value)

namespace gem5
{
using Tick = uint64_t;
using Addr = uint64_t;
using PortID = int;
constexpr PortID InvalidPortID = -1;
inline Tick currentTick = 0;
inline Tick cyclePeriod = 10;
namespace sim_clock { namespace as_int { constexpr Tick ns = 1000; } namespace as_float { constexpr double s = 1e12; } }
inline Tick curTick() { return currentTick; }
inline std::vector<std::string> warnings;
template <typename... Args> void warn(const std::string& msg, Args&&...) { warnings.push_back(msg); }
template <typename... Args> [[noreturn]] void panic(const std::string& msg, Args&&...) { throw std::runtime_error(msg); }
template <typename... Args> [[noreturn]] void fatal(const std::string& msg, Args&&...) { throw std::runtime_error(msg); }

struct Cycles { uint64_t value; explicit Cycles(uint64_t v) : value(v) {} };
class Event;
inline std::multimap<Tick, Event*> events;
class Event
{
  public:
    bool queued = false;
    Tick _when = 0;
    Tick when() const { return _when; }
    virtual const char* description() const { return "event"; }
    virtual ~Event() {
        for (auto it = events.begin(); it != events.end();) {
            if (it->second == this) it = events.erase(it); else ++it;
        }
    }
    bool scheduled() const { return queued; }
    virtual void process() {}
};
class EventFunctionWrapper : public Event
{
    std::function<void()> callback;
  public:
    EventFunctionWrapper(std::function<void()> f, const std::string& = "") : callback(std::move(f)) {}
    void process() override { callback(); }
};
inline void schedule(Event& event, Tick when) {
    assert(!event.queued && when >= currentTick);
    event.queued = true; event._when = when; events.emplace(when, &event);
}
inline void schedule(Event* event, Tick when) { schedule(*event, when); }
inline void deschedule(Event* event) {
    for (auto it = events.begin(); it != events.end();) {
        if (it->second == event) it = events.erase(it); else ++it;
    }
    event->queued = false;
}
inline void reschedule(Event* event, Tick when) { deschedule(event); schedule(*event, when); }
inline void runUntil(Tick until) {
    while (!events.empty() && events.begin()->first <= until) {
        auto [tick, event] = *events.begin(); events.erase(events.begin());
        currentTick = tick; event->queued = false; event->process();
    }
    currentTick = until;
}

class EventManager {
  public:
    EventManager(EventManager* = nullptr) {}
    void schedule(Event& event, Tick tick) { gem5::schedule(event, tick); }
    void schedule(Event* event, Tick tick) { gem5::schedule(event, tick); }
    void deschedule(Event& event) { gem5::deschedule(&event); }
    void deschedule(Event* event) { gem5::deschedule(event); }
    void reschedule(Event* event, Tick tick) { gem5::reschedule(event, tick); }
};
template <typename... A> std::string csprintf(const char* fmt, A... args) {
    // The tested pin-name formats use a single std::string followed by int.
    auto convert = [](const auto& arg) {
        if constexpr (std::is_same_v<std::decay_t<decltype(arg)>, std::string>) return arg.c_str();
        else return arg;
    };
    char buffer[1024]; std::snprintf(buffer, sizeof(buffer), fmt, convert(args)...); return buffer;
}
template <typename T> bool to_number(const std::string& str, T& value) {
    uint64_t temp; std::istringstream is(str); if (!(is >> temp)) return false;
    value = static_cast<T>(temp); return true;
}

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
    int posts = 0, clears = 0;
    std::set<int> active;
    void postConsoleInt() {}
    void clearConsoleInt() {}
    void postPciInt(int id) { ++posts; active.insert(id); }
    void clearPciInt(int id) { ++clears; active.erase(id); }
};
class Terminal;
struct MemCmd
{
    enum Value { SwapReq, ReadReq, WriteReq };
    Value v = ReadReq;
    bool operator==(Value other) const { return v == other; }
};
class AtomicOp
{
  public:
    std::function<void(uint8_t*)> callback;
    void operator()(uint8_t* ptr) { callback(ptr); }
};
class Packet
{
  public:
    Addr address = 0;
    std::vector<uint8_t> payload;
    bool response = false;
    AtomicOp* atomic = nullptr;
    MemCmd cmd{};
    Packet(Addr addr = 0, unsigned size = 4) : address(addr), payload(size, 0) {}
    Addr getAddr() const { return address; }
    unsigned getSize() const { return payload.size(); }
    template <typename T> T* getPtr() { return reinterpret_cast<T*>(payload.data()); }
    template <typename T> T getLE() const {
        assert(sizeof(T) <= payload.size());
        T value = 0; for (unsigned i = 0; i < sizeof(T); ++i) value |= T(payload[i]) << (8 * i);
        return value;
    }
    template <typename T> void setLE(T value) {
        assert(sizeof(T) <= payload.size());
        for (unsigned i = 0; i < sizeof(T); ++i) payload[i] = uint8_t(value >> (8 * i));
    }
    bool isAtomicOp() const { return atomic != nullptr; }
    AtomicOp* getAtomicOp() { return atomic; }
    void makeResponse() { response = true; }
    void makeAtomicResponse() { response = true; }
};
using PacketPtr = Packet*;
struct AddrRange {
    Addr start = 0, end = 0;
    AddrRange() = default;
    AddrRange(Addr s, Addr e) : start(s), end(e) {}
    std::string to_string() const { return std::to_string(start) + ":" + std::to_string(end); }
};
using AddrRangeList = std::vector<AddrRange>;
inline AddrRange RangeSize(Addr base, Addr size) { return {base, base + size}; }
class Port { public: virtual ~Port() = default; };

// The native checkpoint API stores textual scalar/container values.
struct CheckpointOut { std::map<std::string, std::string> values; };
struct CheckpointIn {
    const std::map<std::string, std::string>& values;
    explicit CheckpointIn(const CheckpointOut& out) : values(out.values) {}
};
template <typename T, typename = void> struct ShowParam {
    static void show(std::ostream& os, const T& value) {
        if constexpr (requires { value.serialize(os); }) value.serialize(os);
        else if constexpr (std::is_integral_v<T>) os << +value;
        else os << value;
    }
};
template <typename T, typename = void> struct ParseParam {
    static bool parse(const std::string& str, T& value) {
        if constexpr (requires { value.unserialize(str); }) return value.unserialize(str);
        else { std::istringstream is(str); uint64_t temp; if (!(is >> temp)) return false; value = static_cast<T>(temp); return true; }
    }
};
template <typename T> void paramOut(CheckpointOut& cp, const std::string& key, const T& value) {
    std::ostringstream os; ShowParam<T>::show(os, value); cp.values[key] = os.str();
}
template <typename T> void paramIn(CheckpointIn& cp, const std::string& key, T& value) {
    if (!ParseParam<T>::parse(cp.values.at(key), value)) panic("Invalid checkpoint value");
}
template <typename V> void arrayParamOut(CheckpointOut& cp, const std::string& key, const V& values) {
    std::ostringstream os;
    bool first = true; for (const auto& value : values) {
        if (!first) os << ' '; first = false; ShowParam<typename V::value_type>::show(os, value);
    }
    cp.values[key] = os.str();
}
template <typename T> void arrayParamOut(CheckpointOut& cp, const std::string& key, const T* values, unsigned size) {
    std::ostringstream os;
    for (unsigned i = 0; i < size; ++i) { if (i) os << ' '; ShowParam<T>::show(os, values[i]); }
    cp.values[key] = os.str();
}
template <typename T> void arrayParamIn(CheckpointIn& cp, const std::string& key, T* values, unsigned size) {
    std::istringstream is(cp.values.at(key));
    for (unsigned i = 0; i < size; ++i) {
        std::string word; if (!(is >> word) || !ParseParam<T>::parse(word, values[i])) panic("Invalid checkpoint array");
    }
}
template <typename V> void arrayParamIn(CheckpointIn& cp, const std::string& key, V& values) {
    std::istringstream is(cp.values.at(key)); values.clear();
    uint64_t value; while (is >> value) values.push_back(static_cast<typename V::value_type>(value));
}
template <typename T, size_t N> void arrayParamIn(CheckpointIn& cp, const std::string& key, std::array<T,N>& values) {
    arrayParamIn(cp, key, values.data(), N);
}

class System;
class SimObjectParams { public: System* system = nullptr; std::string name = "test"; Addr pio_addr = 0; Tick pio_latency = 7; };
class SimObject : public EventManager
{
  public:
    virtual ~SimObject() = default;
    virtual void init() {}
    virtual void startup() {}
    virtual Port& getPort(const std::string&, PortID) { static Port port; return port; }
    virtual void serialize(CheckpointOut&) const {}
    virtual void unserialize(CheckpointIn&) {}
};
class PioDevice : public SimObject
{
  public:
    System* sys;
    std::string simName;
    explicit PioDevice(const SimObjectParams& p) : sys(p.system), simName(p.name) {}
    const std::string& name() const { return simName; }
    virtual Tick read(PacketPtr) = 0;
    virtual Tick write(PacketPtr) = 0;
    virtual AddrRangeList getAddrRanges() const { return {}; }
};
class BasicPioDevice : public PioDevice
{
  public:
    BasicPioDevice(const SimObjectParams& p, Addr size) : PioDevice(p), pioAddr(p.pio_addr), pioSize(size), pioDelay(p.pio_latency) {}
    Addr pioAddr = 0, pioSize = 0;
    Tick pioDelay = 0;
    uint32_t powerState = 0;
    void serialize(CheckpointOut& cp) const override { paramOut(cp, "clocked.powerState", powerState); }
    void unserialize(CheckpointIn& cp) override { paramIn(cp, "clocked.powerState", powerState); }
    Tick clockEdge(Cycles cycles) const { return ((curTick() + cyclePeriod - 1) / cyclePeriod + cycles.value) * cyclePeriod; }
    AddrRangeList getAddrRanges() const override { return {RangeSize(pioAddr, pioSize)}; }
    virtual Tick read(PacketPtr pkt) = 0;
    virtual Tick write(PacketPtr pkt) = 0;
};
class BaseInterrupts { public: virtual ~BaseInterrupts() = default; };
class BaseCPU
{
  public:
    virtual ~BaseCPU() = default;
    BaseInterrupts* interruptController = nullptr;
    BaseInterrupts* getInterruptController(int) { return interruptController; }
    std::set<std::pair<int, int>> active;
    void postInterrupt(int tid, int interrupt, int) { active.emplace(tid, interrupt); }
    void clearInterrupt(int tid, int interrupt, int) { active.erase({tid, interrupt}); }
};
class ThreadContext
{
  public:
    BaseCPU cpu;
    int tid = 0;
    BaseCPU* getCpuPtr() { return &cpu; }
    int threadId() const { return tid; }
};
class System
{
  public:
    virtual ~System() = default;
    bool timing = false;
    bool isTimingMode() const { return timing; }
    std::vector<std::unique_ptr<ThreadContext>> contexts;
    std::vector<ThreadContext*> threads;
    explicit System(unsigned n = 8) {
        for (unsigned i = 0; i < n; ++i) {
            contexts.push_back(std::make_unique<ThreadContext>());
            contexts.back()->tid = i; threads.push_back(contexts.back().get());
        }
    }
};
class RiscvSystem : public System { public: void setClint(SimObject*) {} };
class IntSinkPinClint : public Port { public: IntSinkPinClint(const std::string&, int, SimObject*, int) {} };
class SignalSinkPortBool : public Port { public: SignalSinkPortBool(const std::string&) {} void onChange(std::function<void(bool)>) {} };
class ClintParams : public SimObjectParams
{
  public:
    uint64_t mtimecmp_reset_value = 0, pio_size = 0;
    uint32_t num_threads = 0, port_int_pin_connection_count = 0, port_reset_connection_count = 0;
    bool reset_mtimecmp = false;
    System* system = nullptr;
};
class Uart8250Params : public SimObjectParams { public: uint64_t pio_size = 0; };
class ns16550Params : public SimObjectParams { public: uint64_t pio_size = 0; };
class PlicBaseParams : public SimObjectParams { public: Addr pio_size = 0x4000000; };
class PlicParams : public PlicBaseParams
{
  public:
    System* system = nullptr;
    int n_src = 65, n_contexts = 0;
    std::string hart_config = "MS,MS";
    uint64_t output_latency = 3;
};
class PlicIntDeviceParams : public SimObjectParams
{
  public:
    Addr pio_size = 0x200;
    System* system = nullptr;
    Platform* platform = nullptr;
    int interrupt_id = 8;
};
class PlicIntDevice : public BasicPioDevice
{
  protected:
    System* system;
    Platform* platform;
    int _interruptID;
  public:
    explicit PlicIntDevice(const PlicIntDeviceParams& p) : BasicPioDevice(p, p.pio_size), system(p.system), platform(p.platform), _interruptID(p.interrupt_id) {}
    const int& id() { return _interruptID; }
};
class VirtQueue { public: static constexpr Addr ALIGN_SIZE = 4096; };
class VirtIODeviceBase
{
  public:
    uint32_t deviceId = 2, deviceFeatures = 0x12345678;
    uint32_t guestFeatures = 0, address = 0;
    uint16_t queueSelect = 0, queueSize = 128, notify = 0;
    uint8_t status = 0;
    PacketPtr forwarded = nullptr;
    Addr configOffset = 0;
    bool configWrite = false;
    std::function<void()> kickCallback;
    uint32_t getGuestFeatures() const { return guestFeatures; }
    void setGuestFeatures(uint32_t value) { guestFeatures = value; }
    uint16_t getQueueSelect() const { return queueSelect; }
    void setQueueSelect(uint16_t value) { queueSelect = value; }
    uint16_t getQueueSize() const { return queueSize; }
    uint32_t getQueueAddress() const { return address; }
    void setQueueAddress(uint32_t value) { address = value; }
    uint8_t getDeviceStatus() const { return status; }
    void setDeviceStatus(uint8_t value) { status = value; }
    void onNotify(uint16_t value) { notify = value; }
    void registerKickCallback(const std::function<void()>& callback) { kickCallback = callback; }
    void readConfig(PacketPtr pkt, Addr offset) { forwarded = pkt; configOffset = offset; configWrite = false; pkt->makeResponse(); }
    void writeConfig(PacketPtr pkt, Addr offset) { forwarded = pkt; configOffset = offset; configWrite = true; pkt->makeResponse(); }
};
class RiscvMmioVirtIOParams : public PlicIntDeviceParams { public: VirtIODeviceBase* vio = nullptr; };
namespace RiscvISA { enum ExceptionCode { INT_EXT_MACHINE = 11, INT_EXT_SUPER = 9 }; }

enum class ByteOrder { little, big };
template <typename T> constexpr T htobe(T value) { return std::endian::native == std::endian::little ? std::byteswap(value) : value; }
template <typename T> constexpr T betoh(T value) { return htobe(value); }
template <typename T> constexpr T htole(T value) { return std::endian::native == std::endian::big ? std::byteswap(value) : value; }
template <typename T> constexpr T letoh(T value) { return htole(value); }
inline int divCeil(int a, int b) { return (a + b - 1) / b; }
namespace debug { class SimpleFlag { public: bool tracing() const { return false; } const char* name() const { return "stub"; } }; }
namespace trace {
    class Logger { public: template <typename... Args> void dprintf_flag(Args&&...) {} };
    inline Logger* getDebugLogger() { static Logger logger; return &logger; }
}
} // namespace gem5
