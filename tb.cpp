#include "Vf2h_sdram_test_master.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <stdio.h>
#include <stdlib.h>

static vluint64_t sim_time = 0;
static Vf2h_sdram_test_master* dut;
static VerilatedVcdC* tfp;
static int test_num = 0;
static int pass_count = 0;
static int fail_count = 0;

void tick() {
    dut->clk = 0; dut->eval(); tfp->dump(sim_time++);
    dut->clk = 1; dut->eval(); tfp->dump(sim_time++);
}

void reset() {
    dut->reset_n = 0;
    dut->start = 0;
    dut->read_addr = 0;
    dut->read_size = 0;
    dut->avm_waitrequest = 0;
    dut->avm_readdatavalid = 0;
    dut->avm_readdata = 0;
    for (int i = 0; i < 4; i++) tick();
    dut->reset_n = 1;
    tick();
}

void check(const char* name, int condition) {
    test_num++;
    if (condition) {
        printf("  [PASS] %s\n", name);
        pass_count++;
    } else {
        printf("  [FAIL] %s\n", name);
        fail_count++;
    }
}

// Drive a burst read from the slave side.
//   wait_cycles:  how many cycles to hold waitrequest after read is seen
//   beat_count:   number of readdatavalid beats to send
//   gap_pattern:  array of ints, one per beat. Value = number of idle cycles
//                 BEFORE that beat. NULL means no gaps (back-to-back).
//   first_byte:   value placed in readdata[7:0] on the first beat
void drive_slave(int wait_cycles, int beat_count, int* gap_pattern, uint8_t first_byte) {

    // Wait for avm_read to assert
    int timeout = 50;
    while (!dut->avm_read && timeout-- > 0) tick();
    if (timeout <= 0) { printf("  [TIMEOUT] waiting for avm_read\n"); return; }

    // Hold waitrequest
    dut->avm_waitrequest = 1;
    for (int i = 0; i < wait_cycles; i++) tick();
    dut->avm_waitrequest = 0;
    tick(); // This is the cycle where read is accepted (!waitrequest && avm_read)

    // Now deliver beats
    for (int beat = 0; beat < beat_count; beat++) {
        // Insert gap before this beat if requested
        int gap = (gap_pattern != NULL) ? gap_pattern[beat] : 0;
        dut->avm_readdatavalid = 0;
        for (int g = 0; g < gap; g++) tick();

        // Drive one valid beat
        dut->avm_readdatavalid = 1;
        if (beat == 0)
            dut->avm_readdata = (uint64_t)first_byte;
        else
            dut->avm_readdata = 0xDEAD000000000000ULL | beat;
        tick();
    }

    dut->avm_readdatavalid = 0;
}

// ---------------------------------------------------------------
// Test 1: Single-beat read (read_size=8, burstcount=1)
// ---------------------------------------------------------------
void test_single_beat() {
    printf("\nTest: Single-beat read (read_size=8)\n");
    reset();

    dut->read_addr = 0x00001000;
    dut->read_size = 8;
    dut->start = 1;
    tick();
    dut->start = 0;

    drive_slave(/*wait_cycles=*/0, /*beat_count=*/1, NULL, 0xAB);

    // Let done propagate
    for (int i = 0; i < 4; i++) tick();

    check("done is asserted",    dut->done == 1);
    check("result is 0xAB",      dut->result == 0xAB);
    check("avm_read deasserted", dut->avm_read == 0);
}

// ---------------------------------------------------------------
// Test 2: Multi-beat burst (read_size=32, burstcount=4)
// ---------------------------------------------------------------
void test_multi_beat() {
    printf("\nTest: Multi-beat burst (read_size=32, burstcount=4)\n");
    reset();

    dut->read_addr = 0x00002000;
    dut->read_size = 32;
    dut->start = 1;
    tick();
    dut->start = 0;

    drive_slave(0, 4, NULL, 0x42);

    for (int i = 0; i < 4; i++) tick();

    check("done is asserted",       dut->done == 1);
    check("result is 0x42",         dut->result == 0x42);
}

// ---------------------------------------------------------------
// Test 3: Gaps in readdatavalid mid-burst
// ---------------------------------------------------------------
void test_gaps_in_valid() {
    printf("\nTest: Gaps in readdatavalid (4 beats with pauses)\n");
    reset();

    dut->read_addr = 0x00003000;
    dut->read_size = 32;
    dut->start = 1;
    tick();
    dut->start = 0;

    // gap_pattern: 0 idle before beat 0, 3 before beat 1, 0 before beat 2, 5 before beat 3
    int gaps[] = {0, 3, 0, 5};
    drive_slave(0, 4, gaps, 0x77);

    for (int i = 0; i < 4; i++) tick();

    check("done is asserted",  dut->done == 1);
    check("result is 0x77",    dut->result == 0x77);
}

// ---------------------------------------------------------------
// Test 4: Extended waitrequest
// ---------------------------------------------------------------
void test_long_waitrequest() {
    printf("\nTest: Waitrequest held for 10 cycles\n");
    reset();

    dut->read_addr = 0x00004000;
    dut->read_size = 8;
    dut->start = 1;
    tick();
    dut->start = 0;

    drive_slave(/*wait_cycles=*/10, 1, NULL, 0x55);

    for (int i = 0; i < 4; i++) tick();

    check("done is asserted",  dut->done == 1);
    check("result is 0x55",    dut->result == 0x55);
}

// ---------------------------------------------------------------
// Test 5: Back-to-back transactions
// ---------------------------------------------------------------
void test_back_to_back() {
    printf("\nTest: Back-to-back transactions\n");
    reset();

    // First transaction
    dut->read_addr = 0x00005000;
    dut->read_size = 8;
    dut->start = 1;
    tick();
    dut->start = 0;

    drive_slave(0, 1, NULL, 0x11);
    for (int i = 0; i < 4; i++) tick();

    check("txn1: done asserted",  dut->done == 1);
    check("txn1: result is 0x11", dut->result == 0x11);

    // Second transaction without reset
    dut->read_addr = 0x00006000;
    dut->read_size = 16;
    dut->start = 1;
    tick();
    dut->start = 0;

    drive_slave(2, 2, NULL, 0x22);
    for (int i = 0; i < 4; i++) tick();

    check("txn2: done asserted",  dut->done == 1);
    check("txn2: result is 0x22", dut->result == 0x22);
}

// ---------------------------------------------------------------
// Test 6: Small read_size (1 byte — burstcount should be 1)
// ---------------------------------------------------------------
void test_small_read_size() {
    printf("\nTest: Minimum read_size=1 (burstcount should be 1)\n");
    reset();

    dut->read_addr = 0x00007000;
    dut->read_size = 1;
    dut->start = 1;
    tick();
    dut->start = 0;

    drive_slave(0, 1, NULL, 0xEE);

    for (int i = 0; i < 4; i++) tick();

    check("done is asserted",  dut->done == 1);
    check("result is 0xEE",    dut->result == 0xEE);
}

// ---------------------------------------------------------------

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    dut = new Vf2h_sdram_test_master;
    tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("waveform.vcd");

    test_single_beat();
    test_multi_beat();
    test_gaps_in_valid();
    test_long_waitrequest();
    test_back_to_back();
    test_small_read_size();

    printf("\n=============================\n");
    printf("Results: %d passed, %d failed out of %d\n", pass_count, fail_count, test_num);
    printf("=============================\n");

    tfp->close();
    dut->final();
    delete dut;

    return fail_count > 0 ? 1 : 0;
}