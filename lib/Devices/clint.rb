# frozen_string_literal: true

AbstractStruct(:BaseCPU) do
  Method(:postInterrupt, tid: Int(), int_num: Int(), index: Int())
  Method(:clearInterrupt, tid: Int(), int_num: Int(), index: Int())
end

AbstractStruct(:ThreadContext) do
  Method(:getCpuPtr, ret: Ptr(BaseCPU()))
  Method(:threadId, ret: Int())
end

AbstractStruct(:Threads) do
  Method(:at, id: Int(), ret: Ptr(ThreadContext()))
end

AbstractStruct(:System) do
  Field(:threads, Threads())
end

AbstractStruct(:ClintParams) do
  Field(:mtimecmp_reset_value, B64())
  Field(:num_threads, B32())
  Field(:pio_size, B64())
  Field(:reset_mtimecmp, Bool())
  Field(:port_int_pin_connection_count, B32())
  Field(:port_reset_connection_count, B32())
  Field(:name, String())
  Field(:system, Ptr(System()))
end

AbstractStruct(:SignalSinkPortBool) do
  Method(:onChange, handler: Auto())
end

AbstractStruct(:IntSinkPinClint) {}

AbstractMethod(:doReset)

Device(:Clint) do
  Const(:int_rtc, Int(), 0)
  Const(:int_reset, Int(), 1)
  Const(:int_timer_machine, Int(), 7)
  Const(:int_software_machine, Int(), 3)

  Field(:resetLambda, Auto(), Lambda(newVal: Bool()) do
    If(newVal) do
      doReset
    end
  end)

  Constructor(params: Ref(ClintParams())) do
    Init(:system, params.system)
    Init(:nThread, params.num_threads)
    Init(:signal, params.name + '.signal', 0, this, int_rtc)
    Init(:reset, params.name + '.reset')
    Init(:resetMtimecmp, params.reset_mtimecmp)
    Init(:resetValue, params.mtimecmp_reset_value)

    Body do
      reset.onChange(resetLambda)
    end
  end

  Field(:system, Ptr(System()))
  Field(:nThread, B32())
  Field(:signal, IntSinkPinClint())
  Field(:reset, SignalSinkPortBool())
  Field(:resetMtimecmp, Bool())
  Field(:resetValue, B64())

  Method(:raiseInterruptPin, id: Int()) do
    If(id == int_rtc) do
      mtime[] = mtime + 1
    end

    For(iter: :cid, init: 0x0, to: nThread) do
      Let :tc, Ptr(ThreadContext()), system.threads.at(cid)
      Let :mtimecmpv, B64(), mtimecmp.at(cid)

      If(mtime >= mtimecmpv) do
        tc.getCpuPtr.postInterrupt(tc.threadId, int_timer_machine, 0)
      end
      Else do
        tc.getCpuPtr.clearInterrupt(tc.threadId, int_timer_machine, 0)
      end
    end
  end

  Method(:reg_init) do
    mtime[] = 0
    For(iter: :cid, init: 0x0, to: 0x1000) do
      msip.set(cid, 0)
      mtimecmp.set(cid, resetValue)
    end
  end

  Method(:doReset) do
    mtime[] = 0
    For(iter: :cid, init: 0x0, to: 0x1000) do
      If(resetMtimecmp) do
        mtimecmp.set(cid, resetValue)
      end
      msip.set(cid, 0)
      msip.update(cid)
    end

    raiseInterruptPin(int_reset)
  end

  Register(:msip, size: 0x4, offset: 0x0, seqn: 0x1000) do
    Field :msipb, 0x0

    Method(:write, data: B32(), cid: Int()) do
      msip.set(cid, data & 0x1)
      update(cid)
    end

    Method(:read, cid: Int(), ret: B32()) do
      Return msip.at(cid)
    end

    Method(:update, cid: Int()) do
      Let :tc, Ptr(ThreadContext()), system.threads.at(cid)

      If(msip.at(cid)) do
        tc.getCpuPtr.postInterrupt(tc.threadId, int_software_machine, 0)
      end
      Else do
        tc.getCpuPtr.clearInterrupt(tc.threadId, int_software_machine, 0)
      end
    end
  end

  Register(:mtimecmp, size: 0x8, offset: 0x4000, seqn: 0x1000) do
    Field :msipb, 0x0

    Method(:write, data: B64(), cid: Int()) do
      mtimecmp.set(cid, data)
    end

    Method(:read, cid: Int(), ret: B64()) do
      Return mtimecmp.at(cid)
    end
  end

  Register(:mtime, size: 0x8, offset: 0xbff8) {}
end
