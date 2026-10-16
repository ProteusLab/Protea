# frozen_string_literal: true

# PLOD source notice begin
# /*
#  * Copyright (c) 2021 Huawei International
#  * Copyright (c) 2023 Google LLC
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

AbstractStruct(:BaseCPU) {
  Method(:postInterrupt, tid: Int(), interrupt: Int(), index: Int())
  Method(:clearInterrupt, tid: Int(), interrupt: Int(), index: Int())
}

AbstractStruct(:ThreadContext) {
  Method(:getCpuPtr, Ret: Ptr(BaseCPU()))
  Method(:threadId, Ret: Int())
}

AbstractStruct(:Threads) {
  Method(:at, index: Int(), Ret: Ptr(ThreadContext()))
}

AbstractStruct(:System) {
  Field(:threads, Threads())
}

AbstractStruct(:PlicParams) {
  Field(:system, Ptr(System()))
  Field(:n_src, Int())
  Field(:n_contexts, Int())
  Field(:hart_config, String())
  Field(:output_latency, B64())
  Field(:name, String())
}

AbstractStruct(:EventFunctionWrapper) {
  Method(:scheduled, Ret: Bool())
}

AbstractStruct(:Cycles) {}

AbstractMethod(:makeCycles, cycles: B64(), Ret: Cycles())

AbstractMethod(:clockEdge, cycles: Cycles(), Ret: B64())

AbstractMethod(:require, condition: Bool())

AbstractMethod(:fatalIf, condition: Bool(), message: String())

AbstractMethod(:warn, message: String())

AbstractMethod(:toString, value: Int(), Ret: String())

Struct(:PlicContext) {
  Field(:hart, B32())
  Field(:interrupt, Int())
}

Struct(:PlicOutput) {
  Field(:maxID, Vector(B32()))
  Field(:maxPriority, Vector(B32()))
}

