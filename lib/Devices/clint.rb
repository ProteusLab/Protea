require_relative '../SDL/plod'

module System

AbstractStruct(:BaseCPU) {
  Method(:postInterrupt, tid: Int(), int_num: Int(), index: Int())
  Method(:clearInterrupt, tid: Int(), int_num: Int(), index: Int())
}


AbstractStruct(:ThreadContext) {
  Method(:getCpuPtr, ret: Ptr(System.BaseCPU()))
  Method(:threadId, ret: Int())
}

AbstractStruct(:Threads) {
  Method(:at, id: Int(), ret: Ptr(System.ThreadContext()))
}

AbstractStruct(:System) {
  Field(:threads, System.Threads())
}

AbstractStruct(:ClintParams) {
  Field(:mtimecmp_reset_value, B64())
  Field(:num_threads, B32())
  Field(:pio_size, B64())
  Field(:reset_mtimecmp, Bool())
  Field(:port_int_pin_connection_count, B32())
  Field(:port_reset_connection_count, B32())
  Field(:name, String())
  Field(:system, Ptr(System.System()))
}

AbstractStruct(:SignalSinkPortBool) {}
AbstractStruct(:IntSinkPinClint) {}

AbstractMethod(:doReset)

Device(:Clint) {
  Const(:int_rtc, Int(), 0)
  Const(:int_reset, Int(), 1)
  Const(:int_timer_machine, Int(), 7)
  Const(:int_software_machine, Int(), 3)

  Field(:resetLambda, Auto(), Lambda(newVal: Bool()) {
    If(newVal) {
      doReset()
    }
  })

  Constructor(params: Ref(System.ClintParams())) {
    Init(:system, params.system)
    Init(:nThread, params.num_threads)
    Init(:signal, params.name + ".signal", 0, System.Self(), int_rtc)
    Init(:reset, params.name + ".reset")
    Init(:resetMtimecmp, params.reset_mtimecmp)
    Init(:resetValue, params.mtimecmp_reset_value)

    Body {
      reset.onChange(resetLambda)
    }
  }

  Field(:system, Ptr(System.System()))
  Field(:nThread, B32())
  Field(:signal, System.IntSinkPinClint())
  Field(:reset, System.SignalSinkPortBool())
  Field(:resetMtimecmp, Bool())
  Field(:resetValue, B64())

  Method(:raiseInterruptPin, id: Int()) {
    If(id == int_rtc) {
      mtime[]= mtime + 1
    }

    Var :cid, Int()
    For(iter: :cid, init: 0x0, end: nThread) {
      Let :tc, Ptr(System.ThreadContext()), system.threads.at(cid)

      Let :mtimecmpv, B64(), mtimecmp.at(cid)

      If(mtime >= mtimecmpv) {
        tc.getCpuPtr().postInterrupt(tc.threadId(), int_timer_machine, 0)
      }
      Else {
        tc.getCpuPtr().clearInterrupt(tc.threadId(), int_timer_machine, 0)
      }
    }
  }

  Method(:reg_init) {
    mtime[]= 0
    Var :cid, Int()
    For(iter: :cid, init: 0x0, end: 0x1000) {
      msip.set(cid, 0)
      mtimecmp.set(cid, resetValue)
    }
  }

  Method(:doReset) {
    mtime[]= 0
    Var :cid, Int()
    For(iter: :cid, init: 0x0, end: 0x1000) {
      If(resetMtimecmp) {
        mtimecmp.set(cid, resetValue)
      }
      msip.set(cid, 0)
      msip.update(cid)
    }

    raiseInterruptPin(int_reset)
  }

  Register(:msip, size: 0x4, offset: 0x0, seqn: 0x1000) {
    field :msipb, 0x0

    Method(:write, data: B32(), cid: Int()) {
      msip.set(cid, data & 0x1)
      update(cid)
    }

    Method(:read, cid: Int(), ret: B32()) {
      Return msip.at(cid)
    }

    Method(:update, cid: Int()) {
      Let :tc, Ptr(System.ThreadContext()), system.threads.at(cid)

      If(msip.at(cid)) {
        tc.getCpuPtr().postInterrupt(tc.threadId(), int_software_machine, 0)
      }
      Else {
        tc.getCpuPtr().clearInterrupt(tc.threadId(), int_software_machine, 0)
      }
    }
  }

  Register(:mtimecmp, size: 0x8, offset: 0x4000, seqn: 0x1000) {
    field :msipb, 0x0

    Method(:write, data: B64(), cid: Int()) {
      mtimecmp.set(cid, data)
    }

    Method(:read, cid: Int(), ret: B64()) {
      Return mtimecmp.at(cid)
    }
  }

  Register(:mtime, size: 0x8, offset: 0xbff8) {}
}

end
