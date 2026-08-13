module DevGen
  module Uart
    def self.prolog
      <<~CPP
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
      CPP
    end

    def self.base
      'BasicPioDevice'
    end

    def self.port_body
      "return #{base}::getPort(if_name, idx);"
    end

    def self.init_body
      "#{base}::init();"
    end
  end
end
