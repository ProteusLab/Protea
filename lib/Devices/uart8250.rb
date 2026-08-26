# frozen_string_literal: true

AbstractStruct(:Event) do
  Method(:scheduled, ret: Bool())
end

AbstractStruct(:Tick) {}

AbstractStruct(:Platform) do
  Method(:clearConsoleInt)
  Method(:postConsoleInt)
end

AbstractStruct(:SerialDevice) do
  Method(:dataAvailable, ret: Bool())
  Method(:readData, ret: B8())
  Method(:writeData, data: B8())
end

AbstractStruct(:EventFunctionWrapper) do
  Method(:scheduled, ret: Bool())
  Method(:process)
end

AbstractObject(:ns, Tick())
AbstractMethod(:curTick, ret: Tick())

Device(:Uart8250) do
  Enum(:interruptIds) do
    Modem(0)
    Tx(1)
    Rx(2)
    Line(3)
  end

  Const(:rx_int, B8(), 1)
  Const(:tx_int, B8(), 2)
  Const(:uart_mcr_loop, B8(), 16)

  AbstractMethod(:schedule, event: Ptr(Event()), when: Tick())
  AbstractMethod(:reschedule, event: Ptr(Event()), when: Tick())
  AbstractMethod(:deschedule, event: Ptr(Event()))

  Method(:dataAvailable) do
    If(ier.rda) do
      platform.postConsoleInt
      status[] = status | rx_int
    end
  end

  Method(:intStatus, ret: Bool()) do
    Return Cast(Bool(), status)
  end

  Method(:processIntrEvent, interBit: Int()) do
    If(interBit & ier) do
      platform.postConsoleInt
      status[] = status | interBit
      lastTxInt[] = curTick
    end
  end

  Method(:scheduleIntr, event: Ptr(Event())) do
    Let :interval, Tick(), ns * 225

    If(event.scheduled == 0) do
      schedule(event, curTick + interval)
    end
    .Else do
      reschedule(event, curTick + interval)
    end
  end

  Method(:clearIntr, intrBit: B8()) do
    If((status & intrBit) == 0) do
      Return()
    end

    status[] = status & ~intrBit

    If(status == 0) do
      platform.clearConsoleInt
    end
  end

  Register(:rbr, size: 0x1, offset: 0x0, type: :ro) do
    enableIf { lcr.dlab == 0 }

    Method(:read, ret: B8()) do
      Let :data, B8(), 0
      If(device.dataAvailable) do
        data[] = device.readData
      end

      clearIntr(rx_int)

      If(device.dataAvailable & ier.rda) do
        scheduleIntr(GetPtr(rxIntrEvent))
      end
      .Else do
        If(rxIntrEvent.scheduled) do
          deschedule(GetPtr(rxIntrEvent))
        end
      end

      Return data
    end
  end

  Register(:thr, size: 0x1, offset: 0x0, type: :wo) do
    enableIf { lcr.dlab == 0 }

    Method(:write, data: B8()) do
      device.writeData(data)
      clearIntr(tx_int)
      If(ier.thre) do
        scheduleIntr(GetPtr(txIntrEvent))
      end
      .Else do
        If(txIntrEvent.scheduled) do
          deschedule(GetPtr(txIntrEvent))
        end
      end
    end
  end

  Register(:ier, size: 0x1, offset: 0x1) do
    enableIf { lcr.dlab == 0 }

    field :rda, 0x0
    field :thre, 0x1
    field :rls, 0x2
    field :ms, 0x3
    field :zero, [0x4, 0x7]

    Method(:write, data: B8()) do
      this[] = data

      If(ier.thre) do
        If(curTick - lastTxInt > ns * 225) do
          txIntrEvent.process
        end
        .Else do
          scheduleIntr(GetPtr(txIntrEvent))
        end
      end
      .Else do
        If(txIntrEvent.scheduled) do
          deschedule(GetPtr(txIntrEvent))
        end
        clearIntr(tx_int)
      end

      If(ier.rda & device.dataAvailable) do
        scheduleIntr(GetPtr(rxIntrEvent))
      end
      .Else do
        If(rxIntrEvent.scheduled) do
          deschedule(GetPtr(rxIntrEvent))
        end
        clearIntr(rx_int)
      end
    end
  end

  Register(:iir, size: 0x1, offset: 0x2, type: :ro) do
    field :ip, 0x0
    field :iid, [0x1, 0x2]
    field :zero, [0x3, 0x7]

    Method(:read, ret: B8()) do
      this[] = 0

      If(status & rx_int) do
        iid[] = interruptIds.Rx
      end
      .Else do
        If(status & tx_int) do
          iid[] = interruptIds.Tx
          If(txIntrEvent.scheduled) do
            deschedule(GetPtr(txIntrEvent))
          end
          clearIntr(tx_int)
        end
        .Else do
          ip[] = 1
        end
      end

      Return this
    end
  end

  Register(:fcr, size: 0x1, offset: 0x2, type: :wo) {}

  Register(:lcr, size: 0x1, offset: 0x3) do
    field :wls, [0x0, 0x1]
    field :stb, 0x2
    field :pen, 0x3
    field :eps, 0x4
    field :sp, 0x5
    field :sb, 0x6
    field :dlab, 0x7
  end

  Register(:mcr, size: 0x1, offset: 0x4) do
    field :dtr, 0x0
    field :rts, 0x1
    field :out, [0x2, 0x3]
    field :loop, 0x4
    field :zero, [0x5, 0x7]

    Method(:write, data: B8()) do
      If(data == (uart_mcr_loop | 0x0A)) do
        this[] = 0x9A
      end
    end
  end

  Register(:lsr, size: 0x1, offset: 0x5, type: :ro) do
    field :dr, 0x0
    field :oe, 0x1
    field :pe, 0x2
    field :fe, 0x3
    field :bi, 0x4
    field :thre, 0x5
    field :temt, 0x6
    field :zero, 0x7

    Method(:read, ret: B8()) do
      this[] = 0
      If(device.dataAvailable) do
        dr[] = 1
      end
      thre[] = 1
      temt[] = 1

      Return this
    end
  end

  Register(:msr, size: 0x1, offset: 0x6, type: :ro) do
    field :dcts, 0x0
    field :ddsr, 0x1
    field :teri, 0x2
    field :ddcd, 0x3
    field :cts, 0x4
    field :dsr, 0x5
    field :ri, 0x6
    field :dcd, 0x7
  end

  Register(:scr, size: 0x1, offset: 0x7) {}

  Register(:dll, size: 0x1, offset: 0x0) do
    enableIf { lcr.dlab == 1 }
  end

  Register(:dlm, size: 0x1, offset: 0x1) do
    enableIf { lcr.dlab == 1 }
  end

  AbstractField(:status, Int())
  AbstractField(:platform, Ptr(Platform()))
  AbstractField(:device, Ptr(SerialDevice()))
  Field(:txIntrEvent, EventFunctionWrapper(), Lambda { processIntrEvent(tx_int) }, 'TX')
  Field(:rxIntrEvent, EventFunctionWrapper(), Lambda { processIntrEvent(rx_int) }, 'RX')
  Field(:lastTxInt, Tick(), 0)
end
