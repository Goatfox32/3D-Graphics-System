
#include <stdint.h>
#include <stdio.h>
#include "comm.h"
#include "sprites.h"
#include "demos.h"

int main() {

    init_comm();

    // Read status back from the GPU
    uint8_t status = read_status();
    printf("GPU Status: 0x%02X\n", status);

    //int exit = 0;
    //spinning_cube_demo(&exit);
    // draw_triangle(160,  10, 31,  0,  0,
    //               20,  200,  0, 63,  0,
    //               300, 200,  0,  0, 31);
    
    clear();
    int exit = 0;
    spinning_cube_demo(&exit);

    return 0;
}
