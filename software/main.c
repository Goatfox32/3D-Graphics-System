

#include <stdint.h>
#include <stdio.h>
#include "comm.h"

int main() {
    init_comm();

    // Example usage: send a command to the GPU
    send_command(0xAA, 0x12345678);

    // Read status back from the GPU
    uint8_t status = read_status();
    printf("GPU Status: 0x%02X\n", status);

    return 0;
}
