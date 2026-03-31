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

static volatile uint32_t *lw, *sdr, *data;

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
    data = map_physical(fd, BUFFER_BASE, BUFFER_SIZE);
}

void send_command(uint32_t cmd, uint32_t arg) {
    data[0] = cmd;          
    data[1] = arg;

    lw[GPU_CONTROL] = STOP;
    usleep(100);

    lw[CMD_ADDR] = (BUFFER_BASE >> 3);
    lw[CMD_SIZE] = 8;

    lw[GPU_CONTROL] = START;
    lw[GPU_CONTROL] = STOP;
}

uint8_t read_status() {
    return lw[GPU_STATUS] & 0x7F;
}