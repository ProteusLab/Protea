require_relative '../SDL/plod'

module System

  AbstractStruct(:Event) {
    Method(:scheduled, ret: Bool())
  }

  AbstractStruct(:Tick) {}
  AbstractStruct(:Platform) {
    Method(:clearConsoleInt)
  }

  AbstractStruct(:SerialDevice) {
    Method(:dataAvailable, ret: Bool())

    Method(:readData, ret: B8())
  }

  AbstractStruct(:EventFunctionWrapper) {
    Method(:scheduled, ret: Bool())
  }

  AbstractObject(:ns, System.Tick)
  AbstractMethod(:curTick, ret: System.Tick)

  Device(:Uart8250) {
    Enum(:interruptIds) {
      Modem(0)
      Tx(1)
      Rx(2)
      Line(3)
    }

    Const(:rx_int, B8(), 1)
    Const(:tx_int, B8(), 2)
    Const(:uart_mcr_loop, B8(), 16)

    AbstractMethod(:schedule, event: Ptr(System.Event()), when: System.Tick())
    AbstractMethod(:reschedule, event: Ptr(System.Event()), when: System.Tick())
    AbstractMethod(:deschedule, event: Ptr(System.Event()))

    Method(:dataAvailable) {
      If(ier.rda()) {
        platform.postConsoleInt()
        status[]= status | rx_int
      }
    }

    Method(:intStatus, ret: Bool()) {
      Return Cast(Bool(), status)
    }

    Method(:processIntrEvent, interBit: Int()) {
      If(interBit & ier) {
        platform.postConsoleInt()
        status[] = status | interBit;
        lastTxInt[]= curTick();
      }
    }

    Method(:scheduleIntr, event: Ptr(System.Event())) {
      Let :interval, System.Tick(), ns * 225

      If(event.scheduled() == 0) {
        schedule(event, curTick() + interval)
      }
      Else {
        reschedule(event, curTick() + interval)
      }
    }

    Method(:clearIntr, intrBit: B8()) {
      If((status & intrBit) == 0) {
        Return()
      }

      status[]= status & ~intrBit

      If(status == 0) {
        platform.clearConsoleInt()
      }
    }

    Register(:rbr, size: 0x1, offset: 0x0, type: :ro) {
      enableIf { lcr.dlab == 0 }

      Method(:read, ret: B8()) {
        Let :data, B8(), 0
        If(device.dataAvailable()) {
          data[]= device.readData()
        }
        # Else {
        #   # log("empty read of RX register\n")
        # }

        clearIntr(rx_int)

        If(device.dataAvailable() & ier.rda()) {
          scheduleIntr(GetPtr(rxIntrEvent))
        }
        Else {
          If(rxIntrEvent.scheduled()) {
            deschedule(GetPtr(rxIntrEvent))
          }
        }

        Return data
      }
    }

    Register(:thr, size: 0x1, offset: 0x0, type: :wo) {
      enableIf { lcr.dlab == 0 }

      Method(:write, data: B8()) {
        device.writeData(data)
        clearIntr(tx_int)
        If(ier.thre()) {
          scheduleIntr(GetPtr(txIntrEvent))
        }
        Else {
          If(txIntrEvent.scheduled()) {
            deschedule(GetPtr(txIntrEvent))
          }
        }
      }
    }

    Register(:ier, size: 0x1, offset: 0x1) {
      enableIf { lcr.dlab == 0 }

      field :rda, 0x0
      field :thre, 0x1
      field :rls, 0x2
      field :ms, 0x3
      field :zero, [0x4, 0x7]

      Method(:write, data: B8()) {
        System.Self()[]= data

        If(ier.thre) {
          If(curTick() - lastTxInt > ns * 225) {
            txIntrEvent.process()
          }
          Else {
              scheduleIntr(GetPtr(txIntrEvent))
          }
        }
        Else {
          If(txIntrEvent.scheduled()) {
            deschedule(GetPtr(txIntrEvent))
          }
          clearIntr(tx_int)
        }

        If(ier.rda & device.dataAvailable()) {
          scheduleIntr(GetPtr(rxIntrEvent))
        }
        Else {
          If(rxIntrEvent.scheduled()) {
              deschedule(GetPtr(rxIntrEvent))
          }
          clearIntr(rx_int)
        }
      }
    }

    Register(:iir, size: 0x1, offset: 0x2, type: :ro) {
      field :ip, 0x0
      field :iid, [0x1, 0x2]
      field :zero, [0x3, 0x7]

      Method(:read, ret: B8()) {
        System.Self()[]= 0

        If(status & rx_int) {
          iid[]= interruptIds.Rx
        }
        Else {
          If(status & tx_int) {
            iid[]= interruptIds.Tx
            If(txIntrEvent.scheduled()) {
              deschedule(GetPtr(txIntrEvent))
            }
            clearIntr(tx_int)
          }
          Else {
            ip[]= 1
          }
        }

        Return System.Self()
      }
    }

    # fictitious register
    Register(:fcr, size: 0x1, offset: 0x2, type: :wo) {}

    Register(:lcr, size: 0x1, offset: 0x3) {
      field :wls, [0x0, 0x1]
      field :stb, 0x2
      field :pen, 0x3
      field :eps, 0x4
      field :sp, 0x5
      field :sb, 0x6
      field :dlab, 0x7
    }

    Register(:mcr, size: 0x1, offset: 0x4) {
      field :dtr, 0x0
      field :rts, 0x1
      field :out, [0x2, 0x3]
      field :loop, 0x4
      field :zero, [0x5, 0x7]

      Method(:write, data: B8()) {
        If(data == (uart_mcr_loop | 0x0A)) {
          System.Self()[]= 0x9A;
        }
      }
    }

    Register(:lsr, size: 0x1, offset: 0x5, type: :ro) {
      field :dr, 0x0
      field :oe, 0x1
      field :pe, 0x2
      field :fe, 0x3
      field :bi, 0x4
      field :thre, 0x5
      field :temt, 0x6
      field :zero, 0x7

      Method(:read, ret: B8()) {
        System.Self()[]= 0
        If(device.dataAvailable()) {
          dr[]= 1
        }
        thre[]= 1
        temt[]= 1

        Return System.Self()
      }
    }

    Register(:msr, size: 0x1, offset: 0x6, type: :ro) {
      field :dcts, 0x0
      field :ddsr, 0x1
      field :teri, 0x2
      field :ddcd, 0x3
      field :cts, 0x4
      field :dsr, 0x5
      field :ri, 0x6
      field :dcd, 0x7
    }

    Register(:scr, size: 0x1, offset: 0x7) {}

    Register(:dll, size: 0x1, offset: 0x0) {
      enableIf { lcr.dlab == 1 }
    }

    Register(:dlm, size: 0x1, offset: 0x1) {
      enableIf { lcr.dlab == 1 }
    }

    AbstractField(:status, Int())
    AbstractField(:platform, Ptr(System.Platform()))
    AbstractField(:device, Ptr(System.SerialDevice()))
    Field(:txIntrEvent, System.EventFunctionWrapper, Lambda { processIntrEvent(tx_int) }, "TX")
    Field(:rxIntrEvent, System.EventFunctionWrapper, Lambda { processIntrEvent(rx_int) }, "RX")
    Field(:lastTxInt, System.Tick(), 0)
  }

end
