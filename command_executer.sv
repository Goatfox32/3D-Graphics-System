// Braden Vanderwoerd & Jacob Edwards
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// Command Executer Module
// Consumes opcodes from the command FIFO and assembles vertex/sprite data from the data FIFO.
// Dispatches clear, present, draw_triangle, and draw_sprite operations to the frame buffer
// and rasterizer. Waits for the rasterizer to be ready before issuing draw commands.

`default_nettype none

module command_executer (
    input  logic         clk,
    input  logic         reset_n,

    input  logic         command_buffer_empty,
    input  logic [63:0]  command_buffer_data,
    output logic         command_buffer_en,

    input  logic         data_buffer_empty,
    input  logic [63:0]  data_buffer_data,
    output logic         data_buffer_en,

    input  logic         fb_busy,
    output logic         fb_clear,
    output logic         fb_swap,

    input  logic         rast_ready,
    output logic [63:0]  rast_set_pixel, // Not implemented
    output logic         vertex_valid,
    output logic [191:0] vertex_data,
    output logic         sprite_valid,
    output logic [127:0] sprite_data
);

    // --- Command opcodes (must match command_reader.sv and software comm.c)
    localparam NOP           = 8'h00,
               CLEAR         = 8'h01,
               PRESENT_FRAME = 8'h02,
               DRAW_TRIANGLE = 8'h03,
               DRAW_SPRITE   = 8'h04;

    // --- Frame buffer control
    logic next_fb_clear;
    logic next_fb_swap;
    logic [63:0] next_rast_set_pixel; // Reserved for future pixel-level write (not implemented)

    // --- Rasterizer vertex interface
    logic next_vertex_valid;
    logic [191:0] next_vertex_data; // 3 vertices x 64 bits each

    // --- Rasterizer sprite interface
    logic next_sprite_valid;
    logic [127:0] next_sprite_data; // Position/color (64b) + 8x8 bitmap (64b)

    // --- Data beat counter (tracks remaining FIFO reads for multi-beat commands)
    logic [2:0] beats_remaining, next_beats_remaining;

    // --- FSM States
    enum logic [2:0] { IDLE, READ_COMMAND, CLEAR_COMMAND, PRESENT_FRAME_COMMAND,
                       DRAW_TRIANGLE_COMMAND, DRAW_SPRITE_COMMAND }
                       state, next_state;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            fb_clear        <= 1'b0;
            fb_swap         <= 1'b0;
            rast_set_pixel  <= '0;

            vertex_valid      <= 1'b0;
            vertex_data       <= '0;

            sprite_valid      <= 1'b0;
            sprite_data       <= '0;

            beats_remaining <= 3'b0;

            state <= IDLE;
        end
        else begin
            fb_clear        <= next_fb_clear;
            fb_swap         <= next_fb_swap;
            rast_set_pixel    <= next_rast_set_pixel;

            vertex_valid      <= next_vertex_valid;
            vertex_data       <= next_vertex_data;

            sprite_valid      <= next_sprite_valid;
            sprite_data       <= next_sprite_data;

            beats_remaining <= next_beats_remaining;

            state <= next_state;
        end
    end

    always_comb begin
        command_buffer_en = 1'b0;
        data_buffer_en    = 1'b0;

        next_fb_clear         = 1'b0;
        next_fb_swap          = 1'b0;
        next_rast_set_pixel     = rast_set_pixel;

        next_vertex_valid       = 1'b0;
        next_vertex_data        = vertex_data;

        next_sprite_valid       = 1'b0;
        next_sprite_data        = sprite_data;

        next_beats_remaining = beats_remaining;

        next_state              = state;

        case (state)
            IDLE: begin
                // Wait for a command to appear in the command FIFO
                if (!command_buffer_empty) begin
                    next_state = READ_COMMAND;
                end
            end

            READ_COMMAND: begin
                command_buffer_en = 1'b1; // Pop the opcode from the command FIFO
                case (command_buffer_data[7:0])
                    NOP: begin
                        next_state = IDLE;
                    end

                    CLEAR: begin
                        next_state = CLEAR_COMMAND;
                    end

                    PRESENT_FRAME: begin
                        next_state = PRESENT_FRAME_COMMAND;
                    end

                    DRAW_TRIANGLE: begin
                        next_beats_remaining = 3'd3; // 3 data beats: one per vertex
                        next_state = DRAW_TRIANGLE_COMMAND;
                    end

                    DRAW_SPRITE: begin
                        next_beats_remaining = 3'd2; // 2 data beats: position/color + bitmap
                        next_state = DRAW_SPRITE_COMMAND;
                    end

                    default: begin
                        next_state = IDLE; // Unknown command, ignore
                    end
                endcase
            end

            CLEAR_COMMAND: begin
                // Wait for frame buffer to finish any in-progress clear before issuing another
                if (!fb_busy) begin
                    next_fb_clear = 1'b1;
                    next_state = IDLE;
                end
            end

            PRESENT_FRAME_COMMAND: begin
                // Wait for frame buffer idle, then request a front/back buffer swap
                if (!fb_busy) begin
                    next_fb_swap = 1'b1;
                    next_state = IDLE;
                end
            end

            DRAW_TRIANGLE_COMMAND: begin
                // Accumulate 3 data beats into the 192-bit vertex_data register
                if (beats_remaining == 0) begin
                    // All vertex data assembled; wait for rasterizer to be free
                    if (rast_ready) begin
                        next_vertex_valid = 1'b1; // Pulse valid to hand off to rasterizer
                        next_state = IDLE;
                    end
                end
                else if (!data_buffer_empty) begin
                    data_buffer_en = 1'b1;
                    // Pack each 64-bit beat into the correct slice: v1=[63:0], v2=[127:64], v3=[191:128]
                    next_vertex_data[(3-beats_remaining)*64 +: 64] = data_buffer_data;
                    next_beats_remaining = beats_remaining - 1;
                end
            end

            DRAW_SPRITE_COMMAND: begin
                // Accumulate 2 data beats into the 128-bit sprite_data register
                if (beats_remaining == 0) begin
                    if (rast_ready) begin
                        next_sprite_valid = 1'b1;
                        next_state = IDLE;
                    end
                end
                else if (!data_buffer_empty) begin
                    data_buffer_en = 1'b1;
                    // Beat 0: position/color, Beat 1: 8x8 bitmap
                    next_sprite_data[(2-beats_remaining)*64 +: 64] = data_buffer_data;
                    next_beats_remaining = beats_remaining - 1;
                end
            end

            default: next_state = IDLE;
        endcase

    end

endmodule