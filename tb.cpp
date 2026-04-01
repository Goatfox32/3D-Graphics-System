#include <stdlib.h>
#include <iostream>
#include <iomanip>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vcommand_processor.h"

static vluint64_t sim_time = 0;
static Vcommand_processor *dut;
static VerilatedVcdC *trace;

void tick() {
    dut->clk = 0;
    dut->eval();
    trace->dump(sim_time++);
    dut->clk = 1;
    dut->eval();
    trace->dump(sim_time++);
}

void reset() {
    dut->reset_n = 0;
    dut->control = 0;
    dut->read_addr = 0;
    dut->read_size = 0;
    dut->avm_readdata = 0;
    dut->avm_readdatavalid = 0;
    dut->avm_waitrequest = 1;
    dut->rast_enable = 0;
    for (int i = 0; i < 5; i++) tick();
    dut->reset_n = 1;
    tick();
}

void pulse_start(uint32_t addr, uint32_t size) {
    dut->read_addr = addr;
    dut->read_size = size;
    dut->control = 0x01;
    tick();
    dut->control = 0x00;
}

void release_waitrequest() {
    dut->avm_waitrequest = 0;
    tick();
    dut->avm_waitrequest = 1;
    tick();
}

void send_beat(uint64_t data) {
    dut->avm_readdatavalid = 1;
    dut->avm_readdata = data;
    tick();
    dut->avm_readdatavalid = 0;
}

void wait_cycles(int n) {
    for (int i = 0; i < n; i++) tick();
}

bool check(const char *name, bool condition) {
    std::cout << (condition ? "  PASS: " : "  FAIL: ") << name << std::endl;
    return condition;
}

// ============================================================
// Test 1: Triangle command — happy path
// ============================================================
bool test_triangle_happy() {
    std::cout << "\n=== Test 1: Triangle command — happy path ===" << std::endl;
    bool ok = true;

    reset();

    ok &= check("Initially not busy", (dut->status & 0x01) == 0);

    // 32 bytes = 4 beats (1 cmd + 3 vertices)
    pulse_start(0x03000000, 32);
    tick();

    ok &= check("Busy after start", (dut->status & 0x01) == 1);
    ok &= check("avm_read asserted", dut->avm_read == 1);
    ok &= check("avm_burstcount == 4", dut->avm_burstcount == 4);
    ok &= check("avm_address correct", dut->avm_address == 0x03000000);

    release_waitrequest();

    ok &= check("avm_read deasserted", dut->avm_read == 0);

    // Beat 1: triangle command
    send_beat(0x0000000000000003ULL);
    tick();

    // Beat 2: vertex 0 — LSB is 0xCC
    send_beat(0x11111111111111CCULL);

    // Beat 3: vertex 1 — LSB is 0xBB
    send_beat(0x22222222222222BBULL);

    // Beat 4: vertex 2 — LSB is 0xAA
    send_beat(0x33333333333333AAULL);

    // Let it settle
    bool saw_valid = false;
    for (int i = 0; i < 5; i++) {
        if (dut->vertex_valid) { saw_valid = true; tick(); break; }
        tick();
    }
    ok &= check("vertex_valid pulsed", saw_valid);

    // Check vertex data
    uint64_t v0 = ((uint64_t)dut->vertex_data[5] << 32) | dut->vertex_data[4];
    uint64_t v1 = ((uint64_t)dut->vertex_data[3] << 32) | dut->vertex_data[2];
    uint64_t v2 = ((uint64_t)dut->vertex_data[1] << 32) | dut->vertex_data[0];

    std::cout << "  vertex[191:128] = 0x" << std::hex << v0 << std::endl;
    std::cout << "  vertex[127:64]  = 0x" << std::hex << v1 << std::endl;
    std::cout << "  vertex[63:0]    = 0x" << std::hex << v2 << std::endl;

    ok &= check("vertex[191:128] correct", v0 == 0x11111111111111CCULL);
    ok &= check("vertex[127:64] correct",  v1 == 0x22222222222222BBULL);
    ok &= check("vertex[63:0] correct",    v2 == 0x33333333333333AAULL);

    // Check LED status bits
    ok &= check("status[4] v2 LSB == 0xAA", (dut->status >> 4) & 1);
    ok &= check("status[5] v1 LSB == 0xBB", (dut->status >> 5) & 1);
    ok &= check("status[6] v0 LSB == 0xCC", (dut->status >> 6) & 1);
    ok &= check("status[7] all correct",    (dut->status >> 7) & 1);

    ok &= check("Back to not busy", (dut->status & 0x01) == 0);
    ok &= check("No size error", ((dut->status >> 1) & 1) == 0);

    return ok;
}

