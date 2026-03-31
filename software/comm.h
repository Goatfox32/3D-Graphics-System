// comm.h
// Communication module for the GPU project
// Braden Vanderwoerd - 2026-03-30

#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
// #include <string.h>

void init_comm();
void send_command(uint32_t cmd, uint32_t arg);
uint8_t read_status();