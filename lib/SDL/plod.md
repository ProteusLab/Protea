# Plod

**Plod(Protea Language fOr Devices)** — It is a simple programming language that combines both imperative and declarative description styles. The main purpose of this language is to describe peripheral devices.

---

## Syntax and features

### 1. Vars and data types

#### Vars

A variable can be defined using the Let or Var operators.


```
// Example of creating variables
Let :interval, Tick(), ns * 225
Var :data, B8()
```

The first argument of the operator is the name of the variable, the second is the type, and the third is the value that is omitted for the Var operator.

#### Types

The language has four built-in types: B\<N>, Int, Bool, Array\<T, N>.

Template type parameters are specified in parentheses after the type identifier.

For a bit type, its size can be specified not in parentheses, but immediately after the identifier.

```
// Example of types
Int()
B32()
B(9)
Array<B14(), 8>
```

#### Arithmetic operations

All standard arithmetic operations are available for bit and int types.

The assignment operation has a specific syntax, however. This is due to the specifics of the Ruby language.

```
a[]= x * x + y / 2
```

#### User types

User types are described using the Struct keyword. The scope of the structure describes its methods and fields.

"init" name is reserved for the constructor method.

```
// Struct
Struct(:fifo8) {
    Method(:init) {
        front[]= 0
        size[]= 0
    }

    Method(:push, value: b8) {
        buf.set((front + size) % buf.type_info.size, value)
        size[]= size + 1
    }

    Method(:pop, ret: b8) {
        var :valToRet, b8

        valToRet[]= buf.get(front)
        front[]= (front + 1) % buf.type_info.size
        size[]= size - 1
        ret valToRet
    }

    Method(:is_empty, ret: b1) {
        let :empty, b1, size == 0
        ret empty
    }

    Field(:buf, array(b8, 8))
    Field(:front, int)
    Field(:size, int)
}
```

User types can be used on a par with the built-in ones.

#### Abstract types

The language contains abstract types for which only method signatures are described, but not their implementation.

```
// Struct
AbstractStruct(:SerialDevice) {
    Method(:dataAvailable, ret: Bool())
    Method(:readData, ret: B8())
}
```

They are the link between the programming language and the environment in which assembly artifacts are embedded.

### 2. Сontrol flow

#### If/Else

If statement can take an Int or B value. The branch corresponding to the true is executed if the passed value is greater than zero.

```
// Control flow
If(device.dataAvailable() & ier.rda()) {
    scheduleIntr(GetPtr(rxIntrEvent))
}
Else {
    If(rxIntrEvent.scheduled()) {
        deschedule(GetPtr(rxIntrEvent))
    }
}
```

#### For

At the current moment, only the For loop is represented in the language. It specifies the name of the integration variable, its initial and final values. The iteration step is always 1.

```
// Example of a for loop
For(iter: :i, init: 0x0, end: 0x8) {
    buff[i][]= buff[i] * 2
}
```

### 3. Methods

Its signature and implementation are described for the methods. The type of the returned value is indicated using the reserved word ret. If ret is omitted in the signature, it is assumed that the return value type is void.

```
// Example of method
Method(:dataAvailable) {
    If(ier.rda()) {
    platform.postConsoleInt()
    status[]= status | rx_int
    }
}
```

#### Abstract methods

For an abstract method, only the signature is described.

```
// Example of abstract methods
AbstractMethod(:deschedule, event: Ptr(Event()))
```

### 4. Devices

The device is the basic essence of the language. In many ways, it is similar to the usual structure, with the only exception that a register bank must be described for the device.

```
// Example of device
Device(:ns16550) {
    Register(:rbr) {
      size 0x1
      offset 0x0
      type :ro
    }
}
```

The register bank is described by describing the registers individually.

#### Registers

The Register keyword is used for registers.

```
// Example of register
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
```

A register is described by properties such as its size, offset within the register bank, and supported access types. Additionally, the register's read and write semantics are described by implementing functions named read and write. The enableIf keyword allows specifying a predicate that determines when the register is active. Custom methods can also be added.

An important part of a register's description is the description of its bit fields. These are specified either by a simple register offset, in which case the field size is assumed to be one, or by the first and last bits inclusive. These fields can be accessed both within the register and externally. Regular fields, similar to structure fields, can also be added to the register description.

### 5. Other

#### Enum

Enum is no different from similar entities in other languages, except that the type of its values ​​is always Int.

```
// Example of enum
Enum(:interruptIds) {
    Modem(0)
    Tx(1)
    Rx(2)
    Line(3)
}
```

#### Lambda

Lambda syntax mirrors Method syntax, with the exception of the keyword used. An anonymous function can be used as a value, passed to other functions, or used as a default value.

```
// Example of lambda
Lambda { processIntrEvent(tx_int) }
```

