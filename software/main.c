
#include <stdint.h>
#include <stdio.h>
#include "comm.h"
#include "sprites.h"

/*
int main() {

    init_comm();


    clear();
    draw_triangle(160,  10, 0,  0,  24,
                  20,  200, 0,  63,  0,
                  300, 200, 0,  0,  31);

    // usleep(3300000);

    // uint64_t smile = SMILEY_FACE;
    // draw_sprite(40, 10, 0, 0, 31, &smile);

    return 0;
} */

int main(void) {
    init_comm();
    clear();
    // Write extra bytes to data[] WITHOUT issuing another command.
    // Need to expose `data` from comm.c — either extern it, or move
    // this loop into a temporary helper inside comm.c.
    extern volatile uint8_t *data;
    for (int i = 1; i < 64; i++) data[i] = 0;
    return 0;
}