# gem5/Generic/types.py


class OperandType:
    _STANDARD_WIDTHS = [1, 8, 16, 32, 64, 128]

    @classmethod
    def gen(cls, width: int, signed: bool = False) -> str:
        rounded = cls.bits(width)
        if rounded == 1:
            return "bool"
        prefix = "" if signed else "u"
        return f"{prefix}int{rounded}_t"

    @classmethod
    def bits(cls, width: int) -> int:
        return next(s for s in cls._STANDARD_WIDTHS if s >= width)
