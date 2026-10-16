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

AbstractStruct(:Ps2Device) {
  Method(:hostWrite, data: B8())
  Method(:hostDataAvailable, Ret: Bool())
  Method(:hostRead, Ret: B8())
}

AbstractStruct(:I8042Params) {
  Field(:pio_latency, B64())
  Field(:data_port, B64())
  Field(:command_port, B64())
  Field(:mouse, Ptr(Ps2Device()))
  Field(:keyboard, Ptr(Ps2Device()))
  Field(:port_keyboard_int_pin_connection_count, Int())
  Field(:port_mouse_int_pin_connection_count, Int())
}

Device(:I8042) {
  Field(:latency, B64())
  Field(:dataPort, B64())
  Field(:commandPort, B64())
  Field(:statusReg, B8())
  Field(:commandByte, B8())
  Field(:dataReg, B8())
  Field(:lastCommand, B16())
  Field(:mouseIntPin, Vector(Ptr(IntSourcePinBase())))
  Field(:keyboardIntPin, Vector(Ptr(IntSourcePinBase())))
  Field(:mouse, Ptr(Ps2Device()))
  Field(:keyboard, Ptr(Ps2Device()))
  AbstractMethod(:name, Ret: String())
  Const(:no_command, B16(), 0xffff)

  Constructor(params: Ref(I8042Params())) {
    Init(:latency, params.pio_latency)
    Init(:dataPort, params.data_port)
    Init(:commandPort, params.command_port)
    Init(:statusReg, 0x10)
    Init(:commandByte, 0x70)
    Init(:dataReg, 0)
    Init(:lastCommand, no_command)
    Init(:mouse, params.mouse)
    Init(:keyboard, params.keyboard)
    Body {
      fatalIf(mouse == 0, 'The i8042 model requires a mouse instance')
      fatalIf(keyboard == 0, 'The i8042 model requires a keyboard instance')
      For(Iter: :i, Init: 0, To: params.port_keyboard_int_pin_connection_count) {
        keyboardIntPin.push(newSourcePin(name + '.keyboard_int_pin[' + toString(i) + ']', i, this))
      }
      For(Iter: :i, Init: 0, To: params.port_mouse_int_pin_connection_count) {
        mouseIntPin.push(newSourcePin(name + '.mouse_int_pin[' + toString(i) + ']', i, this))
      }
    }
  }
  Method(:getAddrRanges, Ret: AddrRangeList(), Const: true) {
    Var :ranges, AddrRangeList()
    ranges.push(rangeSize(dataPort, 1))
    ranges.push(rangeSize(commandPort, 1))
    Return ranges
  }
  Method(:writeData, newData: B8(), fromMouse: Bool()) {
    dataReg[] = newData
    statusReg[] = statusReg & 0xdf | 1
    If(fromMouse) {
      statusReg[] = statusReg | 0x20
    }
    If((fromMouse == 0) & (commandByte & 1 != 0)) {
      For(Iter: :i, Init: 0, To: keyboardIntPin.size) {
        keyboardIntPin.at(i).raise
        keyboardIntPin.at(i).lower
      }
    }
    Elseif(fromMouse & (commandByte & 2 != 0)) {
      For(Iter: :i, Init: 0, To: mouseIntPin.size) {
        mouseIntPin.at(i).raise
        mouseIntPin.at(i).lower
      }
    }
  }
  Register(:output_buffer, Size: 1, Offset: 0, Type: :ro) {
    Address { dataPort }
    Method(:read, Ret: B8()) {
      Let :data, B8(), dataReg
      statusReg[] = statusReg & 0xde
      If(keyboard.hostDataAvailable) {
        writeData(keyboard.hostRead, 0)
      }
      Elseif(mouse.hostDataAvailable) {
        writeData(mouse.hostRead, 1)
      }
      Return data
    }
  }
  Register(:input_buffer, Size: 1, Offset: 0, Type: :wo) {
    Address { dataPort }
    Method(:write, data: B8()) {
      statusReg[] = statusReg & 0xf7
      If(lastCommand == no_command) {
        keyboard.hostWrite(data)
        If(keyboard.hostDataAvailable) {
          writeData(keyboard.hostRead, 0)
        }
      }
      Elseif(lastCommand == 0xd4) {
        mouse.hostWrite(data)
        If(mouse.hostDataAvailable) {
          writeData(mouse.hostRead, 1)
        }
      }
      Elseif(lastCommand == 0x60) {
        commandByte[] = data
      }
      Elseif(lastCommand == 0xd3) {
        writeData(data, 1)
      }
      Elseif(lastCommand == 0xd2) {
        writeData(data, 0)
      }
      Elseif(lastCommand == 0xd1) {
        panicIf(data & 1 != 1, 'Reset bit should be 1')
      }
      Else {
        fail('Data written for unrecognized i8042 command')
      }
      lastCommand[] = no_command
    }
  }
  Register(:status, Size: 1, Offset: 4, Type: :ro) {
    Address { commandPort }
    Method(:read, Ret: B8()) {
      Return statusReg
    }
  }
  Register(:command, Size: 1, Offset: 4, Type: :wo) {
    Address { commandPort }
    Method(:write, data: B8()) {
      statusReg[] = statusReg | 8
      panicIf((data > 0x20) & (data < 0x40), 'Unimplemented i8042 read controller RAM')
      panicIf((data > 0x60) & (data < 0x80), 'Unimplemented i8042 write controller RAM')
      panicIf((data >= 0xf0) & (data < 0xfe), 'Unimplemented i8042 pulse output bit')
      If(data == 0x20) {
        writeData(commandByte, 0)
      }
      Elseif((data == 0x60) | (data == 0xd1) | (data == 0xd2) | (data == 0xd3) | (data == 0xd4)) {
        lastCommand[] = data
      }
      Elseif(data == 0xa7) {
        commandByte[] = commandByte | 0x20
      }
      Elseif(data == 0xa8) {
        commandByte[] = commandByte & 0xdf
      }
      Elseif((data == 0xa9) | (data == 0xab)) {
        writeData(0, 0)
      }
      Elseif(data == 0xaa) {
        commandByte[] = commandByte | 0x74
        statusReg[] = statusReg | 4
        writeData(0x55, 0)
      }
      Elseif(data == 0xad) {
        commandByte[] = commandByte | 0x10
      }
      Elseif(data == 0xae) {
        commandByte[] = commandByte & 0xef
      }
      Elseif((data == 0xa4) | (data == 0xa5) | (data == 0xa6) | (data == 0xac) | (data == 0xc0) | (data == 0xc1) | (data == 0xc2) | (data == 0xd0) | (data == 0xdd) | (data == 0xdf) | (data == 0xe0) | (data == 0xfe)) {
        fail('Unimplemented i8042 command')
      }
      Else {
        warn('Write to unknown i8042 command port')
      }
    }
  }
  Checkpoint {
    Scalar('dataPort', dataPort)
    Scalar('commandPort', commandPort)
    Scalar('statusReg', statusReg)
    Scalar('commandByte', commandByte)
    Scalar('dataReg', dataReg)
    Scalar('lastCommand', lastCommand)
  }
}
