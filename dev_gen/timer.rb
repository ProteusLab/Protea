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

    def self.port_body
      <<~CPP.chomp
        if (if_name == "int_pin")
            return signal;
        else if (if_name == "reset")
            return reset;
        else
            return #{base}::getPort(if_name, idx);
      CPP
    end

    def self.init_body
      <<~CPP.chomp
        reg_init();
        #{base}::init();

        RiscvSystem *rv_sys = dynamic_cast<RiscvSystem *>(system);
        if (rv_sys != nullptr) {
            rv_sys->setClint(this);
        } else {
            warn("Set Clint to RiscvSystem failed.");
        }
      CPP
    end
  end
end
