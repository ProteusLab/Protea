# frozen_string_literal: true

# PLOD source notice begin
# /*
#  * Copyright (c) 2021 Huawei International
#  * Copyright (c) 2016-2018 ARM Limited
#  * All rights reserved
#  *
#  * The license below extends only to copyright in the software and shall
#  * not be construed as granting a license to any other intellectual
#  * property including but not limited to intellectual property relating
#  * to a hardware implementation of the functionality of the software
#  * licensed hereunder.  You may use the software subject to the license
#  * terms below provided that you ensure that this notice is replicated
#  * unmodified and in its entirety in all distributions of the software,
#  * modified or unmodified, in source code or in binary form.
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

AbstractStruct(:Packet) {}

AbstractStruct(:Platform) {
  Method(:postPciInt, id: Int())
  Method(:clearPciInt, id: Int())
}

AbstractStruct(:VirtIODeviceBase) {
  Field(:deviceId, B32())
  Field(:deviceFeatures, B32())
  Method(:getGuestFeatures, Ret: B32())
  Method(:setGuestFeatures, value: B32())
  Method(:getQueueSelect, Ret: B32())
  Method(:setQueueSelect, value: B32())
  Method(:getQueueSize, Ret: B32())
  Method(:getQueueAddress, Ret: B32())
  Method(:setQueueAddress, value: B32())
  Method(:getDeviceStatus, Ret: B32())
  Method(:setDeviceStatus, value: B32())
  Method(:onNotify, value: B32())
  Method(:registerKickCallback, callback: Auto())
  Method(:readConfig, pkt: Ptr(Packet()), offset: B64())
  Method(:writeConfig, pkt: Ptr(Packet()), offset: B64())
}

AbstractStruct(:RiscvMmioVirtIOParams) {
  Field(:vio, Ptr(VirtIODeviceBase()))
}

AbstractMethod(:warn, message: String())

AbstractMethod(:warnOnce, message: String())

AbstractMethod(:panicIf, condition: Bool(), message: String())

AbstractMethod(:fail, message: String())

