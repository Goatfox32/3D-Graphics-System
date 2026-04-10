#include <math.h>

#define W   320
#define H   240
#define GW  16
#define GH  16
#define HTW 10    /* half tile width (isometric) */
#define HTH 5     /* half tile height */
#define BH  6     /* block height in pixels */

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static int heightmap[GH][GW];

/* Layered sines as cheap terrain noise */
static float terrain_noise(float x, float z) {
    return sinf(x * 0.35f) * 2.5f
         + sinf(z * 0.28f) * 2.0f
         + sinf((x + z) * 0.2f) * 1.5f
         + sinf(x * 0.7f - z * 0.5f) * 1.0f;
}

static void gen_terrain(float ox, float oz) {
    for (int j = 0; j < GH; j++)
        for (int i = 0; i < GW; i++) {
            int h = (int)(terrain_noise(i + ox, j + oz) + 5.0f);
            if (h < 0) h = 0;
            if (h > 9) h = 9;
            heightmap[j][i] = h;
        }
}

#define WATER_LEVEL 3

typedef enum { BIOME_WATER, BIOME_SAND, BIOME_GRASS, BIOME_STONE, BIOME_SNOW } Biome;

static Biome get_biome(int h) {
    if (h <= WATER_LEVEL) return BIOME_WATER;
    if (h == 4)           return BIOME_SAND;
    if (h <= 7)           return BIOME_GRASS;
    if (h == 8)           return BIOME_STONE;
    return BIOME_SNOW;
}

/* top / left-face / right-face colors per biome (RGB565 ranges) */
static void biome_colors(Biome b,
        int *tr, int *tg, int *tb,
        int *lr, int *lg, int *lb,
        int *rr, int *rg, int *rb) {
    switch (b) {
    case BIOME_WATER:
        *tr=3;  *tg=18; *tb=28;  *lr=1;  *lg=10; *lb=20;  *rr=2;  *rg=14; *rb=24; break;
    case BIOME_SAND:
        *tr=28; *tg=56; *tb=10;  *lr=22; *lg=42; *lb=6;   *rr=25; *rg=48; *rb=8;  break;
    case BIOME_GRASS:
        *tr=5;  *tg=52; *tb=5;   *lr=10; *lg=26; *lb=3;   *rr=7;  *rg=20; *rb=2;  break;
    case BIOME_STONE:
        *tr=14; *tg=30; *tb=14;  *lr=8;  *lg=18; *lb=8;   *rr=10; *rg=22; *rb=10; break;
    case BIOME_SNOW:
        *tr=29; *tg=60; *tb=29;  *lr=18; *lg=38; *lb=18;  *rr=22; *rg=46; *rb=22; break;
    }
}

static void draw_block(int cx, int cy,
        int tr, int tg, int tb,
        int lr, int lg, int lb,
        int rr, int rg, int rb) {
    /* Isometric diamond corners */
    int nx = cx,       ny = cy - HTH;   /* north */
    int ex = cx + HTW, ey = cy;         /* east  */
    int sx = cx,       sy = cy + HTH;   /* south */
    int wx = cx - HTW, wy = cy;         /* west  */

    /* Left face (SW): quad W-S-S+BH-W+BH */
    draw_triangle(wx, wy,      lr, lg, lb,
                  sx, sy,      lr, lg, lb,
                  sx, sy + BH, lr, lg, lb);
    draw_triangle(wx, wy,      lr, lg, lb,
                  sx, sy + BH, lr, lg, lb,
                  wx, wy + BH, lr, lg, lb);

    /* Right face (SE): quad S-E-E+BH-S+BH */
    draw_triangle(sx, sy,      rr, rg, rb,
                  ex, ey,      rr, rg, rb,
                  ex, ey + BH, rr, rg, rb);
    draw_triangle(sx, sy,      rr, rg, rb,
                  ex, ey + BH, rr, rg, rb,
                  sx, sy + BH, rr, rg, rb);

    /* Top face: two triangles N-E-S, N-S-W */
    draw_triangle(nx, ny, tr, tg, tb,
                  ex, ey, tr, tg, tb,
                  sx, sy, tr, tg, tb);
    draw_triangle(nx, ny, tr, tg, tb,
                  sx, sy, tr, tg, tb,
                  wx, wy, tr, tg, tb);
}

/*
int main(void) {
    int frame = 0;

    while (1) {
        clear();

        // Slowly scroll the terrain like flying over it
        float t = frame * 0.04f;
        gen_terrain(t, t * 0.6f);

        int origin_x = W / 2;
        int origin_y = 30;

        // Painter's algorithm: back to front (low j/i first)
        for (int j = 0; j < GH; j++) {
            for (int i = 0; i < GW; i++) {
                int h = heightmap[j][i];
                Biome b = get_biome(h);

                // Water sits flat at WATER_LEVEL
                int draw_h = (b == BIOME_WATER) ? WATER_LEVEL : h;

                int cx = origin_x + (i - j) * HTW;
                int cy = origin_y + (i + j) * HTH - draw_h * BH;

                int tr, tg, tb, lr, lg, lb, rr, rg, rb;
                biome_colors(b, &tr,&tg,&tb, &lr,&lg,&lb, &rr,&rg,&rb);

                draw_block(cx, cy, tr,tg,tb, lr,lg,lb, rr,rg,rb);
            }
        }

        frame++;
        usleep(50000);
    }
    return 0;
}*/