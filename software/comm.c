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

static volatile uint32_t *lw, *sdr;
static volatile uint8_t *data;

static volatile uint32_t *map_physical(int fd, off_t base, size_t size) {
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    if (p == MAP_FAILED) { perror("mmap"); exit(1); }
    return (volatile uint32_t *)p;
}

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

    // --- temporary bridge sanity test ---
    printf("status at rest:        0x%02x\n", lw[GPU_STATUS] & 0xFF);

    lw[GPU_CONTROL] = 0x1;
    printf("after control=1:       0x%02x\n", lw[GPU_STATUS] & 0xFF);

    lw[GPU_CONTROL] = 0x0;
    printf("after control=0:       0x%02x\n", lw[GPU_STATUS] & 0xFF);
    // --- end test ---
}

void send_command(uint8_t cmd, uint8_t *arg, int command_len) {
    
    while (lw[GPU_STATUS] & 0x01) { }

    data[0] = (uint32_t)cmd;
    for (int i = 0; i < command_len-1; i++) {
        data[i+1] = (uint32_t)arg[i];
    }

    lw[GPU_CONTROL] = STOP;
    usleep(100);

    lw[CMD_ADDR] = (BUFFER_BASE >> 3);
    lw[CMD_SIZE] = command_len;

    lw[GPU_CONTROL] = START;
    usleep(100);
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

void draw_triangle(int x1, int y1, int r1, int g1, int b1,
                   int x2, int y2, int r2, int g2, int b2,
                   int x3, int y3, int r3, int g3, int b3) {

    uint64_t vertex0 = pack_vertex(x1, y1, r1, g1, b1);
    
    uint64_t vertex1 = pack_vertex(x2, y2, r2, g2, b2);
    
    uint64_t vertex2 = pack_vertex(x3, y3, r3, g3, b3);
    
    uint8_t args[31];
    memset(args, 0, 7);
    memcpy(&args[7], &vertex0, 8);
    memcpy(&args[15], &vertex1, 8);
    memcpy(&args[23], &vertex2, 8);

    send_command(0x03, args, 32);
}

void draw_sprite(int x, int y, int r, int g, int b, uint64_t *texture) {
    uint64_t vertex = ((uint64_t)(x & 0x1FF))
                    | ((uint64_t)(y & 0xFF) << 9)
                    | ((uint64_t)(r & 0x1F) << 17)
                    | ((uint64_t)(g & 0x3F) << 22)
                    | ((uint64_t)(b & 0x1F) << 28);

    uint8_t args[15];
    memset(args, 0, 15);
    memcpy(&args[0], &vertex, 7);
    memcpy(&args[7], texture, 8);
    send_command(0x04, args, 16);
}