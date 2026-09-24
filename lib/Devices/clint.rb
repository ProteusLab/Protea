# frozen_string_literal: true

AbstractStruct(:BaseCPU) {
  Method(:postInterrupt, tid: Int(), int_num: Int(), index: Int())
  Method(:clearInterrupt, tid: Int(), int_num: Int(), index: Int())
}

AbstractStruct(:ThreadContext) {
  Method(:getCpuPtr, Ret: Ptr(BaseCPU()))
  Method(:threadId, Ret: Int())
}

AbstractStruct(:Threads) {
  Method(:at, id: Int(), Ret: Ptr(ThreadContext()))
}

AbstractStruct(:System) {
  Field(:threads, Threads())
}

AbstractStruct(:ClintParams) {
  Field(:mtimecmp_reset_value, B64())
  Field(:num_threads, B32())
  Field(:pio_size, B64())
  Field(:reset_mtimecmp, Bool())
  Field(:port_int_pin_connection_count, B32())
  Field(:port_reset_connection_count, B32())
  Field(:name, String())
  Field(:system, Ptr(System()))
}

AbstractStruct(:SignalSinkPortBool) {
  Method(:onChange, handler: Auto())
}

AbstractStruct(:IntSinkPinClint) {}

AbstractMethod(:doReset)

Device(:Clint) {
  Const(:int_rtc, Int(), 0)
  Const(:int_reset, Int(), 1)
  Const(:int_timer_machine, Int(), 7)
  Const(:int_software_machine, Int(), 3)

  Field(:resetLambda, Auto(), Lambda(newVal: Bool()) {
    If(newVal) {
      doReset
    }
  })

  Constructor(params: Ref(ClintParams())) {
    Init(:system, params.system)
    Init(:nThread, params.num_threads)
    Init(:signal, params.name + '.signal', 0, this, int_rtc)
    Init(:reset, params.name + '.reset')
    Init(:resetMtimecmp, params.reset_mtimecmp)
    Init(:resetValue, params.mtimecmp_reset_value)

    Body {
      reset.onChange(resetLambda)
    }
  }

  Field(:system, Ptr(System()))
  Field(:nThread, B32())
  Field(:signal, IntSinkPinClint())
  Field(:reset, SignalSinkPortBool())
  Field(:resetMtimecmp, Bool())
  Field(:resetValue, B64())

  Method(:raiseInterruptPin, id: Int()) {
    If(id == int_rtc) {
      mtime[] = mtime + 1
    }

    For(Iter: :cid, Init: 0x0, To: nThread) {
      Let :tc, Ptr(ThreadContext()), system.threads.at(cid)
      Let :mtimecmpv, B64(), mtimecmp.at(cid)

      If(mtime >= mtimecmpv) {
        tc.getCpuPtr.postInterrupt(tc.threadId, int_timer_machine, 0)
      }
      Else {
        tc.getCpuPtr.clearInterrupt(tc.threadId, int_timer_machine, 0)
      }
    }
  }

  Method(:reg_init) {
    mtime[] = 0
    For(Iter: :cid, Init: 0x0, To: 0x1000) {
      msip.set(cid, 0)
      mtimecmp.set(cid, resetValue)
    }
  }

  Method(:doReset) {
    mtime[] = 0
    For(Iter: :cid, Init: 0x0, To: 0x1000) {
      If(resetMtimecmp) {
        mtimecmp.set(cid, resetValue)
      }
      msip.set(cid, 0)
      msip.update(cid)
    }

    raiseInterruptPin(int_reset)
  }

  Register(:msip, Size: 0x4, Offset: 0x0, Seqn: 0x1000) {
    Field :msipb, 0x0

    Method(:write, data: B32(), cid: Int()) {
      msip.set(cid, data & 0x1)
      update(cid)
    }

    Method(:read, cid: Int(), Ret: B32()) {
      Return msip.at(cid)
    }

    Method(:update, cid: Int()) {
      Let :tc, Ptr(ThreadContext()), system.threads.at(cid)

      If(msip.at(cid)) {
        tc.getCpuPtr.postInterrupt(tc.threadId, int_software_machine, 0)
      }
      Else {
        tc.getCpuPtr.clearInterrupt(tc.threadId, int_software_machine, 0)
      }
    }
  }

  Register(:mtimecmp, Size: 0x8, Offset: 0x4000, Seqn: 0x1000) {
    Field :msipb, 0x0

    Method(:write, data: B64(), cid: Int()) {
      mtimecmp.set(cid, data)
    }

    Method(:read, cid: Int(), Ret: B64()) {
      Return mtimecmp.at(cid)
    }
  }

  Register(:mtime, Size: 0x8, Offset: 0xbff8) {}
}