Device(:Plic) {
  Const(:int_ext_machine, Int(), 11)
  Const(:int_ext_super, Int(), 9)

  Field(:system, Ptr(System()))
  Field(:nSrc, Int())
  Field(:nSrc32, Int())
  Field(:contextConfigs, Vector(PlicContext()))
  Field(:outputLatency, B64())
  Field(:pendingPriority, Vector(B32()))
  Field(:effPriority, Vector(Vector(B32())))
  Field(:lastID, Vector(B32()))
  Field(:output, PlicOutput())
  Field(:outputQueue, Map(B64(), PlicOutput()))
  Field(:updateCallback, Auto(), Lambda { updateOutput })
  Field(:update, EventFunctionWrapper())

  AbstractField(:pioDelay, B64())
  AbstractField(:pioSize, B64())
  AbstractMethod(:initRegisters)
  AbstractMethod(:scheduleEvent, event: Ref(EventFunctionWrapper()), next_update: B64())
  AbstractMethod(:basicInit)

  Constructor(params: Ref(PlicParams())) {
    Init(:system, params.system)
    Init(:nSrc, params.n_src)
    Init(:outputLatency, params.output_latency)
    Init(:update, updateCallback, params.name + '.update')
    Body {
      fatalIf((params.hart_config != '') & (params.n_contexts != 0), "the hart_config and n_contexts can't be set simultaneously")
      If(params.n_contexts != 0) {
        initContextFromNContexts(params.n_contexts)
      }
      If(params.hart_config != '') {
        initContextFromHartConfig(params.hart_config)
      }
    }
  }

  Method(:initContextFromNContexts, count: Int()) {

    For(Iter: :i, Init: 0, To: count) {
      If(i % 2 == 0) {
        Var :context, PlicContext()
        context.hart[] = i >> 1
        context.interrupt[] = int_ext_machine
        contextConfigs.push(context)
        context.interrupt[] = int_ext_super
        contextConfigs.push(context)
      }
    }
  }

  Method(:initContextFromHartConfig, config: String()) {
    Var :context, PlicContext()
    context.hart[] = 0
    For(Iter: :i, Init: 0, To: config.size) {
      Let :c, B8(), config.at(i)
      If(c == 0x2c) {
        context.hart[] = context.hart + 1
      }
      Elseif(c == 0x4d) {
        context.interrupt[] = int_ext_machine
        contextConfigs.push(context)
      }
      Elseif(c == 0x53) {
        context.interrupt[] = int_ext_super
        contextConfigs.push(context)
      }
      Else {
        fatalIf(1, 'hart_config should not contain this value')
      }
    }
  }

  Method(:init) {
    nSrc32[] = (nSrc + 31) / 32
    require(pioSize >= 0x200000 + contextConfigs.size * 0x1000)
    require(pioSize <= 0x4000000)
    initRegisters
    pendingPriority.resize(nSrc, 0)
    effPriority.resize(contextConfigs.size)
    For(Iter: :i, Init: 0, To: contextConfigs.size) {
      effPriority.at(i).resize(nSrc, 0)
    }
    lastID.resize(contextConfigs.size, 0)
    output.maxID.resize(contextConfigs.size, 0)
    output.maxPriority.resize(contextConfigs.size, 0)
    basicInit
  }

  Method(:post, src_id: Int()) {
    require((src_id < nSrc) & (src_id >= 0))
    Let :word, Int(), src_id >> 5
    Let :bit, Int(), src_id & 0x1f
    pending.set(word, pending.at(word) | Cast(B32(), 1) << bit)
    pendingPriority.set(src_id, priority.at(src_id))
    For(Iter: :i, Init: 0, To: contextConfigs.size) {
      If(enable.at(i * nSrc32 + word) >> bit & 1) {
        effPriority.at(i).set(src_id, pendingPriority.at(src_id))
      }
      Else {
        effPriority.at(i).set(src_id, 0)
      }
    }
    propagateOutput
  }

  Method(:clear, src_id: Int()) {
    require((src_id < nSrc) & (src_id >= 0))
    Let :word, Int(), src_id >> 5
    Let :bit, Int(), src_id & 0x1f
    pending.set(word, pending.at(word) & ~(Cast(B32(), 1) << bit))
    pendingPriority.set(src_id, 0)
    For(Iter: :i, Init: 0, To: contextConfigs.size) {
      effPriority.at(i).set(src_id, 0)
    }
    propagateOutput
  }

  Register(:priority, Size: 4, Offset: 0, Window: 0x1000) {
    Layout {
      Repeat(nSrc, 4)
    }
    Method(:write, data: B32()) {
      Self[] = data
      Let :word, Int(), cid >> 5
      Let :bit, Int(), cid & 0x1f
      If(pending.at(word) >> bit & 1) {
        pendingPriority.set(cid, data)
      }
      Else {
        pendingPriority.set(cid, 0)
      }
      For(Iter: :i, Init: 0, To: contextConfigs.size) {
        If(enable.at(i * nSrc32 + word) >> bit & 1) {
          effPriority.at(i).set(cid, pendingPriority.at(cid))
        }
        Else {
          effPriority.at(i).set(cid, 0)
        }
      }
    }
  }

  Register(:pending, Size: 4, Offset: 0x1000, Type: :ro, Window: 0x1000) {
    Layout {
      Repeat(nSrc32, 4)
    }
  }

  Register(:enable, Size: 4, Offset: 0x2000, Window: 0x1fe000) {
    Layout {
      Repeat(contextConfigs.size, 0x80)
      Repeat(nSrc32, 4)
    }
    Method(:write, data: B32()) {
      Self[] = data
      Let :context, Int(), cid / nSrc32
      Let :word, Int(), cid % nSrc32
      For(Iter: :i, Init: 0, To: 32) {
        Let :src_id, Int(), (word << 5) + i
        If(src_id < nSrc) {
          If(data >> i & 1) {
            effPriority.at(context).set(src_id, pendingPriority.at(src_id))
          }
          Else {
            effPriority.at(context).set(src_id, 0)
          }
        }
      }
    }
  }

  Register(:threshold, Size: 4, Offset: 0x200000) {
    Layout {
      Repeat(contextConfigs.size, 0x1000)
    }
  }

  Register(:claim, Size: 4, Offset: 0x200004) {
    Layout {
      Repeat(contextConfigs.size, 0x1000)
    }
    Method(:read, Ret: B32()) {
      If(lastID.at(cid) == 0) {
        Let :max_id, B32(), output.maxID.at(cid)
        Let :word, Int(), max_id >> 5
        Let :bit, Int(), max_id & 0x1f
        If(pending.at(word) >> bit & 1) {
          lastID.set(cid, max_id)
          clear(max_id)
          Self[] = max_id
          Return Self
        }
        Return 0
      }
      warn('PLIC claim repeated (not completed)')
      Return lastID.at(cid)
    }
    Method(:write, data: B32()) {
      Self[] = data
      require(lastID.at(cid) == data)
      lastID.set(cid, 0)
      updateInt
    }
  }


  Method(:propagateOutput) {
    Var :new_output, PlicOutput()
    new_output.maxID.resize(contextConfigs.size, 0)
    new_output.maxPriority.resize(contextConfigs.size, 0)
    For(Iter: :i, Init: 0, To: contextConfigs.size) {
      Let :max_id, B32(), 0
      Let :max_priority, B32(), effPriority.at(i).at(0)
      For(Iter: :j, Init: 1, To: nSrc) {
        If(effPriority.at(i).at(j) > max_priority) {
          max_id[] = j
          max_priority[] = effPriority.at(i).at(j)
        }
      }
      new_output.maxID.set(i, max_id)
      new_output.maxPriority.set(i, max_priority)
    }
    Let :next_update, B64(), clockEdge(makeCycles(outputLatency))
    outputQueue.put(next_update, new_output)
    If(update.scheduled == 0) {
      scheduleEvent(update, next_update)
    }
  }

  Method(:updateOutput) {
    output[] = outputQueue.firstValue
    outputQueue.eraseFirst
    If(outputQueue.empty == 0) {
      scheduleEvent(update, outputQueue.firstKey)
    }
    updateInt
  }

  Method(:updateInt) {
    For(Iter: :i, Init: 0, To: contextConfigs.size) {
      Let :tc, Ptr(ThreadContext()), system.threads.at(contextConfigs.at(i).hart)
      Let :max_id, B32(), output.maxID.at(i)
      Let :value, B32(), output.maxPriority.at(i)
      Let :limit, B32(), threshold.at(i)
      If((value > limit) & (max_id > 0) & (lastID.at(i) == 0)) {
        tc.getCpuPtr.postInterrupt(tc.threadId, contextConfigs.at(i).interrupt, 0)
      }
      Else {
        tc.getCpuPtr.clearInterrupt(tc.threadId, contextConfigs.at(i).interrupt, 0)
      }
    }
  }

  Method(:restoreOutputEvent) {
    If(outputQueue.empty == 0) {
      scheduleEvent(update, outputQueue.firstKey)
    }
  }
  Checkpoint {
    Repeat(:i, nSrc32) {
      Scalar(Literal('pending') + toString(i), pending.at(i))
    }
    Repeat(:i, nSrc) {
      Scalar(Literal('priority') + toString(i), priority.at(i))
    }
    Repeat(:i, contextConfigs.size) {
      Repeat(:j, nSrc32) {
        Scalar(Literal('enable') + toString(i) + '_' + toString(j), enable.at(i * nSrc32 + j))
      }
      Scalar(Literal('threshold') + toString(i), threshold.at(i))
      Scalar(Literal('claim') + toString(i), claim.at(i))
    }
    OrderedMap(outputQueue, Count: 'n_outputs', CountType: B32(), Iter: :i, Key: :tick, Value: :snapshot) {
      Scalar(Literal('output_tick') + toString(i), tick)
      Array(Literal('output_id') + toString(i), snapshot.maxID)
      Array(Literal('output_pri') + toString(i), snapshot.maxPriority)
    }
    AfterRestore(:restoreOutputEvent)
    Array('output.maxID', output.maxID)
    Array('output.maxPriority', output.maxPriority)
    Array('pendingPriority', pendingPriority)
    Repeat(:i, contextConfigs.size) {
      Array(Literal('effPriority') + toString(i), effPriority.at(i))
    }
    Array('lastID', lastID)
    AfterRestore(:updateInt)
  }
}
