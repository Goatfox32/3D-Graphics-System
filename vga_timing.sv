module vga_timing #(
	parameter H_SYNC_MAX = 800, // 640 visble pixel timings, 16 front porch timings, 96 H-Sync timings, and 48 back porch timings
	parameter V_SYNC_MAX = 525, // 480 visble line timings, 10 front porch timingss, 2 V-Sync timings, and 33 back porch timings
	parameter FRAMERATE = 60,
	parameter DIVIDER = 2
)
(
	input logic clk50,
	input logic s1,
	output logic clk_div,
	output logic [7:0] GPIO_0,
	output logic [$clog2(H_SYNC_MAX)-1:0] h_counter, // H counter size large enoguh for H resolution
   output logic [$clog2(V_SYNC_MAX)-1:0] v_counter // V counter size large enough for V resolution
);

  // Counter large enough for DIVIDER
  logic [$clog2(DIVIDER)-1:0] clk_count;

  
  // --- Clock Divider ---
  always_ff @(posedge clk50) begin
	 if (clk_count == DIVIDER/2 - 1) begin // Period is split in half, one half represents 1, the other represents 0
		clk_count <= '0;
		clk_div   <= ~clk_div;
	 end else begin
		clk_count <= clk_count + 1'b1;
	 end
  end
  
  logic h_pulse;
  logic v_pulse;
  
  	logic [1:0] red; // 1 bit for now
	logic [1:0] green; // 1 bit for now
	logic [1:0] blue; // 1 bit for now
  
	always_ff @(posedge clk_div) begin
    if (~s1) begin
        h_counter <= '0;
        v_counter <= '0;
        h_pulse   <= 1'b0;
        v_pulse   <= 1'b0;
    end
	 
    else begin
	 
		  // ----- H Sync -----
        h_counter <= h_counter + 1'b1;

        if ((h_counter >= 656) && (h_counter < 752))
            h_pulse <= 1'b1;
        else
            h_pulse <= 1'b0;
				
		  // ----- V Sync -----

        if (h_counter == H_SYNC_MAX - 1) begin
            h_counter <= '0;
            v_counter <= v_counter + 1'b1;
        end

        if ((v_counter >= 490) && (v_counter < 492))
            v_pulse <= 1'b1;
        else
            v_pulse <= 1'b0;

        if (v_counter == V_SYNC_MAX - 1)
            v_counter <= '0;
    end
	end
		
	assign GPIO_0[0] = h_pulse;
	assign GPIO_0[1] = v_pulse;
	assign GPI0_0[2] = red[0];
	assign GPI0_0[3] = red[1];
	assign GPI0_0[4] = green[0];
	assign GPI0_0[5] = green[1];
	assign GPI0_0[6] = blue[0];
	assign GPI0_0[7] = blue[1];
	
endmodule