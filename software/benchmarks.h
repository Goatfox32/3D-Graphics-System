// Braden Vanderwoerd
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// benchmarks.h — Performance benchmark function declarations.
// See benchmarks.c for methodology (throughput vs. latency tests).

#ifndef BENCHMARKS_H
#define BENCHMARKS_H

void bench_all(void);

void bench_clear(int n);
void bench_triangle_small(int n);
void bench_triangle_large(int n);
void bench_triangle_fullscreen(int n);
void bench_sprite(int n);
void bench_latency(int n);

#endif