// ============================================================
// Test 2: Clear command — happy path
// ============================================================
bool test_clear_happy() {
    std::cout << "\n=== Test 2: Clear command — happy path ===" << std::endl;
    bool ok = true;

    reset();

    // 8 bytes = 1 beat (just the command)
    pulse_start(0x03000000, 8);
    tick();

    ok &= check("Busy", (dut->status & 0x01) == 1);
    ok &= check("avm_burstcount == 1", dut->avm_burstcount == 1);

    release_waitrequest();

    // Command beat: CLEAR (0x01)
    send_beat(0x0000000000000001ULL);

    // Check rast_clear pulses
    bool saw_clear = false;
    for (int i = 0; i < 5; i++) {
        if (dut->rast_clear) { saw_clear = true; tick(); break; }
        tick();
    }
    ok &= check("rast_clear pulsed", saw_clear);
    ok &= check("Back to not busy", (dut->status & 0x01) == 0);
    ok &= check("No size error", ((dut->status >> 1) & 1) == 0);

    return ok;
}

// ============================================================
// Test 3: Triangle with wrong burst size — size error
// ============================================================
bool test_triangle_size_error() {
    std::cout << "\n=== Test 3: Triangle with wrong burst size ===" << std::endl;
    bool ok = true;

    reset();

    // 8 bytes = 1 beat, but triangle expects 4
    pulse_start(0x03000000, 8);
    tick();

    ok &= check("avm_burstcount == 1", dut->avm_burstcount == 1);

    release_waitrequest();

    // Command beat: TRIANGLE (0x03)
    send_beat(0x0000000000000003ULL);

    wait_cycles(3);

    ok &= check("Size error set", (dut->status >> 1) & 1);
    ok &= check("vertex_valid stays low", dut->vertex_valid == 0);
    ok &= check("Back to not busy", (dut->status & 0x01) == 0);

    return ok;
}

// ============================================================
// Test 4: Clear with wrong burst size — size error
// ============================================================
bool test_clear_size_error() {
    std::cout << "\n=== Test 4: Clear with wrong burst size ===" << std::endl;
    bool ok = true;

    reset();

    // 32 bytes = 4 beats, but clear expects 1
    pulse_start(0x03000000, 32);
    tick();

    ok &= check("avm_burstcount == 4", dut->avm_burstcount == 4);

    release_waitrequest();

    // Command beat: CLEAR (0x01)
    send_beat(0x0000000000000001ULL);

    wait_cycles(3);

    ok &= check("Size error set", (dut->status >> 1) & 1);
    ok &= check("rast_clear stays low", dut->rast_clear == 0);
    ok &= check("Back to not busy", (dut->status & 0x01) == 0);

    return ok;
}

// ============================================================
// Test 5: NOP/unknown command — returns to idle
// ============================================================
bool test_nop_command() {
    std::cout << "\n=== Test 5: NOP/unknown command ===" << std::endl;
    bool ok = true;

    reset();

    pulse_start(0x03000000, 8);
    tick();

    release_waitrequest();

    // Command beat: unknown (0xFF)
    send_beat(0x00000000000000FFULL);

    wait_cycles(3);

    ok &= check("vertex_valid stays low", dut->vertex_valid == 0);
    ok &= check("rast_clear stays low", dut->rast_clear == 0);
    ok &= check("Back to not busy", (dut->status & 0x01) == 0);
    ok &= check("No size error", ((dut->status >> 1) & 1) == 0);

    return ok;
}

