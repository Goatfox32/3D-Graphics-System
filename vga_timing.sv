module vga_timing #(
	parameter H_SYNC_MAX = 800, // 640 visble pixel timings, 16 front porch timings, 96 H-Sync timings, and 48 back porch timings
	parameter V_SYNC_MAX = 525, // 480 visble line timings, 10 front porch timingss, 2 V-Sync timings, and 33 back porch timings
	parameter FRAMERATE = 60,
	parameter DIVIDER = 2
)
(
	input logic clk50,
	input logic s1,
	input logic [5:0] pixel_in,
	output logic clk_div,
	output logic [7:0] GPIO_0,
	output logic [$clog2(H_SYNC_MAX)-1:0] h_counter, // H counter size large enoguh for H resolution
   output logic [$clog2(V_SYNC_MAX)-1:0] v_counter, // V counter size large enough for V resolution
	output logic [8:0] read_x,
   output logic [7:0] read_y
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
  
	logic h_pulse, h_pulse_r;
	logic v_pulse, v_pulse_r;
	logic visible, visible_r;
  
  
	always_ff @(posedge clk_div) begin
		if (~s1) begin
			h_counter <= '0;
			v_counter <= '0;
			h_pulse   <= 0;
			v_pulse   <= 0;
			h_pulse_r <= 0;
			v_pulse_r <= 0;
			visible_r <= 0;
		end
		
		else begin
			
			h_pulse_r <= h_pulse;
			v_pulse_r <= v_pulse;
			visible_r <= visible;

			// ----- H Sync -----

			if ((h_counter >= 656) && (h_counter < 752))
				h_pulse <= 1'b1;
			else
				h_pulse <= 1'b0;
					
			// ----- V Sync -----

			if (h_counter == H_SYNC_MAX - 1) begin
				h_counter <= '0;
				v_counter <= v_counter + 1'b1;
			end else begin
				h_counter <= h_counter + 1'b1;
			end

			if ((v_counter >= 490) && (v_counter < 492))
				v_pulse <= 1'b1;
			else
				v_pulse <= 1'b0;

			if (v_counter == V_SYNC_MAX - 1)
				v_counter <= '0;
		end
	end
	
	assign visible = (h_counter < 640) && (v_counter < 480);
	
	assign read_x = visible ? (h_counter >> 1) : '0;
	assign read_y = visible ? (v_counter >> 1) : '0;

	assign GPIO_0[0] = ~h_pulse_r; // HSYNC active low
	assign GPIO_0[1] = ~v_pulse_r; // VSYNC active low

	assign GPIO_0[2] = visible_r ? pixel_in[4] : 1'b0; // R high bit
	assign GPIO_0[3] = visible_r ? pixel_in[5] : 1'b0; // R low bit
	assign GPIO_0[4] = visible_r ? pixel_in[2] : 1'b0; // G high bit
	assign GPIO_0[5] = visible_r ? pixel_in[3] : 1'b0; // G low bit
	assign GPIO_0[6] = visible_r ? pixel_in[0] : 1'b0; // B high bit
	assign GPIO_0[7] = visible_r ? pixel_in[1] : 1'b0; // B low bit
	
endmodule