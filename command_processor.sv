

module command_processor (
    input  logic         clk,
    input  logic         reset_n,

    input  logic [31:0]  read_addr,
    input  logic [31:0]  read_size,
    output logic [7:0]   status,
    input  logic [7:0]   control,

    output logic [28:0]  avm_address,
    output logic         avm_read,
    output logic [7:0]   avm_burstcount,
    input  logic [63:0]  avm_readdata,
    input  logic         avm_readdatavalid,
    input  logic         avm_waitrequest,

    input  logic         rast_enable,
    output logic         rast_clear,
    output logic         vertex_valid,
    output logic [191:0] vertex_data
);
    
    enum logic [2:0] { IDLE, WAIT_REQ, READ_COMMAND, DO_CLEAR_COMMAND, DO_TRIANGLE_COMMAND } 
                  state, next_state;

    logic         busy, next_busy, size_error, next_size_error;
    logic [1:0]   vertices_remaining, next_vertices_remaining;

    logic [28:0]  next_address;
    logic         next_read;
    logic [7:0]   next_burst;

    logic         next_rast_clear;
    logic [191:0] next_vertex_data;
    logic         next_vertex_valid;

    wire start = control[0];

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            busy            <= 1'b0;
            size_error      <= 1'b0;
            vertices_remaining <= 2'b00;
            
            avm_address     <= '0;
            avm_read        <= 1'b0;
            avm_burstcount  <= 8'h01;

            rast_clear      <= 1'b0;
            vertex_data     <= '0;
            vertex_valid    <= 1'b0;

            state           <= IDLE;
        end
        else begin
            busy            <= next_busy;
            size_error      <= next_size_error;
            vertices_remaining <= next_vertices_remaining;
            
            avm_address     <= next_address;
            avm_read        <= next_read;
            avm_burstcount  <= next_burst;

            rast_clear      <= next_rast_clear;
            vertex_data     <= next_vertex_data;
            vertex_valid    <= next_vertex_valid;

            state           <= next_state;
        end
    end
    
    always_comb begin
        
        next_busy      = busy;
        next_size_error = size_error;
        next_vertices_remaining = vertices_remaining;

        next_address   = avm_address;
        next_read      = avm_read;
        next_burst     = avm_burstcount;

        next_rast_clear = 1'b0;
        next_vertex_data = vertex_data;
        next_vertex_valid = 1'b0;

        next_state     = state;

        case (state)
            IDLE: begin
                next_busy = 1'b0;
                if (start) begin
                    next_busy = 1'b1;
                    next_size_error = 1'b0;

                    next_address    = read_addr[28:0];
                    next_read       = 1'b1;
                    next_burst      = (read_size < 8'd1) ? 8'd1 : (read_size + 8'h7) >> 3;

                    next_state      = WAIT_REQ;
                end
            end

            WAIT_REQ: begin
                if (!avm_waitrequest) begin
                    next_read  = 1'b0;
                    next_state = READ_COMMAND;
                end
            end

            READ_COMMAND: begin
                if (avm_readdatavalid) begin
                    case (avm_readdata[7:0])
                        8'h00: begin
                            next_state = IDLE;
                        end

                        8'h01: begin // Clear command
                            if (avm_burstcount != 8'h01) begin
                                next_size_error = 1'b1;
                                next_state = IDLE;
                            end
                            else begin
                                next_state = DO_CLEAR_COMMAND;
                            end
                        end

                        8'h02: begin // DRAW_PIXEL command (not implemented)
                            next_state = IDLE;
                        end

                        8'h03: begin // DRAW_TRIANGLE command
                            if (avm_burstcount != 8'h04) begin
                                next_size_error = 1'b1;
                                next_state = IDLE;
                            end
                            else begin
                                next_state = DO_TRIANGLE_COMMAND;
                                next_vertices_remaining = 2'd3;
                            end
                        end

                        default: begin
                            next_state = IDLE;
                        end
                    endcase
                end
            end

            DO_CLEAR_COMMAND: begin
                next_rast_clear = 1'b1;
                next_state = IDLE;
            end

            DO_TRIANGLE_COMMAND: begin
                if (vertices_remaining == 0) begin
                    next_vertex_valid = 1'b1;
                    next_state = IDLE;
                end
                else if (avm_readdatavalid) begin
                    next_vertices_remaining = vertices_remaining - 1;
                    next_vertex_data[(vertices_remaining-1)*64 +: 64] = avm_readdata;
                end
            end

            default: next_state = IDLE;

        endcase
    end

    assign status[0] = busy; // READY/BUSY
    assign status[1] = size_error; // SIZE_ERROR
    assign status[2] = vertex_valid; // VERTEX_VALID
    assign status[3] = (state == WAIT_REQ) & avm_waitrequest;  // stuck indicator
    assign status[4] = (vertex_data[7:0]   == 8'hAA);  // byte 0 of vertex 2
    assign status[5] = (vertex_data[71:64] == 8'hBB);  // byte 0 of vertex 1
    assign status[6] = (vertex_data[135:128] == 8'hCC); // byte 0 of vertex 0
    assign status[7] = (status[4] & status[5] & status[6]); // all correct

endmodule
