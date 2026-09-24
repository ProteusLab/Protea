      #pragma once

      #include <string>
#include <vector>

#include "base/inifile.hh"
#include "base/trace.hh"
#include "debug/Uart.hh"
#include "dev/platform.hh"
#include "mem/packet.hh"
#include "mem/packet_access.hh"
#include "sim/serialize.hh"
#include "base/bitunion.hh"
#include "base/logging.hh"
#include "dev/io_device.hh"
#include "dev/reg_bank.hh"
#include "dev/serial/uart.hh"


      namespace protea {
        auto _or(auto lhs, auto rhs) {
          return lhs | rhs;
        }

        auto _mul(auto lhs, auto rhs) {
          return lhs * rhs;
        }

        auto _add(auto lhs, auto rhs) {
          return lhs + rhs;
        }

        auto _and(auto lhs, auto rhs) {
          return lhs & rhs;
        }

        auto _eq(auto lhs, auto rhs) {
          return lhs == rhs;
        }

        auto _sub(auto lhs, auto rhs) {
          return lhs - rhs;
        }

        auto _gt(auto lhs, auto rhs) {
          return lhs > rhs;
        }

        auto _not(auto op) {
          return ~op;
        }

        bool _cast(auto op) {
          return op > 0;
        }

        template <typename BVTD, typename BVTS>
        void _insert(BVTD& dist, uint32_t lsb, uint32_t size, BVTS src) {
          BVTD cleaner = ~((((BVTD)1 << size) - 1) << lsb);
          BVTS data = ((BVTD)src & (((BVTD)1 << size) - 1)) << lsb;

          dist &= cleaner;
          dist |= data;
        }

        template <typename BVT>
        BVT _extract(BVT op, uint32_t lsb, uint32_t size) {
          return (op >> lsb) & (((BVT)1 << size) - 1);
        }
      }

      namespace gem5 {

      class Terminal;
      class Platform;

      class Uart8250 : public BasicPioDevice {

          enum interruptIds
    {
        Modem = 0,
        Tx = 1,
        Rx = 2,
        Line = 3,
    };


          uint8_t rx_int = 1;
    uint8_t tx_int = 2;
    uint8_t uart_mcr_loop = 16;

          std::function<void()> lambda_0 = [this] () {
        processIntrEvent(tx_int);
    };
    
    std::function<void()> lambda_1 = [this] () {
        processIntrEvent(rx_int);
    };


          EventFunctionWrapper txIntrEvent = EventFunctionWrapper(lambda_0, "TX");
    EventFunctionWrapper rxIntrEvent = EventFunctionWrapper(lambda_1, "RX");
    Tick lastTxInt = Tick(0);

          uint8_t rbr = 0;
    uint8_t thr = 0;
    uint8_t ier = 0;
    uint8_t iir = 0;
    uint8_t fcr = 0;
    uint8_t lcr = 0;
    uint8_t mcr = 0;
    uint8_t lsr = 0;
    uint8_t msr = 0;
    uint8_t scr = 0;
    uint8_t dll = 0;
    uint8_t dlm = 0;

          uint8_t rbr_read() {
        uint8_t data;
        data = 0;
        
        
        if (device->dataAvailable()) {
            
            
            data = device->readData();
        }
        clearIntr(rx_int);
        
        
        
        _tmp100 = protea::_extract(ier, 0, 1);
        
        
        if (protea::_and(device->dataAvailable(), )) {
            
            _tmp102 = &rxIntrEvent;
            scheduleIntr();
        }
        else {
            
            
            if (rxIntrEvent.scheduled()) {
                
                _tmp104 = &rxIntrEvent;
                deschedule();
            }
        }
        return data;
    }
    
    void rbr_write(uint8_t data) { rbr = data; }
    
    
    void thr_write(uint8_t data) {
        device->writeData(data);
        clearIntr(tx_int);
        
        _tmp108 = protea::_extract(ier, 1, 1);
        if () {
            
            _tmp109 = &txIntrEvent;
            scheduleIntr();
        }
        else {
            
            
            if (txIntrEvent.scheduled()) {
                
                _tmp111 = &txIntrEvent;
                deschedule();
            }
        }
    }
    
    uint8_t thr_read() { return thr; }
    
    
    void ier_write(uint8_t data) {
        ier = data;
        
        _tmp115 = protea::_extract(ier, 1, 1);
        if () {
            
            _tmp116 = curTick();
            
            
            
            
            
            
            if (protea::_gt(protea::_sub(, lastTxInt), protea::_mul(sim_clock::as_int::ns, 225))) {
                txIntrEvent.process();
            }
            else {
                
                _tmp121 = &txIntrEvent;
                scheduleIntr();
            }
        }
        else {
            
            
            if (txIntrEvent.scheduled()) {
                
                _tmp123 = &txIntrEvent;
                deschedule();
            }
            clearIntr(tx_int);
        }
        
        _tmp124 = protea::_extract(ier, 0, 1);
        
        
        
        
        if (protea::_and(, device->dataAvailable())) {
            
            _tmp127 = &rxIntrEvent;
            scheduleIntr();
        }
        else {
            
            
            if (rxIntrEvent.scheduled()) {
                
                _tmp129 = &rxIntrEvent;
                deschedule();
            }
            clearIntr(rx_int);
        }
    }
    
    uint8_t ier_read() { return ier; }
    
    
    uint8_t iir_read() {
        iir = 0;
        
        
        if (protea::_and(status, rx_int)) {
            
            _tmp131 = interruptIds::Rx;
            protea::_insert(iir, 1, 2, );
        }
        else {
            
            
            if (protea::_and(status, tx_int)) {
                
                _tmp133 = interruptIds::Tx;
                protea::_insert(iir, 1, 2, );
                
                
                if (txIntrEvent.scheduled()) {
                    
                    _tmp135 = &txIntrEvent;
                    deschedule();
                }
                clearIntr(tx_int);
            }
            else {
                protea::_insert(iir, 0, 1, 1);
            }
        }
        return iir;
    }
    
    void iir_write(uint8_t data) { iir = data; }
    
    
    
    uint8_t fcr_read() { return fcr; }
    
    void fcr_write(uint8_t data) { fcr = data; }
    
    
    
    uint8_t lcr_read() { return lcr; }
    
    void lcr_write(uint8_t data) { lcr = data; }
    
    
    void mcr_write(uint8_t data) {
        
        
        
        
        if (protea::_eq(data, protea::_or(uart_mcr_loop, 10))) {
            mcr = 154;
        }
    }
    
    uint8_t mcr_read() { return mcr; }
    
    
    uint8_t lsr_read() {
        lsr = 0;
        
        
        if (device->dataAvailable()) {
            protea::_insert(lsr, 0, 1, 1);
        }
        protea::_insert(lsr, 5, 1, 1);
        protea::_insert(lsr, 6, 1, 1);
        return lsr;
    }
    
    void lsr_write(uint8_t data) { lsr = data; }
    
    
    
    uint8_t msr_read() { return msr; }
    
    void msr_write(uint8_t data) { msr = data; }
    
    
    
    uint8_t scr_read() { return scr; }
    
    void scr_write(uint8_t data) { scr = data; }
    
    
    
    uint8_t dll_read() { return dll; }
    
    void dll_write(uint8_t data) { dll = data; }
    
    
    
    uint8_t dlm_read() { return dlm; }
    
    void dlm_write(uint8_t data) { dlm = data; }
    


      public:

          void dataAvailable() {
        
        _tmp72 = protea::_extract(ier, 0, 1);
        if () {
            platform->postConsoleInt();
            
            
            status = protea::_or(status, rx_int);
        }
    }
    
    bool intStatus() {
        
        _tmp74 = protea::_cast(status);
        return ;
    }
    
    void processIntrEvent(int interBit) {
        
        
        if (protea::_and(interBit, ier)) {
            platform->postConsoleInt();
            
            
            status = protea::_or(status, interBit);
            
            _tmp77 = curTick();
            lastTxInt = ;
        }
    }
    
    void scheduleIntr(Event* event) {
        
        
        Tick interval;
        interval = protea::_mul(sim_clock::as_int::ns, 225);
        
        
        
        
        if (protea::_eq(event->scheduled(), 0)) {
            
            _tmp83 = curTick();
            
            
            schedule(event, protea::_add(, interval));
        }
        else {
            
            _tmp85 = curTick();
            
            
            reschedule(event, protea::_add(, interval));
        }
    }
    
    void clearIntr(uint8_t intrBit) {
        
        
        
        
        if (protea::_eq(protea::_and(status, intrBit), 0)) {
            return;
        }
        
        _tmp90 = protea::_not(intrBit);
        
        
        status = protea::_and(status, );
        
        
        if (protea::_eq(status, 0)) {
            platform->clearConsoleInt();
        }
    }


          Uart8250(const Uart8250Params &params)
            : BasicPioDevice(params, params.pio_size) {
      
            }

          Tick read(PacketPtr pkt) override {
            uint64_t daddr = pkt->getAddr() - pioAddr;
            uint8_t* data_ptr = pkt->getPtr<uint8_t>();

            if (0 <= daddr && daddr < 0 + 1) {
        uint8_t read_data;
        
      _tmp94 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp96) {
          read_data = rbr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (0 <= daddr && daddr < 0 + 1) {
        uint8_t read_data;
        
      _tmp105 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp107) {
          read_data = thr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t read_data;
        
      _tmp112 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp114) {
          read_data = ier_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (2 <= daddr && daddr < 2 + 1) {
        uint8_t read_data;
        
        uint64_t cid = (daddr - 2) / 1;
        if (true) {
          read_data = iir_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (2 <= daddr && daddr < 2 + 1) {
        uint8_t read_data;
        
        uint64_t cid = (daddr - 2) / 1;
        if (true) {
          read_data = fcr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (3 <= daddr && daddr < 3 + 1) {
        uint8_t read_data;
        
        uint64_t cid = (daddr - 3) / 1;
        if (true) {
          read_data = lcr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (4 <= daddr && daddr < 4 + 1) {
        uint8_t read_data;
        
        uint64_t cid = (daddr - 4) / 1;
        if (true) {
          read_data = mcr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (5 <= daddr && daddr < 5 + 1) {
        uint8_t read_data;
        
        uint64_t cid = (daddr - 5) / 1;
        if (true) {
          read_data = lsr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (6 <= daddr && daddr < 6 + 1) {
        uint8_t read_data;
        
        uint64_t cid = (daddr - 6) / 1;
        if (true) {
          read_data = msr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (7 <= daddr && daddr < 7 + 1) {
        uint8_t read_data;
        
        uint64_t cid = (daddr - 7) / 1;
        if (true) {
          read_data = scr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (0 <= daddr && daddr < 0 + 1) {
        uint8_t read_data;
        
      _tmp140 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp142) {
          read_data = dll_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t read_data;
        
      _tmp143 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp145) {
          read_data = dlm_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }


            bool is_atomic = pkt->isAtomicOp() && pkt->cmd == MemCmd::SwapReq;

            if (is_atomic) {
                (*(pkt->getAtomicOp()))(pkt->getPtr<uint8_t>());
                return write(pkt);
            } else {
                pkt->makeResponse();
                return pioDelay;
            }
          }

          Tick write(PacketPtr pkt) {
            Addr daddr = pkt->getAddr() - pioAddr;
            uint8_t* data_ptr = *pkt->getPtr<uint8_t>();

            if (0 <= daddr && daddr < 0 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp94 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp96) {
          rbr_write(write_data);
        }
      }
      if (0 <= daddr && daddr < 0 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp105 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp107) {
          thr_write(write_data);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp112 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp114) {
          ier_write(write_data);
        }
      }
      if (2 <= daddr && daddr < 2 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
        uint64_t cid = (daddr - 2) / 1;
        if (true) {
          iir_write(write_data);
        }
      }
      if (2 <= daddr && daddr < 2 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
        uint64_t cid = (daddr - 2) / 1;
        if (true) {
          fcr_write(write_data);
        }
      }
      if (3 <= daddr && daddr < 3 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
        uint64_t cid = (daddr - 3) / 1;
        if (true) {
          lcr_write(write_data);
        }
      }
      if (4 <= daddr && daddr < 4 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
        uint64_t cid = (daddr - 4) / 1;
        if (true) {
          mcr_write(write_data);
        }
      }
      if (5 <= daddr && daddr < 5 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
        uint64_t cid = (daddr - 5) / 1;
        if (true) {
          lsr_write(write_data);
        }
      }
      if (6 <= daddr && daddr < 6 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
        uint64_t cid = (daddr - 6) / 1;
        if (true) {
          msr_write(write_data);
        }
      }
      if (7 <= daddr && daddr < 7 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
        uint64_t cid = (daddr - 7) / 1;
        if (true) {
          scr_write(write_data);
        }
      }
      if (0 <= daddr && daddr < 0 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp140 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp142) {
          dll_write(write_data);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp143 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp145) {
          dlm_write(write_data);
        }
      }


            pkt->makeResponse();
            return pioDelay;
          }

          AddrRangeList getAddrRanges() const
          {
              AddrRangeList ranges;
              ranges.push_back(RangeSize(pioAddr, pioSize));
              return ranges;
          }

          void serialize(CheckpointOut &cp) const override {}
          void unserialize(CheckpointIn &cp) override {}

          Port &
          Uart8250::getPort(const std::string &if_name, PortID idx)
          {
        return BasicPioDevice::getPort(if_name, idx);
          }

          void
          Uart8250::init()
          {
        BasicPioDevice::init();
          }
      };

      }