// ============================================================
// Test 6: Size error clears on next transaction
// ============================================================
bool test_size_error_clears() {
    std::cout << "\n=== Test 6: Size error clears on next transaction ===" << std::endl;
    bool ok = true;

    reset();

    // First: trigger a size error (triangle with burst=1)
    pulse_start(0x03000000, 8);
    tick();
    release_waitrequest();
    send_beat(0x0000000000000003ULL);
    wait_cycles(3);

    ok &= check("Size error set", (dut->status >> 1) & 1);

    // Second: start a new valid transaction
    pulse_start(0x03000000, 32);
    tick();

    ok &= check("Size error cleared on new start", ((dut->status >> 1) & 1) == 0);

    // Complete the transaction normally
    release_waitrequest();
    send_beat(0x0000000000000003ULL);
    tick();
    send_beat(0x11111111111111CCULL);
    send_beat(0x22222222222222BBULL);
    send_beat(0x33333333333333AAULL);

    bool saw_valid = false;
    for (int i = 0; i < 5; i++) {
        if (dut->vertex_valid) { saw_valid = true; tick(); break; }
        tick();
    }

    ok &= check("vertex_valid pulsed", saw_valid);
    ok &= check("No size error after valid transaction", ((dut->status >> 1) & 1) == 0);
    ok &= check("All correct LED", (dut->status >> 7) & 1);

    return ok;
}

// ============================================================
// Test 7: Gaps in readdatavalid during triangle
// ============================================================
bool test_triangle_with_gaps() {
    std::cout << "\n=== Test 7: Triangle with gaps in readdatavalid ===" << std::endl;
    bool ok = true;

    reset();

    pulse_start(0x03000000, 32);
    tick();
    release_waitrequest();

    send_beat(0x0000000000000003ULL);
    wait_cycles(8);

    send_beat(0xAAAAAAAAAAAAAAAAULL);
    wait_cycles(3);

    send_beat(0xBBBBBBBBBBBBBBBBULL);
    wait_cycles(15);

    send_beat(0xCCCCCCCCCCCCCCCCULL);

    bool saw_valid = false;
    for (int i = 0; i < 5; i++) {
        if (dut->vertex_valid) { saw_valid = true; tick(); break; }
        tick();
    }
    ok &= check("vertex_valid pulsed despite gaps", saw_valid);

    uint64_t v0 = ((uint64_t)dut->vertex_data[5] << 32) | dut->vertex_data[4];
    uint64_t v1 = ((uint64_t)dut->vertex_data[3] << 32) | dut->vertex_data[2];
    uint64_t v2 = ((uint64_t)dut->vertex_data[1] << 32) | dut->vertex_data[0];

    ok &= check("v0 correct", v0 == 0xAAAAAAAAAAAAAAAAULL);
    ok &= check("v1 correct", v1 == 0xBBBBBBBBBBBBBBBBULL);
    ok &= check("v2 correct", v2 == 0xCCCCCCCCCCCCCCCCULL);

    return ok;
}

// ============================================================
// Test 8: Long waitrequest
// ============================================================
bool test_long_waitrequest() {
    std::cout << "\n=== Test 8: Waitrequest held 30 cycles ===" << std::endl;
    bool ok = true;

    reset();

    pulse_start(0x03000000, 32);
    tick();

    // Verify avm_read and stuck indicator hold for 30 cycles
    bool held = true;
    for (int i = 0; i < 30; i++) {
        if (!dut->avm_read) held = false;
        if (!((dut->status >> 3) & 1)) held = false;
        tick();
    }
    ok &= check("avm_read held for 30 cycles", held);
    ok &= check("Stuck indicator held for 30 cycles", held);

    release_waitrequest();
    ok &= check("avm_read deasserted", dut->avm_read == 0);

    // Complete normally
    send_beat(0x0000000000000003ULL);
    tick();
    send_beat(0x1111111111111111ULL);
    send_beat(0x2222222222222222ULL);
    send_beat(0x3333333333333333ULL);
    wait_cycles(5);

    ok &= check("Back to not busy", (dut->status & 0x01) == 0);

    return ok;
}

