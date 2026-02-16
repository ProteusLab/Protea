require_relative '../SDL/plod'

module System

  Struct(:fifo8) {
    Method(:init) {
      front[]= 0
      size[]= 0
    }

    Method(:push, value: b8) {
      buf.set((front + size) % buf.plod_type.size, value)
      size[]= size + 1
    }

    Method(:pop, ret: b8) {
      var :valToRet, b8

      valToRet[]= buf.get(front)
      front[]= (front + 1) % buf.plod_type.size
      size[]= size - 1
      ret valToRet
    }

    Method(:is_empty, ret: b1) {
      let :empty, b1, size == 0
      ret empty
    }

    Field(:buf, array(b8, 8))
    Field(:front, int)
    Field(:size, int)
  }

  Device(:ns16550) {
    Register(:rbr) {
      size 0x1
      offset 0x0
      type :ro
      enableIf { lcr.dlab == 0 }

      Method(:read) {
        let :ret_val, b8, 0

        If(fcr.fe) {
          If(mFifo.is_empty) {
            ret_val[]= 0
          }
          Else {
            ret_val[]= mFifo.pop
          }

          If(mFifo.is_empty) {
            lsr.dr[]= 0
            lsr.bi[]= 0
          }
          Else {
            ret_val[]= mFifo.pop
          }
        }
        Else {
          ret[]= rbr
          lsr.dr[]= 0
          lsr.bi[]= 0
        }

        ret ret_val
      }
    }

    Register(:thr) {
      size 0x1
      offset 0x0
      type :wo
      enableIf { lcr.dlab == 0 }
    }

    Register(:ier) {
      size 0x1
      offset 0x1
      enableIf { lcr.dlab == 0 }
    }

    Register(:iir) {
      size 0x1
      offset 0x2
      type :ro
      field :iid, 0x1, 0x3

      Method(:read) {
        If(iid == 0x2) {

        }

        ret iir
      }
    }

    Register(:fcr) {
      size 0x1
      offset 0x2
      type :wo
      field :fe, 0x0
    }

    Register(:lcr) {
      size 0x1
      offset 0x3
      field :dlab, 0x7
    }

    Register(:mcr) {
      size 0x1
      offset 0x4
    }

    Register(:lsr) {
      size 0x1
      offset 0x5
      field :dr, 0x0
      field :bi, 0x4
    }

    Register(:msr) {
      size 0x1
      offset 0x6
    }

    Register(:scr) {
      size 0x1
      offset 0x7
    }

    Register(:dll) {
      size 0x1
      offset 0x0
      enableIf { lcr.dlab == 1 }
    }

    Register(:dlm) {
      size 0x1
      offset 0x1
      enableIf { lcr.dlab == 1 }
    }

    Field(:mFifo, System.fifo8)
    Field(:mThrIpending, System.int)
  }
end
