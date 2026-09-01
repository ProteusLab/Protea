# frozen_string_literal: true

Struct(:fifo8) {
  Method(:init) {
    front[] = 0
    size[] = 0
  }

  Method(:push, value: B8()) {
    buf.set((front + size) % buf.type.size, value)
    size[] = size + 1
  }

  Method(:pop, ret: B8()) {
    Var :valToRet, B8()

    valToRet[] = buf.get(front)
    front[] = (front + 1) % buf.type.size
    size[] = size - 1
    Return valToRet
  }

  Method(:is_empty, ret: B1()) {
    Let :empty, B1(), size == 0
    Return empty
  }

  Field(:buf, Array(B8(), 8))
  Field(:front, Int())
  Field(:size, Int())
}

Device(:ns16550) {
  Register(:rbr) {
    size 0x1
    offset 0x0
    type :ro
    enableIf { lcr.dlab == 0 }

    Method(:read, ret: B8()) {
      Let :ret_val, B8(), 0

      If(fcr.fe) {
        If(mFifo.is_empty) {
          ret_val[] = 0
        }
        Else {
          ret_val[] = mFifo.pop
        }

        If(mFifo.is_empty) {
          lsr.dr[] = 0
          lsr.bi[] = 0
        }
        Else {
          ret_val[] = mFifo.pop
        }
      }
      Else {
        ret_val[] = rbr
        lsr.dr[] = 0
        lsr.bi[] = 0
      }

      Return ret_val
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
    Field :iid, 0x1, 0x3

    Method(:read, ret: B8()) {
      If(iid == 0x2) {
      }

      Return this
    }
  }

  Register(:fcr) {
    size 0x1
    offset 0x2
    type :wo
    Field :fe, 0x0
  }

  Register(:lcr) {
    size 0x1
    offset 0x3
    Field :dlab, 0x7
  }

  Register(:mcr) {
    size 0x1
    offset 0x4
  }

  Register(:lsr) {
    size 0x1
    offset 0x5
    Field :dr, 0x0
    Field :bi, 0x4
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

  Field(:mFifo, fifo8)
  Field(:mThrIpending, Int())
}
