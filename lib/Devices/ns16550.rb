# frozen_string_literal: true

Struct(:fifo8) do
  Method(:init) do
    front[] = 0
    size[] = 0
  end

  Method(:push, value: B8()) do
    buf.set((front + size) % buf.type.size, value)
    size[] = size + 1
  end

  Method(:pop, ret: B8()) do
    Var :valToRet, B8()

    valToRet[] = buf.get(front)
    front[] = (front + 1) % buf.type.size
    size[] = size - 1
    Return valToRet
  end

  Method(:is_empty, ret: B1()) do
    Let :empty, B1(), size == 0
    Return empty
  end

  Field(:buf, Array(B8(), 8))
  Field(:front, Int())
  Field(:size, Int())
end

Device(:ns16550) do
  Register(:rbr) do
    size 0x1
    offset 0x0
    type :ro
    enableIf { lcr.dlab == 0 }

    Method(:read, ret: B8()) do
      Let :ret_val, B8(), 0

      If(fcr.fe) do
        If(mFifo.is_empty) do
          ret_val[] = 0
        end
        .Else do
          ret_val[] = mFifo.pop
        end

        If(mFifo.is_empty) do
          lsr.dr[] = 0
          lsr.bi[] = 0
        end
        .Else do
          ret_val[] = mFifo.pop
        end
      end
      .Else do
        ret_val[] = rbr
        lsr.dr[] = 0
        lsr.bi[] = 0
      end

      Return ret_val
    end
  end

  Register(:thr) do
    size 0x1
    offset 0x0
    type :wo
    enableIf { lcr.dlab == 0 }
  end

  Register(:ier) do
    size 0x1
    offset 0x1
    enableIf { lcr.dlab == 0 }
  end

  Register(:iir) do
    size 0x1
    offset 0x2
    type :ro
    field :iid, 0x1, 0x3

    Method(:read, ret: B8()) do
      If(iid == 0x2) do
      end

      Return this
    end
  end

  Register(:fcr) do
    size 0x1
    offset 0x2
    type :wo
    field :fe, 0x0
  end

  Register(:lcr) do
    size 0x1
    offset 0x3
    field :dlab, 0x7
  end

  Register(:mcr) do
    size 0x1
    offset 0x4
  end

  Register(:lsr) do
    size 0x1
    offset 0x5
    field :dr, 0x0
    field :bi, 0x4
  end

  Register(:msr) do
    size 0x1
    offset 0x6
  end

  Register(:scr) do
    size 0x1
    offset 0x7
  end

  Register(:dll) do
    size 0x1
    offset 0x0
    enableIf { lcr.dlab == 1 }
  end

  Register(:dlm) do
    size 0x1
    offset 0x1
    enableIf { lcr.dlab == 1 }
  end

  Field(:mFifo, fifo8)
  Field(:mThrIpending, Int())
end
