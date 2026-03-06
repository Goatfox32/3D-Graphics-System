// Date: March 3rd, 2026
// Name: Jacob Edwards
// Student #: A01360840

module graphics_system (
    input  logic       write,
    input  logic [7:0] write_data,
    input  logic       clk50,
    output logic [7:0] leds
);

    logic [7:0] data_reg;

    always_ff @(posedge clk50) begin
        if (write)
            data_reg <= write_data;
    end

    assign leds = data_reg;

endmodule


module triangle_rasterizer #(
    parameter int H_RES = 320, // Horizontal Resolution
    parameter int V_RES = 240, // Vertical Resolution
    parameter int COL_W = 16,  // Color width (RGB 565)
    parameter int EW    = 24,  // Edge width
    parameter int ADD_W = 17,  // Address width for framebuffer
    parameter int VTEX  = 10   // Vertex data size
)(
    input  logic              clk,
    input  logic              reset,

    input  logic [EW-1:0]     edge1,
    input  logic [EW-1:0]     edge2,
    input  logic [EW-1:0]     edge3,

    input  logic [VTEX-1:0]   data
);

    // body

endmodule