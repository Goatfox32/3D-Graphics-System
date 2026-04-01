#!/bin/bash
set -e

echo "=== Verilating ==="
verilator --cc --trace --exe \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL \
    command_processor.sv \
    tb.cpp

echo "=== Building ==="
make -C obj_dir -f Vcommand_processor.mk Vcommand_processor -j$(nproc)

echo "=== Running ==="
./obj_dir/Vcommand_processor

echo ""
echo "=== Waveform saved to command_processor.vcd ==="
echo "Open with: surfer command_processor.vcd"