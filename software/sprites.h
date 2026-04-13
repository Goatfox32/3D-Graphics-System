#ifndef SPRITES_H
#define SPRITES_H

/*
 * 8x8 letter sprites, authored as ASCII art and packed into uint64_t at
 * runtime. Packing convention (matches the hardware expectation: LSB of
 * the 64-bit word is the top-left pixel):
 *   - Row 0 (top) occupies bits 0..7   (the lowest byte)
 *   - Row 7 (bot) occupies bits 56..63 (the highest byte)
 *   - Within each row, column 0 (left) is bit 0 of that byte
 *
 * Usage:
 *   #include "sprites.h"
 *   sprites_init();            // call once at startup
 *   uint64_t a = SPRITE('A');  // or SPRITE('a'), case-insensitive
 *
 * Note: this header defines `static` storage, so include it from exactly
 * one translation unit. If you need it in multiple .c files, split the
 * definitions into a sprites.c and leave only declarations here.
 */

#include <stdint.h>
#include <ctype.h>

/* ----- packing helper ----------------------------------------------------- */

static uint64_t make_sprite(const char *rows[8]) {
    uint64_t result = 0;
    for (int r = 0; r < 8; r++) {
        uint8_t byte = 0;
        for (int c = 0; c < 8; c++) {
            if (rows[r][c] == '\0') break;   /* tolerate short rows */
            if (rows[r][c] == '#') byte |= (uint8_t)(1u << c);
        }
        result |= ((uint64_t)byte) << (r * 8);
    }
    return result;
}

static const char *SMILEY[8] = {
    "..####..",
    ".#....#.",
    "#.#..#.#",
    "#......#",
    "#.#..#.#",
    "#..##..#",
    ".#....#.",
    "..####..",
};

static const char *SOLID[8] = {
    "########",
    "########",
    "########",
    "########",
    "########",
    "########",
    "########",
    "########",
};

static const char *DOT[8] = {
    "........",
    "........",
    "........",
    "........",
    "........",
    "........",
    "...##...",
    "...##...",
};

/* ----- letter definitions ------------------------------------------------- *
 * Row 0 is the TOP row. '#' = lit pixel, anything else = blank.
 * Each row must be at least 8 characters (use '.' for blanks).
 */

static const char *CHAR_A[8] = {
    "..####..",
    ".#....#.",
    "#......#",
    "#......#",
    "########",
    "#......#",
    "#......#",
    "#......#",
};

static const char *CHAR_B[8] = {
    "#######.",
    "#......#",
    "#......#",
    "#######.",
    "#......#",
    "#......#",
    "#......#",
    "#######.",
};

static const char *CHAR_C[8] = {
    ".######.",
    "#......#",
    "#.......",
    "#.......",
    "#.......",
    "#.......",
    "#......#",
    ".######.",
};

static const char *CHAR_D[8] = {
    "#######.",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#######.",
};

static const char *CHAR_E[8] = {
    "########",
    "#.......",
    "#.......",
    "######..",
    "#.......",
    "#.......",
    "#.......",
    "########",
};

static const char *CHAR_F[8] = {
    "########",
    "#.......",
    "#.......",
    "######..",
    "#.......",
    "#.......",
    "#.......",
    "#.......",
};

static const char *CHAR_G[8] = {
    ".######.",
    "#......#",
    "#.......",
    "#.......",
    "#...####",
    "#......#",
    "#......#",
    ".######.",
};

static const char *CHAR_H[8] = {
    "#......#",
    "#......#",
    "#......#",
    "########",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
};

static const char *CHAR_I[8] = {
    ".######.",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    ".######.",
};

static const char *CHAR_J[8] = {
    "...#####",
    ".....#..",
    ".....#..",
    ".....#..",
    ".....#..",
    ".....#..",
    "#....#..",
    ".####...",
};

static const char *CHAR_K[8] = {
    "#.....#.",
    "#....#..",
    "#...#...",
    "#..#....",
    "####....",
    "#...#...",
    "#....#..",
    "#.....#.",
};

static const char *CHAR_L[8] = {
    "#.......",
    "#.......",
    "#.......",
    "#.......",
    "#.......",
    "#.......",
    "#.......",
    "########",
};

