// Braden Vanderwoerd
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// comm.h — Public API for HPS-to-GPU communication.
// Provides init, raw command send, status read, and high-level draw commands.

#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Initialize memory-mapped I/O (must be called before any other comm function)
void init_comm();

// Low-level: write a raw command packet to SDRAM and trigger the GPU
void send_command(uint8_t cmd, uint8_t *arg, int command_len);

// Read the GPU status register (bit 0 = busy)
uint8_t read_status();

// --- High-level GPU commands

// Clear the back buffer (fills with black)
void clear();

// Swap front and back buffers (present the rendered frame)
void present_frame();

// Draw a filled triangle. Per-vertex colors are accepted for all three vertices,
// but the hardware currently only uses v1's color (flat shading).
void draw_triangle(int x1, int y1, int r1, int g1, int b1,
                   int x2, int y2, int r2, int g2, int b2,
                   int x3, int y3, int r3, int g3, int b3);

// Draw an 8x8 1-bit sprite at (x,y) with the given color and bitmap texture
void draw_sprite(int x, int y, int r, int g, int b, uint64_t *texture);