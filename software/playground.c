// playground.c
// Scratch space. Edit freely. The menu just calls playground().
//
// Three patterns you'll probably want, copy-paste whichever fits:
//
// 1. ONE-SHOT TEST — draw something, present, return immediately:
//
//        void playground(void) {
//            clear();
//            draw_triangle(50,50, 31,0,0,  150,50, 0,0,0,  100,150, 0,0,0);
//            present_frame();
//        }
//
// 2. ANIMATION LOOP — runs until you press a key:
//
//        static int frame = 0;
//        static void frame_body(void) {
//            clear();
//            int x = 50 + (frame % 200);
//            draw_triangle(x,50, 31,63,31,  x+30,50, 0,0,0,  x+15,80, 0,0,0);
//            present_frame();
//            frame++;
//        }
//        void playground(void) {
//            frame = 0;
//            input_run_until_key(frame_body);
//        }
//
// 3. INTERACTIVE — read keys yourself inside the loop:
//
//        void playground(void) {
//            int x = 100, y = 100;
//            input_raw_mode_enable();
//            while (1) {
//                int k = read_key();
//                if (k == 'q') break;
//                if (k == 'a') x -= 5;
//                if (k == 'd') x += 5;
//                if (k == 'w') y -= 5;
//                if (k == 's') y += 5;
//                clear();
//                draw_triangle(x,y, 0,63,0,  x+20,y, 0,0,0,  x+10,y+20, 0,0,0);
//                present_frame();
//            }
//            input_raw_mode_disable();
//        }

#include "playground.h"
#include "comm.h"
#include "config.h"
#include "input.h"
#include "sprites.h"

#include <stdio.h>

void playground(void) {//
    printf("playground: edit playground.c to put something here.\n");
    clear();
    // A red triangle so you can tell the playground ran.
    draw_triangle(SCREEN_W/2 - 30, SCREEN_H/2 - 20, R_MAX, 0, 0,
                  SCREEN_W/2 + 30, SCREEN_H/2 - 20, 0, 0, 0,
                  SCREEN_W/2,      SCREEN_H/2 + 30, 0, 0, 0);
    //uint64_t sprite = SMILEY_FACE;
    //draw_sprite(10, 10, 31, 0, 0, &sprite);
    present_frame();
}