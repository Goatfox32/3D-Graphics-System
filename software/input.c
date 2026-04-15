// Braden Vanderwoerd
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// input.c — Non-blocking stdin helpers using termios + select.
// Provides raw terminal mode for immediate keypress detection during demos.

#define _POSIX_C_SOURCE 200112L

#include "input.h"

#include <stdio.h>
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>

static struct termios saved_termios; // Backup of original terminal settings
static int raw_active = 0;          // Guard to prevent double-enable

// Switch terminal to raw mode: no line buffering, no echo.
// This allows demos to detect keypresses immediately without waiting for Enter.
void input_raw_mode_enable(void) {
    if (raw_active) return;
    tcgetattr(STDIN_FILENO, &saved_termios);
    struct termios t = saved_termios;
    t.c_lflag &= ~(ICANON | ECHO); // Disable canonical mode and echo
    t.c_cc[VMIN]  = 0;             // Non-blocking: read() returns immediately
    t.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &t);
    raw_active = 1;
}

void input_raw_mode_disable(void) {
    if (!raw_active) return;
    tcsetattr(STDIN_FILENO, TCSANOW, &saved_termios);
    raw_active = 0;
}

// Non-blocking check: returns 1 if a key is waiting in stdin, 0 otherwise.
// Uses select() with zero timeout for instant polling.
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