// ============================================================
// Test 9: Clear followed by triangle
// ============================================================
bool test_clear_then_triangle() {
    std::cout << "\n=== Test 9: Clear followed by triangle ===" << std::endl;
    bool ok = true;

    reset();

    // Transaction 1: clear
    pulse_start(0x03000000, 8);
    tick();
    release_waitrequest();
    send_beat(0x0000000000000001ULL);

    bool saw_clear = false;
    for (int i = 0; i < 5; i++) {
        if (dut->rast_clear) { saw_clear = true; tick(); break; }
        tick();
    }
    ok &= check("Clear: rast_clear pulsed", saw_clear);
    ok &= check("Clear: not busy", (dut->status & 0x01) == 0);

    // Transaction 2: triangle
    pulse_start(0x03000000, 32);
    tick();
    release_waitrequest();
    send_beat(0x0000000000000003ULL);
    tick();
    send_beat(0xDEADDEADDEAD00CCULL);
    send_beat(0xBEEFBEEFBEEF00BBULL);
    send_beat(0xCAFECAFECAFE00AAULL);

    bool saw_valid = false;
    for (int i = 0; i < 5; i++) {
        if (dut->vertex_valid) { saw_valid = true; tick(); break; }
        tick();
    }
    ok &= check("Triangle: vertex_valid pulsed", saw_valid);
    ok &= check("Triangle: all correct LED", (dut->status >> 7) & 1);
    ok &= check("Triangle: not busy", (dut->status & 0x01) == 0);

    return ok;
}

// ============================================================
// Test 10: DRAW_PIXEL — not implemented, returns to idle
// ============================================================
bool test_draw_pixel_nop() {
    std::cout << "\n=== Test 10: DRAW_PIXEL returns to idle ===" << std::endl;
    bool ok = true;

    reset();

    pulse_start(0x03000000, 8);
    tick();
    release_waitrequest();

    // Command: DRAW_PIXEL (0x02)
    send_beat(0x0000000000000002ULL);

    wait_cycles(3);

    ok &= check("vertex_valid stays low", dut->vertex_valid == 0);
    ok &= check("rast_clear stays low", dut->rast_clear == 0);
    ok &= check("Back to not busy", (dut->status & 0x01) == 0);

    return ok;
}

// ============================================================
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vcommand_processor;
    trace = new VerilatedVcdC;
    dut->trace(trace, 99);
    trace->open("command_processor.vcd");

    int pass = 0, fail = 0;

    test_triangle_happy()       ? pass++ : fail++;
    test_clear_happy()          ? pass++ : fail++;
    test_triangle_size_error()  ? pass++ : fail++;
    test_clear_size_error()     ? pass++ : fail++;
    test_nop_command()          ? pass++ : fail++;
    test_size_error_clears()    ? pass++ : fail++;
    test_triangle_with_gaps()   ? pass++ : fail++;
    test_long_waitrequest()     ? pass++ : fail++;
    test_clear_then_triangle()  ? pass++ : fail++;
    test_draw_pixel_nop()       ? pass++ : fail++;

    std::cout << "\n========================================" << std::endl;
    std::cout << std::dec << "  " << pass << " tests passed, " << fail << " tests failed" << std::endl;
    std::cout << "========================================" << std::endl;

    trace->close();
    delete trace;
    delete dut;

    return fail > 0 ? 1 : 0;
}