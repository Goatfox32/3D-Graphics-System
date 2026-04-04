
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
    output logic         vertex_valid,
    output logic [191:0] vertex_data,
    output logic         clear,
    output logic [63:0]  set_pixel
);

    localparam NOP = 8'h00,
               CLEAR = 8'h01,
               DRAW_PIXEL = 8'h02,
               DRAW_TRIANGLE = 8'h03;

    logic next_command_buffer_en;
    logic next_data_buffer_en;

    logic next_vertex_valid;
    logic [191:0] next_vertex_data;

    logic next_clear;
    logic [63:0] next_set_pixel;

    logic [2:0] vertices_remaining, next_vertices_remaining;

    enum logic [2:0] { IDLE, READ_COMMAND, CLEAR_COMMAND, DRAW_TRIANGLE_COMMAND } state, next_state;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            command_buffer_en <= 1'b0;
            data_buffer_en    <= 1'b0;
            vertex_valid      <= 1'b0;
            vertex_data       <= '0;
            clear             <= 1'b0;
            set_pixel         <= '0;

            vertices_remaining <= 3'b0;

            state <= IDLE;
        end
        else begin
            command_buffer_en <= next_command_buffer_en;
            data_buffer_en    <= next_data_buffer_en;
            vertex_valid      <= next_vertex_valid;
            vertex_data       <= next_vertex_data;
            clear             <= next_clear;
            set_pixel         <= next_set_pixel;

            vertices_remaining <= next_vertices_remaining;

            state <= next_state;
        end
    end

    always_comb begin
        next_command_buffer_en = 1'b0;
        next_data_buffer_en    = 1'b0;
        next_vertex_valid      = 1'b0;
        next_vertex_data       = vertex_data;
        next_clear             = 1'b0;
        next_set_pixel         = set_pixel;

        next_vertices_remaining   = vertices_remaining;

        next_state             = state;

        case (state)
            IDLE: begin
                if (!command_buffer_empty) begin
                    next_state = READ_COMMAND;
                end
            end

            READ_COMMAND: begin
                next_command_buffer_en = 1'b1;
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
                        next_vertices_remaining = 3'd3;
                        next_state = DRAW_TRIANGLE_COMMAND;
                    end

                    default: begin
                        next_state = IDLE; // Unknown command, ignore
                    end
                endcase
            end

            CLEAR_COMMAND: begin
                if (rast_ready) begin
                    next_clear = 1'b1;
                    next_state = IDLE;
                end
            end

            DRAW_TRIANGLE_COMMAND: begin
                if (vertices_remaining == 0) begin
                    if (rast_ready) begin
                        next_vertex_valid = 1'b1;
                        next_state = IDLE;
                    end
                end
                else if (!data_buffer_empty) begin
                    next_data_buffer_en = 1'b1;
                    next_vertex_data[(vertices_remaining-1)*64 +: 64] = data_buffer_data;
                    next_vertices_remaining = vertices_remaining - 1;
                end
            end
        endcase

    end

endmodule