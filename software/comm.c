// comm.c
// Communication module for the GPU project
// Braden Vanderwoerd - 2026-03-30

#include "comm.h"

#define LW_BRIDGE_BASE 0xFF200000
#define LW_BRIDGE_SIZE 0x1000
#define SDR_BASE       0xFFC25000
#define SDR_SIZE       0x1000
#define BUFFER_BASE    0x18000000
#define BUFFER_SIZE    0x10000

#define CMD_ADDR    (0x00 / 4)
#define CMD_SIZE    (0x10 / 4)
#define GPU_CONTROL (0x20 / 4)
#define GPU_STATUS  (0x30 / 4)

#define STOP  0x00000000
#define START 0x00000001

static volatile uint32_t *lw, *sdr;
static volatile uint8_t *data;

static volatile uint32_t *map_physical(int fd, off_t base, size_t size) {
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    if (p == MAP_FAILED) { perror("mmap"); exit(1); }
    return (volatile uint32_t *)p;
}

void init_comm() {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem"); exit(1); }

    lw   = map_physical(fd, LW_BRIDGE_BASE, LW_BRIDGE_SIZE);
    sdr  = map_physical(fd, SDR_BASE, SDR_SIZE);
    data = (volatile uint8_t*) map_physical(fd, BUFFER_BASE, BUFFER_SIZE);
}

void send_command(uint8_t cmd, uint8_t *arg, int command_len) {
    
    // ADD CHECK FOR command_reader BUSY

    data[0] = (uint32_t)cmd;
    for (int i = 0; i < command_len-1; i++) {
        data[i+1] = (uint32_t)arg[i];
    }

    lw[GPU_CONTROL] = STOP;
    usleep(100);

    lw[CMD_ADDR] = (BUFFER_BASE >> 3);
    lw[CMD_SIZE] = command_len;

    lw[GPU_CONTROL] = START;
    lw[GPU_CONTROL] = STOP;
}

uint8_t read_status() {
    return lw[GPU_STATUS];
}

void clear() {
    send_command(0x01, NULL, 1);
}

// Do NOT use (not implemented in command processor)
void draw_pixel(int x, int y, int r, int g, int b) {
    uint8_t args[3] = { (uint8_t)r, (uint8_t)g, (uint8_t)b };
    //send_command(0x02, args, 4);
}

void draw_triangle(int x1, int y1, int r1, int b1, int g1,
                   int x2, int y2, int r2, int b2, int g2,
                   int x3, int y3, int r3, int b3, int g3) {
                    
    uint64_t vertex0 = {(x1 & 0x1FF),
                        (y1 & 0xFF) << 9,
                        (r1 & 0x1F) << 17,
                        (g1 & 0x3F) << 22,
                        (b1 & 0x1F) << 28};
    uint64_t vertex1 = {(x2 & 0x1FF),
                        (y2 & 0xFF) << 9,
                        (r2 & 0x1F) << 17,
                        (g2 & 0x3F) << 22,
                        (b2 & 0x1F) << 28};
    uint64_t vertex2 = {(x3 & 0x1FF),
                        (y3 & 0xFF) << 9,
                        (r3 & 0x1F) << 17,
                        (g3 & 0x3F) << 22,
                        (b3 & 0x1F) << 28};
    
    uint8_t args[31];
    memset(args, 0, 7);
    memcpy(&args[7], &vertex0, 8);
    memcpy(&args[15], &vertex1, 8);
    memcpy(&args[23], &vertex2, 8);

    send_command(0x03, args, 32);
}