# frozen_string_literal: true

# PLOD source notice begin
# /*
#  * Copyright (c) 2008 The Regents of The University of Michigan
#  * All rights reserved.
#  *
#  * Redistribution and use in source and binary forms, with or without
#  * modification, are permitted provided that the following conditions are
#  * met: redistributions of source code must retain the above copyright
#  * notice, this list of conditions and the following disclaimer;
#  * redistributions in binary form must reproduce the above copyright
#  * notice, this list of conditions and the following disclaimer in the
#  * documentation and/or other materials provided with the distribution;
#  * neither the name of the copyright holders nor the names of its
#  * contributors may be used to endorse or promote products derived from
#  * this software without specific prior written permission.
#  *
#  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#  */
# PLOD source notice end

AbstractStruct(:Packet) {
  Method(:getByte, Ret: B8())
}

AbstractStruct(:AddrRange) {}

AbstractStruct(:AddrRangeList) {
  Method(:push, value: AddrRange())
}

AbstractMethod(:rangeSize, base: B64(), size: B64(), Ret: AddrRange())

AbstractMethod(:require, condition: Bool())

AbstractMethod(:panicIf, condition: Bool(), message: String())

AbstractMethod(:fatalIf, condition: Bool(), message: String())

AbstractMethod(:fail, message: String())

AbstractMethod(:warn, message: String())

AbstractMethod(:toString, value: Int(), Ret: String())

AbstractStruct(:IntSourcePinBase) {
  Method(:raise)
  Method(:lower)
}

AbstractStruct(:IntSinkPinBase) {
  Method(:getId, Ret: Int())
  Method(:state, Ret: Bool())
}

AbstractMethod(:newSourcePin, name: String(), id: Int(), owner: Auto(), Ret: Ptr(IntSourcePinBase()))

AbstractMethod(:newSinkPin, name: String(), id: Int(), owner: Auto(), Ret: Ptr(IntSinkPinBase()))

AbstractStruct(:TriggerMessage) {
  Field(:destination, B32())
  Field(:vector, B32())
  Field(:deliveryMode, B32())
  Field(:destMode, B32())
  Field(:level, B32())
  Field(:trigger, B32())
}

AbstractStruct(:RequestPort) {
  Method(:isConnected, Ret: Bool())
  Method(:sendMessage, pkt: Ptr(Packet()), timing: Bool())
  Method(:sendCallback, pkt: Ptr(Packet()), timing: Bool(), callback: Auto())
}

AbstractStruct(:BaseInterrupts) {}

AbstractStruct(:LocalApic) {
  Method(:readReg, offset: Int(), Ret: B32())
  Method(:getInitialApicId, Ret: Int())
}

AbstractStruct(:BaseCPU) {
  Method(:getInterruptController, index: Int(), Ret: Ptr(BaseInterrupts()))
}

AbstractStruct(:ThreadContext) {
  Method(:getCpuPtr, Ret: Ptr(BaseCPU()))
}

AbstractStruct(:System) {
  Field(:threads, Vector(Ptr(ThreadContext())))
  Method(:isTimingMode, Ret: Bool())
}

AbstractStruct(:I82094AAParams) {
  Field(:apic_id, Int())
  Field(:int_latency, B64())
  Field(:port_inputs_connection_count, Int())
}

AbstractMethod(:makeMessage, value: B32(), Ret: TriggerMessage())

AbstractMethod(:localApic, interrupts: Ptr(BaseInterrupts()), Ret: Ptr(LocalApic()))

AbstractMethod(:buildAck, Ret: Ptr(Packet()))

AbstractMethod(:buildTrigger, id: Int(), message: TriggerMessage(), Ret: Ptr(Packet()))

AbstractMethod(:freePacket, pkt: Ptr(Packet()))

AbstractMethod(:bindMessage, callback: Auto(), message: TriggerMessage(), Ret: Auto())

AbstractObject(:logicalDestinationReg, Int())

