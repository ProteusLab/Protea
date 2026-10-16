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

AbstractStruct(:CheckpointOut) {}

AbstractStruct(:CheckpointIn) {}

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

AbstractStruct(:Timer) {
  Method(:readCounter, num: B32(), Ret: B8())
  Method(:writeCounter, num: B32(), data: B8())
  Method(:writeControl, data: B8())
  Method(:outputHigh, num: B32(), Ret: Bool())
  Method(:serialize, base: String(), cp: Ref(CheckpointOut()), Const: true)
  Method(:unserialize, base: String(), cp: Ref(CheckpointIn()))
  Method(:startup)
}

AbstractStruct(:I8254Params) {
  Field(:pio_latency, B64())
  Field(:name, String())
  Field(:port_int_pin_connection_count, Int())
}

Device(:I8254) {
  Field(:latency, B64())
  Field(:counterCallback, Auto(), Lambda(num: B32()) { counterInterrupt(num) })
  Field(:pit, Timer())
  Field(:intPin, Vector(Ptr(IntSourcePinBase())))
  AbstractField(:pioAddr, B64())
  AbstractMethod(:name, Ret: String())

  Constructor(params: Ref(I8254Params())) {
    Init(:latency, params.pio_latency)
    Init(:pit, this, params.name, counterCallback)
    Body {
      For(Iter: :i, Init: 0, To: params.port_int_pin_connection_count) {
        intPin.push(newSourcePin(name + '.int_pin[' + toString(i) + ']', i, this))
      }
    }
  }
  Method(:counterInterrupt, num: B32()) {
    If(num == 0) {
      For(Iter: :i, Init: 0, To: intPin.size) {
        intPin.at(i).raise
        intPin.at(i).lower
      }
    }
  }
  Method(:outputHigh, num: B32(), Ret: Bool()) {
    Return pit.outputHigh(num)
  }
  Method(:readCounter, num: B32(), Ret: B8()) {
    Return pit.readCounter(num)
  }
  Method(:writeCounter, num: B32(), data: B8()) {
    pit.writeCounter(num, data)
  }
  Method(:writeControl, data: B8()) {
    pit.writeControl(data)
  }
  Register(:counter, Size: 1, Offset: 0, Seqn: 3) {
    Method(:read, Ret: B8()) {
      Return pit.readCounter(Cast(B32(), cid))
    }
    Method(:write, data: B8()) {
      pit.writeCounter(Cast(B32(), cid), data)
    }
  }
  Register(:control, Size: 1, Offset: 3) {
    Method(:read, Ret: B8()) {
      Return 0xff
    }
    Method(:write, data: B8()) {
      pit.writeControl(data)
    }
  }
  Method(:startup) {
    pit.startup
  }
  Checkpoint {
    Delegate(pit, Prefix: 'pit')
  }
}
