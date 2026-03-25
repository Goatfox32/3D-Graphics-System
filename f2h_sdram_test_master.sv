module f2h_sdram_test_master (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        start,
    input  logic [28:0] read_addr,
    input  logic [7:0]  read_size,

    output logic [28:0] avm_address,
    output logic        avm_read,
    output logic [7:0]  avm_burstcount,
    input  logic [63:0] avm_readdata,
    input  logic        avm_readdatavalid,
    input  logic        avm_waitrequest,

    output logic [7:0]  result,
    output logic        done
);
    
    enum logic [1:0] { IDLE, WAIT_REQ, READ_DATA, EXTRA_BEATS} 
                 state, next_state;

    logic [28:0] next_address;
    logic        next_read;
    logic [7:0]  next_burst;

    logic        next_done;
    logic [7:0]  next_result;

    logic [7:0]  beats_remaining;
    logic [7:0]  next_beats_rem;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            avm_address     <= '0;
            avm_read        <= 1'b0;
            avm_burstcount  <= '0;

            done            <= 1'b0;
            result          <= '0;

            beats_remaining <= '0;

            state           <= IDLE;
        end
        else begin
            avm_address     <= next_address;
            avm_read        <= next_read;
            avm_burstcount  <= next_burst;

            done            <= next_done;
            result          <= next_result;

            beats_remaining <= next_beats_rem;

            state           <= next_state;
        end
    end

    always_comb begin
        
        next_address   = avm_address;
        next_read      = avm_read;
        next_burst     = avm_burstcount;

        next_done      = done;
        next_result    = result;

        next_beats_rem = beats_remaining;

        next_state     = state;

        case (state)
            IDLE: begin
                if (start) begin
                    next_address    = read_addr;
                    next_read       = 1'b1;
                    next_burst      = (read_size + 8'h7) >> 3;

                    next_done       = 1'b0;     // Could reset result here as well

                    next_beats_rem  = (read_size + 8'h7) >> 3;

                    next_state      = WAIT_REQ;
                end
            end

            WAIT_REQ: begin
                if (!avm_waitrequest) begin
                    next_read  = 1'b0;
                    next_state = READ_DATA;
                end
            end

            READ_DATA: begin
                if (avm_readdatavalid) begin
                    next_result    = avm_readdata[7:0];

                    next_beats_rem = beats_remaining - 1'b1;
                    next_state     = EXTRA_BEATS;
                end
            end

            EXTRA_BEATS: begin
                if (beats_remaining == 8'd0) begin
                    next_state = IDLE;
                    next_done  = 1'b1;
                end
                else if (avm_readdatavalid) begin
                    next_beats_rem = beats_remaining - 8'd1;
                end
            end

            default: ;

        endcase
    end

endmodule
