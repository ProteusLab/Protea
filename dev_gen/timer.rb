module DevGen
  module Timer
    def self.prolog
      <<~CPP
        #include "arch/riscv/system.hh"
        #include "cpu/base.hh"
        #include "mem/packet.hh"
        #include "mem/packet_access.hh"
        #include "sim/system.hh"
        #include "arch/riscv/interrupts.hh"
        #include "dev/intpin.hh"
        #include "dev/io_device.hh"
        #include "dev/mc146818.hh"
        #include "dev/reg_bank.hh"
        #include "mem/packet.hh"
        #include "mem/packet_access.hh"
        #include "sim/system.hh"
      CPP
    end

    def self.base
      'BasicPioDevice'
    end
  end
end
