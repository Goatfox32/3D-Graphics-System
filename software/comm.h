// comm.h
// Communication module for the GPU project
// Braden Vanderwoerd - 2026-03-30

#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void init_comm();
void send_command(uint8_t cmd, uint8_t *arg, int command_len);
uint8_t read_status();

void clear();
void draw_pixel(int x, int y, int r, int g, int b);
void draw_triangle(int x1, int y1, int r1, int b1, int g1,
                   int x2, int y2, int r2, int b2, int g2,
                   int x3, int y3, int r3, int b3, int g3);
void draw_sprite(int x, int y, int r, int g, int b, uint8_t *texture);