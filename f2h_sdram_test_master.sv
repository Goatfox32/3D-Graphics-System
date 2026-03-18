module f2h_sdram_test_master (
    input  logic        clk,
    input  logic        reset_n,

    // Trigger and address from existing PIOs
    input  logic        start,           // gpu_control[0]
    input  logic [31:0] read_addr,       // cmd_addr PIO value

    // Avalon-MM master port (connects to f2h_sdram0)
    output logic [31:0] avm_address,
    output logic        avm_read,
    output logic [7:0]  avm_burstcount,
    input  logic [63:0] avm_readdata,
    input  logic        avm_readdatavalid,
    input  logic        avm_waitrequest,

    // Result
    output logic [7:0]  result,          // low 8 bits of read data → gpu_status
    output logic        done             // gpu_status[1]
);

    typedef enum logic [2:0] {
        IDLE,
        READ_REQ,
        READ_WAIT,
        COMPLETE
    } state_t;

    state_t state;
    logic start_prev;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state          <= IDLE;
            avm_read       <= 1'b0;
            avm_address    <= '0;
            avm_burstcount <= 8'd1;
            result         <= 8'h00;
            done           <= 1'b0;
            start_prev     <= 1'b0;
        end else begin
            start_prev <= start;

            case (state)
                IDLE: begin
                    avm_read <= 1'b0;
                    // Trigger on rising edge of start
                    if (start && !start_prev) begin
                        avm_address    <= read_addr;
                        avm_burstcount <= 8'd1;
                        done           <= 1'b0;
                        state          <= READ_REQ;
                    end
                end

                READ_REQ: begin
                    avm_read <= 1'b1;
                    // Hold until waitrequest deasserts
                    if (!avm_waitrequest) begin
                        avm_read <= 1'b0;
                        state    <= READ_WAIT;
                    end
                end

                READ_WAIT: begin
                    // Variable latency — wait for readdatavalid
                    if (avm_readdatavalid) begin
                        result <= avm_readdata[7:0];
                        done   <= 1'b1;
                        state  <= COMPLETE;
                    end
                end

                COMPLETE: begin
                    // Stay here until start goes low (HPS clears control reg)
                    if (!start) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule