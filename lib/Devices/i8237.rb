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

AbstractStruct(:I8237Params) {
  Field(:pio_latency, B64())
}

Device(:I8237) {
  Field(:latency, B64())
  Field(:maskVal, B8())
  Field(:requestVal, B8())
  Field(:commandVal, B8())
  Field(:statusVal, B8())
  Field(:tempVal, B8())
  Field(:highByte, Bool())
  Field(:modes, Array(B8(), 4))
  AbstractField(:pioAddr, B64())
  AbstractField(:pioSize, B64())
  AbstractMethod(:initRegisters)
  AbstractMethod(:basicInit)

  Constructor(params: Ref(I8237Params())) {
    Init(:latency, params.pio_latency)
    Body {
      For(Iter: :i, Init: 0, To: 4) {
        modes.set(i, 0)
      }
      initRegisters
      reset
    }
  }
  Method(:init) {
    basicInit
  }
  Method(:reset) {
    maskVal[] = 0xf
    requestVal[] = 0
    commandVal[] = 0
    statusVal[] = 0
    tempVal[] = 0
    highByte[] = 0
  }
  Register(:channel, Size: 1, Offset: 0, Seqn: 8) {
    Method(:read, Ret: B8()) {
      fail('Read from i8237 channel unimplemented')
      Return 0
    }
    Method(:write, data: B8()) {
      fail('Write to i8237 channel unimplemented')
    }
  }
  Register(:status_command, Size: 1, Offset: 8) {
    Method(:read, Ret: B8()) {
      Return statusVal
    }
    Method(:write, data: B8()) {
      commandVal[] = data
    }
  }
  Register(:request, Size: 1, Offset: 9) {
    Method(:read, Ret: B8()) {
      fail('Illegal read from i8237 request register')
      Return 0
    }
    Method(:write, data: B8()) {
      Let :select, B8(), data & 3
      Let :bitVal, B8(), data >> 2 & 1
      panicIf(bitVal != 0, 'Requesting i8237 DMA transfers is unimplemented')
      requestVal[] = requestVal & ~(Cast(B8(), 1) << select) | bitVal << select
    }
  }
  Register(:set_mask_bit, Size: 1, Offset: 10) {
    Method(:read, Ret: B8()) {
      fail('Illegal read from i8237 set mask register')
      Return 0
    }
    Method(:write, data: B8()) {
      Let :select, B8(), data & 3
      Let :bitVal, B8(), data >> 2 & 1
      panicIf(bitVal == 0, 'Turning on i8237 channels unimplemented')
      maskVal[] = maskVal & ~(Cast(B8(), 1) << select) | bitVal << select
    }
  }
  Register(:mode, Size: 1, Offset: 11) {
    Method(:read, Ret: B8()) {
      fail('Illegal read from i8237 mode register')
      Return 0
    }
    Method(:write, data: B8()) {
      modes.set(data & 3, data)
    }
  }
  Register(:clear_flip_flop, Size: 1, Offset: 12) {
    Method(:read, Ret: B8()) {
      fail('Illegal read from i8237 clear flip-flop register')
      Return 0
    }
    Method(:write, data: B8()) {
      highByte[] = 0
    }
  }
  Register(:temporary_master_clear, Size: 1, Offset: 13) {
    Method(:read, Ret: B8()) {
      Return tempVal
    }
    Method(:write, data: B8()) {
      reset
    }
  }
  Register(:clear_mask, Size: 1, Offset: 14) {
    Method(:read, Ret: B8()) {
      fail('Illegal read from i8237 clear mask register')
      Return 0
    }
    Method(:write, data: B8()) {
      maskVal[] = 0
    }
  }
  Register(:write_mask, Size: 1, Offset: 15) {
    Method(:read, Ret: B8()) {
      fail('Illegal read from i8237 write mask register')
      Return 0
    }
    Method(:write, data: B8()) {
      maskVal[] = data & 15
    }
  }
  Checkpoint {
    Scalar('maskReg', maskVal)
  }
}
