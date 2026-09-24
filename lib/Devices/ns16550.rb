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

  Method(:pop, Ret: B8()) {
    Var :valToRet, B8()

    valToRet[] = buf.get(front)
    front[] = (front + 1) % buf.type.size
    size[] = size - 1
    Return valToRet
  }

  Method(:is_empty, Ret: B1()) {
    Let :empty, B1(), size == 0
    Return empty
  }

  Field(:buf, Array(B8(), 8))
  Field(:front, Int())
  Field(:size, Int())
}

Device(:ns16550) {
  Register(:rbr) {
    Size 0x1
    Offset 0x0
    Type :ro
    EnableIf { lcr.dlab == 0 }

    Method(:read, Ret: B8()) {
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
    Size 0x1
    Offset 0x0
    Type :wo
    EnableIf { lcr.dlab == 0 }
  }

  Register(:ier) {
    Size 0x1
    Offset 0x1
    EnableIf { lcr.dlab == 0 }
  }

  Register(:iir) {
    Size 0x1
    Offset 0x2
    Type :ro
    Field :iid, 0x1, 0x3

    Method(:read, Ret: B8()) {
      If(iid == 0x2) {
      }

      Return this
    }
  }

  Register(:fcr) {
    Size 0x1
    Offset 0x2
    Type :wo
    Field :fe, 0x0
  }

  Register(:lcr) {
    Size 0x1
    Offset 0x3
    Field :dlab, 0x7
  }

  Register(:mcr) {
    Size 0x1
    Offset 0x4
  }

  Register(:lsr) {
    Size 0x1
    Offset 0x5
    Field :dr, 0x0
    Field :bi, 0x4
  }

  Register(:msr) {
    Size 0x1
    Offset 0x6
  }

  Register(:scr) {
    Size 0x1
    Offset 0x7
  }

  Register(:dll) {
    Size 0x1
    Offset 0x0
    EnableIf { lcr.dlab == 1 }
  }

  Register(:dlm) {
    Size 0x1
    Offset 0x1
    EnableIf { lcr.dlab == 1 }
  }

  Field(:mFifo, fifo8)
  Field(:mThrIpending, Int())
}
