#include <stdint.h>

uint64_t SMILEY_FACE = 0x004242420081423C;

const char *smiley[8] = {
    "#.####..",
    ".#....#.",
    "#.#..#.#",
    "#......#",
    "#.#..#.#",
    "#..##..#",
    ".#....#.",
    "..####..",
};

uint64_t make_sprite(const char *rows[8]) {
    uint64_t result = 0;
    for (int r = 0; r < 8; r++) {
        uint8_t byte = 0;
        for (int c = 0; c < 8; c++) {
            if (rows[r][c] == '#')
                byte |= (1 << c);
        }
        result |= ((uint64_t)byte) << (r * 8);
    }
    return result;
}