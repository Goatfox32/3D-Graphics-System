// Braden Vanderwoerd
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// comm.c — HPS-to-GPU communication layer.
// Maps physical memory regions (/dev/mem) for the lightweight AXI bridge, SDRAM controller
// registers, and the shared command buffer. Provides high-level functions to issue GPU
// commands (clear, present, draw_triangle, draw_sprite) by writing command packets into
// the shared SDRAM buffer and triggering the hardware command reader via PIO registers.
//
// NOTE: draw_triangle() accepts per-vertex RGB colors for all three vertices, but the
// hardware rasterizer currently only uses vertex 1's color (flat shading). The extra
// color parameters are retained for forward compatibility with color interpolation.

#include "comm.h"

// --- Physical memory regions (mapped via /dev/mem mmap)
#define LW_BRIDGE_BASE 0xFF200000   // Lightweight HPS-to-FPGA AXI bridge
#define LW_BRIDGE_SIZE 0x1000
#define SDR_BASE       0xFFC25000   // SDRAM controller registers
#define SDR_SIZE       0x1000
#define BUFFER_BASE    0x18000000   // Shared SDRAM command buffer (FPGA-accessible)
#define BUFFER_SIZE    0x10000

// --- PIO register offsets within the lightweight bridge (word-indexed)
// These must match the Qsys base addresses in graphics_system.tcl
#define CMD_ADDR    (0x00 / 4)      // Command buffer SDRAM address
#define CMD_SIZE    (0x10 / 4)      // Command size in bytes
#define GPU_CONTROL (0x20 / 4)      // Control register (bit 0 = start)
#define GPU_STATUS  (0x30 / 4)      // Status register (bit 0 = busy)

// --- SDRAM controller configuration registers (for F2H port setup)
#define STATICCFG   (0x5C / 4)
#define CPORTWIDTH  (0x64 / 4)
#define CPORTWMAP   (0x68 / 4)
#define CPORTRMAP   (0x6C / 4)
#define RFIFOCMAP   (0x70 / 4)
#define WFIFOCMAP   (0x74 / 4)
#define CPORTRDWR   (0x78 / 4)
#define FPGAPORTRST (0x80 / 4)

#define STOP  0x00000000
#define START 0x00000001

static volatile uint32_t *lw, *sdr;  // Memory-mapped register pointers
static volatile uint8_t *data;       // Shared SDRAM command buffer

static volatile uint32_t *map_physical(int fd, off_t base, size_t size) {
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    if (p == MAP_FAILED) { perror("mmap"); exit(1); }
    return (volatile uint32_t *)p;
}

// Pack vertex data into the 64-bit hardware format:
// [8:0] x (9 bits), [16:9] y (8 bits), [21:17] r (5 bits), [27:22] g (6 bits), [32:28] b (5 bits)
static uint64_t pack_vertex(int x, int y, int r, int g, int b) {
    return ((uint64_t)(x & 0x1FF))
         | ((uint64_t)(y & 0xFF) << 9)
         | ((uint64_t)(r & 0x1F) << 17)
         | ((uint64_t)(g & 0x3F) << 22)
         | ((uint64_t)(b & 0x1F) << 28);
}

void init_comm() {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem"); exit(1); }

    lw   = map_physical(fd, LW_BRIDGE_BASE, LW_BRIDGE_SIZE);
    sdr  = map_physical(fd, SDR_BASE, SDR_SIZE);
    data = (volatile uint8_t*) map_physical(fd, BUFFER_BASE, BUFFER_SIZE);
}

// Write a command packet to shared SDRAM and trigger the hardware command reader.
// Blocks until the GPU is idle (busy bit clear) before writing.
void send_command(uint8_t cmd, uint8_t *arg, int command_len) {

    while (lw[GPU_STATUS] & 0x01) { } // Poll busy bit

    // Write command byte + payload into shared SDRAM buffer
    data[0] = (uint32_t)cmd;
    for (int i = 0; i < command_len-1; i++) {
        data[i+1] = (uint32_t)arg[i];
    }

    // Trigger the command reader: deassert start, set address/size, pulse start
    lw[GPU_CONTROL] = STOP;
    usleep(100);

    lw[CMD_ADDR] = (BUFFER_BASE >> 3); // Convert byte address to 8-byte-aligned SDRAM address
    lw[CMD_SIZE] = command_len;

    lw[GPU_CONTROL] = START;   // Rising edge triggers start_pulse in command_reader
    usleep(100);
    lw[GPU_CONTROL] = STOP;
}

uint8_t read_status() {
    return lw[GPU_STATUS];
}

void clear() {
    send_command(0x01, NULL, 1);
}

void present_frame() {
    send_command(0x02, NULL, 1);
}

// Draw a filled triangle. All three vertices carry color fields, but the hardware
// rasterizer currently only uses vertex 1's color (flat shading). Vertex 2 and 3
// colors are packed for forward compatibility with barycentric color interpolation.
void draw_triangle(int x1, int y1, int r1, int g1, int b1,
                   int x2, int y2, int r2, int g2, int b2,
                   int x3, int y3, int r3, int g3, int b3) {

    uint64_t vertex0 = pack_vertex(x1, y1, r1, g1, b1);
    uint64_t vertex1 = pack_vertex(x2, y2, r2, g2, b2);
    uint64_t vertex2 = pack_vertex(x3, y3, r3, g3, b3);

    // Command layout: 8-byte command word + 3 x 8-byte vertices = 32 bytes (4 SDRAM beats)
    uint8_t args[31];
    memset(args, 0, 7);             // Pad command word (opcode is in byte 0 of send_command)
    memcpy(&args[7],  &vertex0, 8); // Vertex 1
    memcpy(&args[15], &vertex1, 8); // Vertex 2
    memcpy(&args[23], &vertex2, 8); // Vertex 3

    send_command(0x03, args, 32);
}

// Draw an 8x8 1-bit sprite at (x, y) with the given color.
// The texture is a 64-bit bitmask: bit N set = pixel N is drawn.
// Command layout: opcode + position/color packed in first beat, bitmap in second beat.
void draw_sprite(int x, int y, int r, int g, int b, uint64_t *texture) {
    uint64_t vertex = ((uint64_t)(x & 0x1FF))
                    | ((uint64_t)(y & 0xFF) << 9)
                    | ((uint64_t)(r & 0x1F) << 17)
                    | ((uint64_t)(g & 0x3F) << 22)
                    | ((uint64_t)(b & 0x1F) << 28);

    uint8_t args[15];
    memset(args, 0, 15);
    memcpy(&args[0], &vertex, 7);   // Position + color (packed above opcode in beat 0)
    memcpy(&args[7], texture, 8);   // 8x8 bitmap
    send_command(0x04, args, 16);   // 2 SDRAM beats
}