Device(:MmioVirtIO) {
  Const(:magic, B32(), 0x74726976)
  Const(:version, B32(), 1)
  Const(:vendor_id, B32(), 0x1af4)
  Const(:align_size, B32(), 0x1000)
  Const(:int_used_ring, B32(), 1)
  Const(:int_config, B32(), 2)
  Field(:hostFeaturesSelect, B32())
  Field(:guestFeaturesSelect, B32())
  Field(:pageSize, B32())
  Field(:interruptStatus, B32())
  Field(:vio, Ptr(VirtIODeviceBase()))
  Field(:kickCallback, Auto(), Lambda { kick })
  AbstractField(:platform, Ptr(Platform()))
  AbstractField(:_interruptID, Int())
  AbstractField(:pioAddr, B64())
  AbstractMethod(:readRegister, offset: B64(), Ret: B32())
  AbstractMethod(:writeRegister, offset: B64(), data: B32())

  Constructor(params: Ref(RiscvMmioVirtIOParams())) {
    Init(:hostFeaturesSelect, 0)
    Init(:guestFeaturesSelect, 0)
    Init(:pageSize, 0)
    Init(:interruptStatus, 0)
    Init(:vio, params.vio)
    Body {
      vio.registerKickCallback(kickCallback)
    }
  }

  Register(:magic_value, Size: 4, Offset: 0x00, Type: :ro) {
    Method(:read, Ret: B32()) {
      Return magic
    }
  }
  Register(:version_value, Size: 4, Offset: 0x04, Type: :ro) {
    Method(:read, Ret: B32()) {
      Return version
    }
  }
  Register(:device_id, Size: 4, Offset: 0x08, Type: :ro) {
    Method(:read, Ret: B32()) {
      Return vio.deviceId
    }
  }
  Register(:vendor, Size: 4, Offset: 0x0c, Type: :ro) {
    Method(:read, Ret: B32()) {
      Return vendor_id
    }
  }
  Register(:host_features, Size: 4, Offset: 0x10, Type: :ro) {
    Method(:read, Ret: B32()) {
      If(hostFeaturesSelect == 0) {
        Return vio.deviceFeatures
      }
      Return 0
    }
  }
  Register(:host_features_select, Size: 4, Offset: 0x14) {
    Method(:read, Ret: B32()) {
      Return hostFeaturesSelect
    }
    Method(:write, data: B32()) {
      hostFeaturesSelect[] = data
    }
  }
  Register(:guest_features, Size: 4, Offset: 0x20) {
    Method(:read, Ret: B32()) {
      If(guestFeaturesSelect == 0) {
        Return vio.getGuestFeatures
      }
      Return 0
    }
    Method(:write, data: B32()) {
      If(guestFeaturesSelect == 0) {
        vio.setGuestFeatures(data)
      }
      Elseif(data != 0) {
        warn('Setting unimplemented guest features register')
      }
    }
  }
  Register(:guest_features_select, Size: 4, Offset: 0x24) {

    Method(:read, Ret: B32()) {
      Return hostFeaturesSelect
    }
    Method(:write, data: B32()) {
      guestFeaturesSelect[] = data
    }
  }
  Register(:guest_page_size, Size: 4, Offset: 0x28) {
    Method(:read, Ret: B32()) {
      Return pageSize
    }
    Method(:write, data: B32()) {
      panicIf(data != align_size, 'Unhandled VirtIO page size')
      pageSize[] = data
    }
  }
  Register(:queue_select, Size: 4, Offset: 0x30) {
    Method(:read, Ret: B32()) {
      Return vio.getQueueSelect
    }
    Method(:write, data: B32()) {
      vio.setQueueSelect(data)
    }
  }
  Register(:queue_num_max, Size: 4, Offset: 0x34, Type: :ro) {
    Method(:read, Ret: B32()) {
      Return vio.getQueueSize
    }
  }
  Register(:queue_num, Size: 4, Offset: 0x38) {
    Method(:read, Ret: B32()) {
      Return vio.getQueueSize
    }
    Method(:write, data: B32()) {
      warnOnce('Ignoring queue resize hint')
    }
  }
  Register(:queue_align, Size: 4, Offset: 0x3c) {
    Method(:read, Ret: B32()) {
      Return align_size
    }
    Method(:write, data: B32()) {
      panicIf(data != align_size, 'Unhandled VirtIO alignment size')
    }
  }
  Register(:queue_pfn, Size: 4, Offset: 0x40) {
    Method(:read, Ret: B32()) {
      Return vio.getQueueAddress
    }
    Method(:write, data: B32()) {
      vio.setQueueAddress(data)
    }
  }
  Register(:queue_notify, Size: 4, Offset: 0x50, Type: :wo) {
    Method(:write, data: B32()) {
      vio.onNotify(data)
    }
  }
  Register(:interrupt_status, Size: 4, Offset: 0x60, Type: :ro) {
    Method(:read, Ret: B32()) {
      Return interruptStatus
    }
  }
  Register(:interrupt_ack, Size: 4, Offset: 0x64, Type: :wo) {
    Method(:write, data: B32()) {
      setInterrupts(interruptStatus & ~data)
    }
  }
  Register(:status, Size: 4, Offset: 0x70) {
    Method(:read, Ret: B32()) {
      Return vio.getDeviceStatus
    }
    Method(:write, data: B32()) {
      panicIf(data > 0xff, 'Unexpected status')
      vio.setDeviceStatus(data)
    }
  }



  Method(:kick) {
    setInterrupts(interruptStatus | int_used_ring)
  }

  Method(:setInterrupts, value: B32()) {
    Let :old_ints, B32(), interruptStatus
    interruptStatus[] = value
    If((old_ints == 0) & (interruptStatus != 0)) {
      platform.postPciInt(_interruptID)
    }
    Elseif((old_ints != 0) & (interruptStatus == 0)) {
      platform.clearPciInt(_interruptID)
    }
  }
  Checkpoint {
    Inherit()
  }
}
