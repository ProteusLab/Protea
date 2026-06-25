PRESET_NAME=$1

cmake -S . \
  --preset "${PRESET_NAME}" \
  -DPROTEA_BUILD_TESTS=true \
  -DQEMU_PATH=qemu-riscv32 \
  -G Ninja

cmake --build --preset "${PRESET_NAME}" --target simtests --parallel 12

ctest --preset "${PRESET_NAME}"
