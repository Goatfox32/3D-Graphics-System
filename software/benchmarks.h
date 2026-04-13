// benchmarks.h
// Performance benchmarks for the GPU C library.

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