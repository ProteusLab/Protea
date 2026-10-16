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

      class ns16550 : public BasicPioDevice {

          

          

          

          fifo8 mFifo;
    int mThrIpending;

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

          void rbr_read() {
        uint8_t ret_val;
        ret_val = 0;
        
        _tmp49 = protea::_extract(fcr, 0, 1);
        if () {
            
            _tmp50 = {name: :mFifo, type: :fifo8, regset: nil}(is_empty);
            if () {
                ret_val = 0;
            }
            else {
                
                _tmp51 = {name: :mFifo, type: :fifo8, regset: nil}(pop);
                ret_val = ;
            }
            
            _tmp52 = {name: :mFifo, type: :fifo8, regset: nil}(is_empty);
            if () {
                
                _tmp53 = protea::_extract(lsr, 0, 1);
                
                
                _tmp54 = protea::_extract(lsr, 4, 1);
            
            }
            else {
                
                _tmp55 = {name: :mFifo, type: :fifo8, regset: nil}(pop);
                ret_val = ;
            }
        }
        else {
            ret_val = rbr;
            
            _tmp56 = protea::_extract(lsr, 0, 1);
            
            
            _tmp57 = protea::_extract(lsr, 4, 1);
        
        }
        return ret_val;
    }
    
    void rbr_write(uint8_t data) { rbr = data; }
    
    
    
    uint8_t thr_read() { return thr; }
    
    void thr_write(uint8_t data) { thr = data; }
    
    
    
    uint8_t ier_read() { return ier; }
    
    void ier_write(uint8_t data) { ier = data; }
    
    
    void iir_read() {
        
        
        if (protea::_eq(iid, 2)) {
            
        }
        return iir;
    }
    
    void iir_write(uint8_t data) { iir = data; }
    
    
    
    uint8_t fcr_read() { return fcr; }
    
    void fcr_write(uint8_t data) { fcr = data; }
    
    
    
    uint8_t lcr_read() { return lcr; }
    
    void lcr_write(uint8_t data) { lcr = data; }
    
    
    
    uint8_t mcr_read() { return mcr; }
    
    void mcr_write(uint8_t data) { mcr = data; }
    
    
    
    uint8_t lsr_read() { return lsr; }
    
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

          

          ns16550(const ns16550Params &params)
            : BasicPioDevice(params, params.pio_size) {
      
            }

          Tick read(PacketPtr pkt) override {
            uint64_t daddr = pkt->getAddr() - pioAddr;
            uint8_t* data_ptr = pkt->getPtr<uint8_t>();

            if (0 <= daddr && daddr < 0 + 1) {
        uint8_t read_data;
        
      _tmp46 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp48) {
          read_data = rbr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (0 <= daddr && daddr < 0 + 1) {
        uint8_t read_data;
        
      _tmp58 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp60) {
          read_data = thr_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t read_data;
        
      _tmp61 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp63) {
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
        
      _tmp66 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp68) {
          read_data = dll_read();
          std::memcpy(data_ptr, &read_data, 1);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t read_data;
        
      _tmp69 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp71) {
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
        
      _tmp46 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp48) {
          rbr_write(write_data);
        }
      }
      if (0 <= daddr && daddr < 0 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp58 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp60) {
          thr_write(write_data);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp61 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp63) {
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
        
      _tmp66 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 0) / 1;
        if (_tmp68) {
          dll_write(write_data);
        }
      }
      if (1 <= daddr && daddr < 1 + 1) {
        uint8_t write_data;
        std::memcpy(&write_data, data_ptr, 1);
        
      _tmp69 = protea::_extract(lcr, 7, 1);
      
      
        uint64_t cid = (daddr - 1) / 1;
        if (_tmp71) {
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
          ns16550::getPort(const std::string &if_name, PortID idx)
          {
        return BasicPioDevice::getPort(if_name, idx);
          }

          void
          ns16550::init()
          {
        BasicPioDevice::init();
          }
      };

      }