Device(:I82094AA) {
  Field(:regSel, B8())
  Field(:initialApicId, B8())
  Field(:id, B8())
  Field(:arbId, B8())
  Field(:lowestPriorityOffset, B64())
  Field(:redirTable, Array(B64(), 24))
  Field(:pinStates, Array(Bool(), 24))
  Field(:inputs, Vector(Ptr(IntSinkPinBase())))
  Field(:intRequestPort, RequestPort())
  Field(:ackCallback, Auto(), Lambda(message: TriggerMessage(), pkt: Ptr(Packet())) { message.vector[] = pkt.getByte; signalInterrupt(message); freePacket(pkt) })
  AbstractField(:pioAddr, B64())
  AbstractField(:pioDelay, B64())
  AbstractField(:sys, Ptr(System()))
  AbstractMethod(:name, Ret: String())
  AbstractMethod(:basicInit)

  Constructor(params: Ref(I82094AAParams())) {
    Init(:regSel, 0)
    Init(:initialApicId, params.apic_id)
    Init(:id, params.apic_id)
    Init(:arbId, params.apic_id)
    Init(:lowestPriorityOffset, 0)
    Init(:intRequestPort, name + '.int_request', this, this, params.int_latency)
    Body {
      require(params.apic_id < 0xff)
      For(Iter: :i, Init: 0, To: 24) {
        redirTable.set(i, 0x10000)
        pinStates.set(i, 0)
      }
      For(Iter: :i, Init: 0, To: params.port_inputs_connection_count) {
        inputs.push(newSinkPin(name + '.inputs[' + toString(i) + ']', i, this))
      }
    }
  }
  Method(:init) {
    basicInit
    panicIf(intRequestPort.isConnected == 0, 'Int port not connected to anything')
  }
  Register(:select, Size: 4, Offset: 0) {
    Method(:read, Ret: B32()) {
      Return regSel
    }
    Method(:write, data: B32()) {
      regSel[] = Cast(B8(), data)
    }
  }
  Register(:window, Size: 4, Offset: 16) {
    Method(:read, Ret: B32()) {
      Return readReg(regSel)
    }
    Method(:write, data: B32()) {
      writeReg(regSel, data)
    }
  }
  Method(:writeReg, offset: B8(), value: B32()) {
    If(offset == 0) {
      id[] = Cast(B8(), value >> 24)
    }
    Elseif(offset == 1) {
    }
    Elseif(offset == 2) {
      arbId[] = Cast(B8(), value >> 24)
    }
    Elseif((offset >= 0x10) & (offset <= 0x40)) {
      Let :index, Int(), (offset - 0x10) / 2
      Let :entry, B64(), redirTable.at(index)
      If(offset % 2 != 0) {
        entry[] = entry & 0xffffffff | Cast(B64(), value & 0xff000000) << 32
      }
      Else {
        entry[] = entry & 0xffffffff00000000 | value & 0x1ffff
      }
      redirTable.set(index, entry)
    }
    Else {
      warn('Access to undefined I/O APIC register')
    }
  }
  Method(:readReg, offset: B8(), Ret: B32()) {
    If(offset == 0) {
      Return Cast(B32(), id) << 24
    }
    Elseif(offset == 1) {
      Return 0x170014
    }
    Elseif(offset == 2) {
      Return Cast(B32(), arbId) << 24
    }
    Elseif((offset >= 0x10) & (offset <= 0x40)) {
      Let :index, Int(), (offset - 0x10) / 2
      If(offset % 2 != 0) {
        Return Cast(B32(), redirTable.at(index) >> 32)
      }
      Return Cast(B32(), redirTable.at(index))
    }
    warn('Access to undefined I/O APIC register')
    Return 0
  }
  Method(:requestInterrupt, line: Int()) {
    require(line < 24)
    Let :entry, B64(), redirTable.at(line)
    If(entry >> 16 & 1 != 0) {
      Return()
    }
    Let :message, TriggerMessage(), makeMessage(0)
    message.destination[] = Cast(B32(), entry >> 56)
    message.deliveryMode[] = Cast(B32(), entry >> 8 & 7)
    message.destMode[] = Cast(B32(), entry >> 11 & 1)
    message.level[] = Cast(B32(), entry >> 13 & 1)
    message.trigger[] = Cast(B32(), entry >> 15 & 1)
    If(message.deliveryMode == 7) {
      Let :pkt, Ptr(Packet()), buildAck
      intRequestPort.sendCallback(pkt, sys.isTimingMode, bindMessage(ackCallback, message))
    }
    Else {
      message.vector[] = Cast(B32(), entry & 0xff)
      signalInterrupt(message)
    }
  }
  Method(:signalInterrupt, message: TriggerMessage()) {
    Var :apics, Vector(Int())
    Let :numContexts, Int(), sys.threads.size
    If(message.destMode == 0) {
      panicIf(message.deliveryMode == 1, 'Lowest priority delivery unsupported in physical destination mode')
      If(message.destination == 0xff) {
        For(Iter: :i, Init: 0, To: numContexts) {
          apics.push(i)
        }
      }
      Else {
        apics.push(message.destination)
      }
    }
    Else {
      For(Iter: :i, Init: 0, To: numContexts) {
        Let :base, Ptr(BaseInterrupts()), sys.threads.at(i).getCpuPtr.getInterruptController(0)
        Let :lapic, Ptr(LocalApic()), localApic(base)
        If(lapic.readReg(logicalDestinationReg) >> 24 & message.destination != 0) {
          apics.push(lapic.getInitialApicId)
        }
      }
      If((message.deliveryMode == 1) & (apics.size != 0)) {
        Let :modOffset, B64(), lowestPriorityOffset % apics.size
        lowestPriorityOffset[] = lowestPriorityOffset + 1
        Let :selected, Int(), apics.at(modOffset)
        apics.clear
        apics.push(selected)
      }
    }
    For(Iter: :i, Init: 0, To: apics.size) {
      Let :pkt, Ptr(Packet()), buildTrigger(apics.at(i), message)
      intRequestPort.sendMessage(pkt, sys.isTimingMode)
    }
  }
  Method(:raiseInterruptPin, number: Int()) {
    require(number < 24)
    If(pinStates.at(number) == 0) {
      requestInterrupt(number)
    }
    pinStates.set(number, 1)
  }
  Method(:lowerInterruptPin, number: Int()) {
    require(number < 24)
    pinStates.set(number, 0)
  }
  Checkpoint {
    Scalar('regSel', regSel)
    Scalar('initialApicId', initialApicId)
    Scalar('id', id)
    Scalar('arbId', arbId)
    Scalar('lowestPriorityOffset', lowestPriorityOffset)
    Array('redirTableArray', redirTable)
    Array('pinStates', pinStates)
  }
}
