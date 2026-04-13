// main.c
// Interactive launcher. Top-level: demos + playground + benchmarks + quit.
// Each sub-menu is its own loop; "b" returns to the parent, "q" quits.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "comm.h"
#include "benchmarks.h"
#include "playground.h"
#include "demos.h"

// ---- shared menu plumbing -----------------------------------------------

typedef struct {
    const char *key;
    const char *desc;
    void (*fn)(void);
} menu_item;

// Read a line, trim newline, return pointer to internal buffer or NULL on EOF.
static char *prompt(const char *p) {
    static char line[64];
    printf("%s", p);
    fflush(stdout);
    if (!fgets(line, sizeof line, stdin)) return NULL;
    line[strcspn(line, "\r\n")] = '\0';
    return line;
}

// Print a menu, read a key, dispatch. Returns when user picks back/quit.
// `back_key` is the key that exits this menu ("q" at top level, "b" in subs).
// Returns 1 if the user wants to fully quit, 0 if just backing out.
static int run_menu(const char *title, menu_item *items, const char *back_key, const char *back_label) {
    while (1) {
        printf("\n=== %s ===\n", title);
        for (menu_item *m = items; m->key; m++) {
            printf("  %-4s  %s\n", m->key, m->desc);
        }
        printf("  %-4s  %s\n", back_key, back_label);

        char *line = prompt("> ");
        if (!line) return 1;                       // EOF -> quit
        if (line[0] == '\0') continue;
        if (strcmp(line, "q") == 0) return 1;      // quit always works
        if (strcmp(line, back_key) == 0) return 0; // back out

        int handled = 0;
        for (menu_item *m = items; m->key; m++) {
            if (strcmp(line, m->key) == 0) {
                m->fn();
                handled = 1;
                break;
            }
        }
        if (!handled) printf("unknown command: %s\n", line);
    }
}

// ---- benchmark wrappers --------------------------------------------------

static void m_bench_all(void)        { bench_all(); }
static void m_bench_clear(void)      { bench_clear(1000); }
static void m_bench_tri_small(void)  { bench_triangle_small(10000); }
static void m_bench_tri_large(void)  { bench_triangle_large(2000); }
static void m_bench_tri_full(void)   { bench_triangle_fullscreen(200); }
static void m_bench_sprite(void)     { bench_sprite(5000); }
static void m_bench_latency(void)    { bench_latency(1000); }

static menu_item benchmark_items[] = {
    { "a",  "run all benchmarks",        m_bench_all       },
    { "1",  "clear throughput",          m_bench_clear     },
    { "2",  "triangle (small, 16px)",    m_bench_tri_small },
    { "3",  "triangle (large, 128px)",   m_bench_tri_large },
    { "4",  "triangle (fullscreen)",     m_bench_tri_full  },
    { "5",  "sprite throughput",         m_bench_sprite    },
    { "6",  "command latency",           m_bench_latency   },
    { NULL, NULL, NULL }
};

static int benchmarks_menu(void) {
    return run_menu("Benchmarks", benchmark_items, "b", "back");
}

// ---- top-level wrappers --------------------------------------------------

static void m_clear_present(void) { clear(); present_frame(); printf("cleared.\n"); }
static void m_playground(void)    { playground(); }
static void m_benchmarks(void)    { benchmarks_menu(); }

// Demo stubs — replace with real demos as they're written.
static void m_demo1(void) { demo_full(); }
static void m_demo2(void) { demo_spinning_cube(); }
static void m_demo3(void) { demo_dvd_bounce(); }
static void m_demo4(void) { demo_game_of_life(); }

static menu_item top_items[] = {
    { "1", "full demo",            m_demo1         },
    { "2", "spinning cube",     m_demo2         },
    { "3", "DVD logo",            m_demo3         },
    { "4", "game of life",            m_demo4         },
    { "5", "benchmarks ->",  m_benchmarks    },
    { "p", "playground",     m_playground    },
    { "c", "clear + present", m_clear_present},
    { NULL, NULL, NULL }
};

// ---- main ----------------------------------------------------------------

int main(void) {
    init_comm();
    srand((unsigned)time(NULL));
    run_menu("GPU Test Suite", top_items, "q", "quit");
    return 0;
}