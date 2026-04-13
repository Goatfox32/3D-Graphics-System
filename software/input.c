// input.c
// Non-blocking stdin helpers using termios + select.

#define _POSIX_C_SOURCE 200112L

#include "input.h"

#include <stdio.h>
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>

static struct termios saved_termios;
static int raw_active = 0;

void input_raw_mode_enable(void) {
    if (raw_active) return;
    tcgetattr(STDIN_FILENO, &saved_termios);
    struct termios t = saved_termios;
    // ~ICANON: deliver bytes immediately, don't wait for Enter
    // ~ECHO:   don't print the keys the user types
    t.c_lflag &= ~(ICANON | ECHO);
    t.c_cc[VMIN]  = 0;  // read() returns immediately
    t.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &t);
    raw_active = 1;
}

void input_raw_mode_disable(void) {
    if (!raw_active) return;
    tcsetattr(STDIN_FILENO, TCSANOW, &saved_termios);
    raw_active = 0;
}

int key_pressed(void) {
    fd_set rfds;
    struct timeval tv = {0, 0};
    FD_ZERO(&rfds);
    FD_SET(STDIN_FILENO, &rfds);
    return select(STDIN_FILENO + 1, &rfds, NULL, NULL, &tv) > 0;
}

int read_key(void) {
    unsigned char c;
    ssize_t n = read(STDIN_FILENO, &c, 1);
    return n == 1 ? (int)c : -1;
}

void input_run_until_key(void (*fn)(void)) {
    input_raw_mode_enable();
    while (!key_pressed()) {
        fn();
    }
    // drain whatever key(s) the user pressed so they don't leak into the menu
    while (read_key() != -1) { }
    input_raw_mode_disable();
}