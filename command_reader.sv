// Braden Vanderwoerd & Jacob Edwards
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// Command Reader Module
// Reads GPU commands from SDRAM via the Avalon-MM F2H master interface and distributes
// them into two FIFOs: a command FIFO (opcode only) and a data FIFO (vertex/sprite payloads).
// When busy is high, the module will not accept new commands and sets the status bit accordingly.

module command_reader (
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

    input  logic         command_buffer_full,
    output logic         command_buffer_en,
    output logic [63:0]  command_buffer_data,

    input  logic         data_buffer_full,
    input  logic [4:0]   data_buffer_count,
    output logic         data_buffer_en,
    output logic [63:0]  data_buffer_data
);

    // --- Command opcodes (match the software-side protocol in comm.c)
    localparam NOP           = 8'h00,
               CLEAR         = 8'h01,
               PRESENT_FRAME = 8'h02,
               DRAW_TRIANGLE = 8'h03,
               DRAW_SPRITE   = 8'h04;

    // --- SDRAM signals
    logic [28:0] next_address;
    logic        next_read;
    logic [7:0]  next_burst;

    // --- FIFO signals
    logic        next_command_buffer_en;
    logic [63:0] next_command_buffer_data;
    logic        next_data_buffer_en;
    logic [63:0] next_data_buffer_data;

    // --- Internal logical signals
    logic       busy, next_busy, size_error, next_size_error;
    logic [2:0] beats_remaining, next_beats_remaining;

    // --- FSM States
    // IDLE       : waiting for a start pulse from HPS
    // WAIT_REQ   : burst request issued, waiting for waitrequest to deassert
    // READ_COMMAND: first beat of burst arrives — decode the opcode
    // READ_DATA  : subsequent beats carry vertex/sprite payload into data FIFO
    // DRAIN_DATA : discard remaining beats for unrecognized or size-error commands
    enum logic [2:0] { IDLE, WAIT_REQ, READ_COMMAND, READ_DATA, DRAIN_DATA }
                  state, next_state;

    // --- Start Edge Detection
    logic start_r;
    always_ff @(posedge clk) begin
        if (!reset_n) start_r <= 1'b0;
        else          start_r <= control[0]; // Control bit 0 triggers start
    end
    wire start_pulse = control[0] & ~start_r;

    // --- Registered signals
    always_ff @(posedge clk) begin
        // --- Reset values
        if (!reset_n) begin
            avm_address    <= '0;
            avm_read       <= 1'b0;
            avm_burstcount <= 8'h01;

            command_buffer_en   <= 1'b0;
            command_buffer_data <= '0;
            data_buffer_en      <= 1'b0;
            data_buffer_data    <= '0;

            busy            <= 1'b0;
            size_error      <= 1'b0;
            beats_remaining <= '0;

            state <= IDLE;
        end
        else begin
            avm_address     <= next_address;
            avm_read        <= next_read;
            avm_burstcount  <= next_burst;

            command_buffer_en   <= next_command_buffer_en;
            command_buffer_data <= next_command_buffer_data;
            data_buffer_en      <= next_data_buffer_en;
            data_buffer_data    <= next_data_buffer_data;

            busy            <= next_busy;
            size_error      <= next_size_error;
            beats_remaining <= next_beats_remaining;

            state <= next_state;
        end
    end
    
    // --- FSM logic
    always_comb begin
        next_address   = avm_address;
        next_read      = avm_read;
        next_burst     = avm_burstcount;

        next_command_buffer_en    = 1'b0;
        next_command_buffer_data  = command_buffer_data;
        next_data_buffer_en   = 1'b0;
        next_data_buffer_data = data_buffer_data;

        next_busy            = busy;
        next_size_error      = size_error;
        next_beats_remaining = beats_remaining;

        next_state = state;

        case (state)
            IDLE: begin
                // Only accept new commands when FIFOs have room (13 entries leaves space for largest command)
                next_busy = (data_buffer_count < 5'd13) & !command_buffer_full ? 1'b0 : 1'b1;
                if (start_pulse & (data_buffer_count < 5'd13)) begin
                    next_address = read_addr[28:0];
                    next_read    = 1'b1;
                    next_burst   = (read_size < 8'd1) ? 8'd1 : (read_size + 8'h7) >> 3; // Ceiling division: bytes -> 8-byte beats

                    next_busy            = 1'b1;
                    next_size_error      = 1'b0;
                    next_beats_remaining = (read_size < 8'd1) ? 8'd0 : ((read_size + 8'h7) >> 3) - 1'b1; // Total beats minus the command beat

                    next_state = WAIT_REQ;
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
                    // First valid beat is always the command word; opcode is in the low byte
                    next_state = DRAIN_DATA; // Default: drain remaining beats for unknown/dataless commands
                    case (avm_readdata[7:0])
                        NOP: begin // NOP
                            
                        end

                        CLEAR: begin // CLEAR command
                            if (avm_burstcount != 8'h01) begin
                                next_size_error = 1'b1;
                            end
                            else begin
                                next_command_buffer_en   = 1'b1;
                                next_command_buffer_data = 64'h01;
                                next_state = READ_DATA;
                            end
                        end

                        PRESENT_FRAME: begin // Swap front/back buffers
                            if (avm_burstcount != 8'h01) begin
                                next_size_error = 1'b1;
                            end
                            else begin
                                next_command_buffer_en   = 1'b1;
                                next_command_buffer_data = 64'h02;
                                next_state = READ_DATA;
                            end
                        end

                        DRAW_TRIANGLE: begin // 4 beats: 1 command + 3 vertex data words
                            if (avm_burstcount != 8'h04) begin
                                next_size_error = 1'b1;
                            end
                            else begin
                                next_command_buffer_en   = 1'b1;
                                next_command_buffer_data = 64'h03;
                                next_state = READ_DATA;
                            end
                        end

                        DRAW_SPRITE: begin // 2 beats: command (with position/color) + bitmap
                            if (avm_burstcount != 8'h02) begin
                                next_size_error = 1'b1;
                            end
                            else begin
                                next_command_buffer_en   = 1'b1;
                                next_command_buffer_data = 64'h04;

                                // Sprite position/color is packed into the command word above the opcode
                                next_data_buffer_en   = 1'b1;
                                next_data_buffer_data = {8'h0, avm_readdata[63:8]};

                                next_state = READ_DATA;
                            end
                        end

                        default: begin
                            
                        end
                    endcase
                end
            end

            READ_DATA: begin
                // Forward each valid data beat into the data FIFO
                if (beats_remaining == 2'b00) begin
                    next_state = DRAIN_DATA;
                end
                else if (avm_readdatavalid) begin
                    next_data_buffer_en   = 1'b1;
                    next_data_buffer_data = avm_readdata;
                    next_beats_remaining = beats_remaining - 1;
                end
            end

            DRAIN_DATA: begin
                // Consume and discard any remaining burst beats before returning to IDLE
                if (beats_remaining == 2'b00) begin
                    next_busy = 1'b0;
                    next_state = IDLE;
                end
                else if (avm_readdatavalid) begin
                    next_beats_remaining = beats_remaining - 1;
                end
            end

            default: next_state = IDLE;

        endcase
    end

    // --- Status register (directly readable by HPS via PIO)
    assign status[0] = busy;                                    // Bit 0: BUSY flag (polled by software before issuing commands)
    assign status[1] = size_error;                              // Bit 1: SIZE_ERROR (burst size mismatch for command)
    assign status[2] = control[0];                              // Bit 2: echo of start bit (debug)
    assign status[3] = (state == WAIT_REQ) | avm_waitrequest;  // Bit 3: stall indicator (debug)
    assign status[7:4] = '0;

endmodule