static const char *CHAR_M[8] = {
    "#......#",
    "##....##",
    "#.#..#.#",
    "#..##..#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
};

static const char *CHAR_N[8] = {
    "#......#",
    "##.....#",
    "#.#....#",
    "#..#...#",
    "#...#..#",
    "#....#.#",
    "#.....##",
    "#......#",
};

static const char *CHAR_O[8] = {
    ".######.",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    ".######.",
};

static const char *CHAR_P[8] = {
    "#######.",
    "#......#",
    "#......#",
    "#######.",
    "#.......",
    "#.......",
    "#.......",
    "#.......",
};

static const char *CHAR_Q[8] = {
    ".######.",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#...#..#",
    "#....#.#",
    ".#####.#",
};

static const char *CHAR_R[8] = {
    "#######.",
    "#......#",
    "#......#",
    "#######.",
    "#..#....",
    "#...#...",
    "#....#..",
    "#.....#.",
};

static const char *CHAR_S[8] = {
    ".######.",
    "#......#",
    "#.......",
    ".#......",
    "..####..",
    "......#.",
    "#......#",
    ".######.",
};

static const char *CHAR_T[8] = {
    "########",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
};

static const char *CHAR_U[8] = {
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    ".######.",
};

static const char *CHAR_V[8] = {
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    ".#....#.",
    "..#..#..",
    "...##...",
};

static const char *CHAR_W[8] = {
    "#......#",
    "#......#",
    "#......#",
    "#......#",
    "#..##..#",
    "#.#..#.#",
    "##....##",
    "#......#",
};

static const char *CHAR_X[8] = {
    "#......#",
    ".#....#.",
    "..#..#..",
    "...##...",
    "...##...",
    "..#..#..",
    ".#....#.",
    "#......#",
};

static const char *CHAR_Y[8] = {
    "#......#",
    ".#....#.",
    "..#..#..",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
};

static const char *CHAR_Z[8] = {
    "########",
    "......#.",
    ".....#..",
    "....#...",
    "...#....",
    "..#.....",
    ".#......",
    "########",
};

/* ----- runtime table ------------------------------------------------------ */

static uint64_t sprite_table[26];

static void sprites_init(void) {
    sprite_table[ 0] = make_sprite(CHAR_A);
    sprite_table[ 1] = make_sprite(CHAR_B);
    sprite_table[ 2] = make_sprite(CHAR_C);
    sprite_table[ 3] = make_sprite(CHAR_D);
    sprite_table[ 4] = make_sprite(CHAR_E);
    sprite_table[ 5] = make_sprite(CHAR_F);
    sprite_table[ 6] = make_sprite(CHAR_G);
    sprite_table[ 7] = make_sprite(CHAR_H);
    sprite_table[ 8] = make_sprite(CHAR_I);
    sprite_table[ 9] = make_sprite(CHAR_J);
    sprite_table[10] = make_sprite(CHAR_K);
    sprite_table[11] = make_sprite(CHAR_L);
    sprite_table[12] = make_sprite(CHAR_M);
    sprite_table[13] = make_sprite(CHAR_N);
    sprite_table[14] = make_sprite(CHAR_O);
    sprite_table[15] = make_sprite(CHAR_P);
    sprite_table[16] = make_sprite(CHAR_Q);
    sprite_table[17] = make_sprite(CHAR_R);
    sprite_table[18] = make_sprite(CHAR_S);
    sprite_table[19] = make_sprite(CHAR_T);
    sprite_table[20] = make_sprite(CHAR_U);
    sprite_table[21] = make_sprite(CHAR_V);
    sprite_table[22] = make_sprite(CHAR_W);
    sprite_table[23] = make_sprite(CHAR_X);
    sprite_table[24] = make_sprite(CHAR_Y);
    sprite_table[25] = make_sprite(CHAR_Z);
}

/* Access macro: case-insensitive, returns 0 for non-letters. */
#define SPRITE(c) \
    (isalpha((unsigned char)(c)) ? sprite_table[toupper((unsigned char)(c)) - 'A'] : (uint64_t)0)

#endif /* SPRITES_H */