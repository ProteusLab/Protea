# frozen_string_literal: true

# PLOD source notice begin
# /*
#  * Copyright (c) 2004-2005 The Regents of The University of Michigan
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

AbstractStruct(:Pic) {
  Method(:getVector, Ret: Int())
}

AbstractStruct(:I8259Params) {
  Field(:pio_latency, B64())
  Field(:mode, Int())
  Field(:slave, Ptr(Pic()))
  Field(:port_output_connection_count, Int())
  Field(:port_inputs_connection_count, Int())
}

AbstractMethod(:findMsb, value: B8(), Ret: Int())

AbstractObject(:intAcknowledgeAddress, B64())

Device(:I8259) {
  Field(:pinStates, Array(Bool(), 8))
  Field(:latency, B64())
  Field(:output, Vector(Ptr(IntSourcePinBase())))
  Field(:inputs, Vector(Ptr(IntSinkPinBase())))
  Field(:mode, Int())
  Field(:slave, Ptr(Pic()))
  Field(:irr, B8())
  Field(:isr, B8())
  Field(:imr, B8())
  Field(:vectorOffset, B8())
  Field(:cascadeMode, Bool())
  Field(:cascadeBits, B8())
  Field(:edgeTriggered, Bool())
  Field(:readIRR, Bool())
  Field(:expectICW4, Bool())
  Field(:initControlWord, Int())
  Field(:autoEOI, Bool())
  AbstractField(:pioAddr, B64())
  AbstractField(:pioSize, B64())
  AbstractMethod(:name, Ret: String())
  AbstractMethod(:basicInit)

  Constructor(params: Ref(I8259Params())) {
    Init(:latency, params.pio_latency)
    Init(:mode, params.mode)
    Init(:slave, params.slave)
    Init(:irr, 0)
    Init(:isr, 0)
    Init(:imr, 0)
    Init(:vectorOffset, 0)
    Init(:cascadeMode, 0)
    Init(:cascadeBits, 0)
    Init(:edgeTriggered, 1)
    Init(:readIRR, 1)
    Init(:expectICW4, 0)
    Init(:initControlWord, 0)
    Init(:autoEOI, 0)
    Body {
      For(Iter: :i, Init: 0, To: 8) {
        pinStates.set(i, 0)
      }
      For(Iter: :i, Init: 0, To: params.port_output_connection_count) {
        output.push(newSourcePin(name + '.output[' + toString(i) + ']', i, this))
      }
      panicIf(params.port_inputs_connection_count > 8, 'I8259 only supports 8 inputs')
      For(Iter: :i, Init: 0, To: params.port_inputs_connection_count) {
        inputs.push(newSinkPin(name + '.inputs[' + toString(i) + ']', i, this))
      }
    }
  }
  Method(:getAddrRanges, Ret: AddrRangeList(), Const: true) {
    Var :ranges, AddrRangeList()
    ranges.push(rangeSize(pioAddr, pioSize))
    If((mode == 0) | (mode == 2)) {
      ranges.push(rangeSize(intAcknowledgeAddress, 1))
    }
    Return ranges
  }
  Method(:init) {
    basicInit
    For(Iter: :i, Init: 0, To: inputs.size) {
      pinStates.set(inputs.at(i).getId, inputs.at(i).state)
    }
  }
  Register(:inta, Size: 1, Offset: 0, Type: :ro) {
    Address { intAcknowledgeAddress }
    Method(:read, Ret: B8()) {
      require((mode == 0) | (mode == 2))
      Return Cast(B8(), getVector)
    }
  }
  Register(:command, Size: 1, Offset: 0) {
    Method(:read, Ret: B8()) {
      If(readIRR) {
        Return irr
      }
      Return isr
    }
    Method(:write, data: B8()) {
      If(data & 0x10 != 0) {
        imr[] = 0
        edgeTriggered[] = data >> 3 & 1
        cascadeMode[] = data & 2 == 0
        expectICW4[] = data & 1
        If(expectICW4 == 0) {
          autoEOI[] = 0
        }
        initControlWord[] = 1
      }
      Elseif(data >> 3 & 3 == 0) {
        Let :operation, B8(), data >> 5
        If(operation == 1) {
          handleEOI(findMsb(isr))
        }
        Elseif(operation == 3) {
          handleEOI(data & 7)
        }
      }
      Elseif(data >> 3 & 3 == 1) {
        If(data & 2 != 0) {
          readIRR[] = data & 1
        }
      }
    }
  }
  Register(:mask, Size: 1, Offset: 1) {
    Method(:read, Ret: B8()) {
      Return imr
    }
    Method(:write, data: B8()) {
      If(initControlWord == 0) {
        imr[] = data
      }
      Elseif(initControlWord == 1) {
        vectorOffset[] = data & 0xf8
        If(cascadeMode) {
          initControlWord[] = initControlWord + 1
        }
        Else {
          cascadeBits[] = 0
          initControlWord[] = 0
        }
      }
      Elseif(initControlWord == 2) {
        If(mode == 0) {
          cascadeBits[] = data
        }
        Else {
          cascadeBits[] = data & 7
        }
        If(expectICW4) {
          initControlWord[] = initControlWord + 1
        }
        Else {
          initControlWord[] = 0
        }
      }
      Elseif(initControlWord == 3) {
        autoEOI[] = data >> 1 & 1
        initControlWord[] = 0
      }
    }
  }
  Method(:maskAll) {
    imr[] = 0xff
  }
  Method(:unmaskAll) {
    imr[] = 0
  }
  Method(:handleEOI, line: Int()) {
    isr[] = isr & ~(Cast(B8(), 1) << line)
    If(irr != 0) {
      requestInterrupt(findMsb(irr))
    }
  }
  Method(:requestInterrupt, line: Int()) {
    If(isr >> line == 0) {
      If(output.empty == 0) {
        For(Iter: :i, Init: 0, To: output.size) {
          output.at(i).raise
          output.at(i).lower
        }
      }
      Else {
        warn("Received interrupt but didn't have anyone to tell about it")
      }
    }
  }
  Method(:signalInterrupt, line: Int()) {
    fatalIf(line >= 8, 'I8259 interrupt line does not exist')
    If(imr >> line & 1 == 0) {
      irr[] = irr | Cast(B8(), 1) << line
      requestInterrupt(line)
    }
  }
  Method(:raiseInterruptPin, number: Int()) {
    fatalIf(number >= 8, 'I8259 interrupt line does not exist')
    If(pinStates.at(number) == 0) {
      signalInterrupt(number)
    }
    pinStates.set(number, 1)
  }
  Method(:lowerInterruptPin, number: Int()) {
    fatalIf(number >= 8, 'I8259 interrupt line does not exist')
    pinStates.set(number, 0)
  }
  Method(:getVector, Ret: Int()) {
    Let :line, Int(), findMsb(irr)
    irr[] = irr & ~(Cast(B8(), 1) << line)
    If(autoEOI) {
      handleEOI(line)
    }
    Else {
      isr[] = isr | Cast(B8(), 1) << line
    }
    If(slave != 0) {
      If(cascadeBits >> line & 1 != 0) {
        Return slave.getVector
      }
    }
    Return line | vectorOffset
  }
  Checkpoint {
    Array('pinStates', pinStates)
    Scalar('mode', mode)
    Scalar('IRR', irr)
    Scalar('ISR', isr)
    Scalar('IMR', imr)
    Scalar('vectorOffset', vectorOffset)
    Scalar('cascadeMode', cascadeMode)
    Scalar('cascadeBits', cascadeBits)
    Scalar('edgeTriggered', edgeTriggered)
    Scalar('readIRR', readIRR)
    Scalar('expectICW4', expectICW4)
    Scalar('initControlWord', initControlWord)
    Scalar('autoEOI', autoEOI)
  }
}
