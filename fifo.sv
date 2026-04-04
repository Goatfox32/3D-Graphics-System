// Ai-Generated
// Simple FIFO implementation in SystemVerilog

module fifo (
    input  logic         clk,
    input  logic         reset_n,

    input  logic [63:0] data_in,
    input  logic        write_en,
    output logic [63:0] data_out,
    input  logic        read_en,
    output logic        empty,
    output logic [4:0]  count,
    output logic        full
);

    logic [63:0] fifo_mem [0:15];
    logic [3:0]  head, tail;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            head <= 4'b0000;
            tail <= 4'b0000;
            count <= 5'b00000;
            data_out <= 64'b0;
        end else begin
            if (write_en && !full && read_en && !empty) begin
                fifo_mem[tail] <= data_in;
                tail <= tail + 1;
                data_out <= fifo_mem[head];
                head <= head + 1;
                // Count unchanged
            end else if (write_en && !full) begin
                fifo_mem[tail] <= data_in;
                tail <= tail + 1;
                count <= count + 1;
            end else if (read_en && !empty) begin
                head <= head + 1;
                count <= count - 1;
            end
        end
    end
    
    assign data_out = fifo_mem[head];

    assign empty = (count == 0);
    assign full = (count == 16);

endmodule