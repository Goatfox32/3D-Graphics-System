// Braden Vanderwoerd
// 2026-04-06
// Command Executer Module
// This module executes commands read by the Command Reader, interfacing with the rasterizer and vertex processor as needed.
// It reads commands and data from the FIFOs and sends appropriate signals to the rasterizer and vertex processor.

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

    input  logic         rast_ready,
    output logic         rast_clear,
    output logic [63:0]  rast_set_pixel,
    output logic         vertex_valid,
    output logic [191:0] vertex_data,
    output logic         sprite_valid,
    output logic [127:0] sprite_data
);

    localparam NOP           = 8'h00,
               CLEAR         = 8'h01,
               DRAW_PIXEL    = 8'h02,
               DRAW_TRIANGLE = 8'h03,
               DRAW_SPRITE   = 8'h04;

    logic next_rast_clear;
    logic [63:0] next_rast_set_pixel;

    logic next_vertex_valid;
    logic [191:0] next_vertex_data;

    logic next_sprite_valid;
    logic [127:0] next_sprite_data;

    logic [2:0] beats_remaining, next_beats_remaining;

    enum logic [2:0] { IDLE, READ_COMMAND, CLEAR_COMMAND, DRAW_TRIANGLE_COMMAND, DRAW_SPRITE_COMMAND } state, next_state;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            rast_clear        <= 1'b0;
            rast_set_pixel    <= '0;

            vertex_valid      <= 1'b0;
            vertex_data       <= '0;

            sprite_valid      <= 1'b0;
            sprite_data       <= '0;

            beats_remaining <= 3'b0;

            state <= IDLE;
        end
        else begin
            rast_clear        <= next_rast_clear;
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

        next_rast_clear         = 1'b0;
        next_rast_set_pixel     = rast_set_pixel;

        next_vertex_valid       = 1'b0;
        next_vertex_data        = vertex_data;

        next_sprite_valid       = 1'b0;
        next_sprite_data        = sprite_data;

        next_beats_remaining = beats_remaining;

        next_state              = state;

        case (state)
            IDLE: begin
                if (!command_buffer_empty) begin
                    next_state = READ_COMMAND;
                end
            end

            READ_COMMAND: begin
                command_buffer_en = 1'b1;
                case (command_buffer_data[7:0])
                    NOP: begin
                        next_state = IDLE;
                    end

                    CLEAR: begin
                        next_state = CLEAR_COMMAND;
                    end

                    DRAW_PIXEL: begin
                        next_state = IDLE;
                    end

                    DRAW_TRIANGLE: begin
                        next_beats_remaining = 3'd3;
                        next_state = DRAW_TRIANGLE_COMMAND;
                    end

                    DRAW_SPRITE: begin
                        next_beats_remaining = 3'd2;
                        next_state = DRAW_SPRITE_COMMAND;
                    end

                    default: begin
                        next_state = IDLE; // Unknown command, ignore
                    end
                endcase
            end

            CLEAR_COMMAND: begin
                if (rast_ready) begin
                    next_rast_clear = 1'b1;
                    next_state = IDLE;
                end
            end

            DRAW_TRIANGLE_COMMAND: begin
                if (beats_remaining == 0) begin
                    if (rast_ready) begin
                        next_vertex_valid = 1'b1;
                        next_state = IDLE;
                    end
                end
                else if (!data_buffer_empty) begin
                    data_buffer_en = 1'b1;
                    next_vertex_data[(3-beats_remaining)*64 +: 64] = data_buffer_data;
                    next_beats_remaining = beats_remaining - 1;
                end
            end

            DRAW_SPRITE_COMMAND: begin
                if (beats_remaining == 0) begin
                    if (rast_ready) begin
                        next_sprite_valid = 1'b1;
                        next_state = IDLE;
                    end
                end
                else if (!data_buffer_empty) begin
                    data_buffer_en = 1'b1;
                    next_sprite_data[(2-beats_remaining)*64 +: 64] = data_buffer_data;
                    next_beats_remaining = beats_remaining - 1;
                end
            end

            default: next_state = IDLE;
        endcase

    end

endmodule