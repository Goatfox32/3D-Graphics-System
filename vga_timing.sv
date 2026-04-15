// Jacob Edwards & Braden Vanderwoerd
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// VGA Timing Controller
// Generates 640x480 @ 60 Hz VGA timing from a 50 MHz input clock.
// A clock divider produces a 25 MHz pixel clock (clk_div). Horizontal and vertical
// counters drive sync pulses and a visible-area flag. The 640x480 output is mapped
// to the 320x240 frame buffer by halving the pixel coordinates (>> 1).
// Active pixel data is output on GPIO_0[7:0] as 6-bit RGB with active-low syncs.

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

  logic [$clog2(DIVIDER)-1:0] clk_count; // Divider toggle counter

  // --- Clock Divider: 50 MHz -> 25 MHz (DIVIDER=2) ---
  // Toggles clk_div every DIVIDER/2 input cycles to produce a 50% duty-cycle output
  always_ff @(posedge clk50) begin
		if (clk_count == DIVIDER/2 - 1) begin
			clk_count <= '0;
			clk_div   <= ~clk_div;
		end else begin
			clk_count <= clk_count + 1'b1;
		end
	end
  
	logic h_pulse, h_pulse_r; // Horizontal sync pulse and its registered version
	logic v_pulse, v_pulse_r; // Vertical sync pulse and its registered version
	logic visible, visible_r; // Active display area flag (combinational and registered)
  
  
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
			// Register sync/visible signals (one pixel delay for clean output)
			h_pulse_r <= h_pulse;
			v_pulse_r <= v_pulse;
			visible_r <= visible;

			// ----- Horizontal Sync (active during pixels 656-751) -----
			if ((h_counter >= 656) && (h_counter < 752))
				h_pulse <= 1'b1;
			else
				h_pulse <= 1'b0;

			// ----- Horizontal/Vertical Counter Advancement -----
			if (h_counter == H_SYNC_MAX - 1) begin
				h_counter <= '0;              // End of line: reset H, advance V
				v_counter <= v_counter + 1'b1;
			end else begin
				h_counter <= h_counter + 1'b1;
			end

			// ----- Vertical Sync (active during lines 490-491) -----
			if ((v_counter >= 490) && (v_counter < 492))
				v_pulse <= 1'b1;
			else
				v_pulse <= 1'b0;

			if (v_counter == V_SYNC_MAX - 1)
				v_counter <= '0; // End of frame: reset V
		end
	end
	
	// Visible area: first 640 pixels of each of the first 480 lines
	assign visible = (h_counter < 640) && (v_counter < 480);

	// Map 640x480 VGA coordinates to 320x240 frame buffer by dividing by 2
	assign read_x = visible ? (h_counter >> 1) : '0;
	assign read_y = visible ? (v_counter >> 1) : '0;

	// --- GPIO output to VGA DAC (active-low syncs, active-high RGB during visible)
	assign GPIO_0[0] = ~h_pulse_r; // HSYNC (active low)
	assign GPIO_0[1] = ~v_pulse_r; // VSYNC (active low)
	assign GPIO_0[2] = visible_r ? pixel_in[4] : 1'b0; // R[1] (high bit)
	assign GPIO_0[3] = visible_r ? pixel_in[5] : 1'b0; // R[0] (low bit)
	assign GPIO_0[4] = visible_r ? pixel_in[2] : 1'b0; // G[1] (high bit)
	assign GPIO_0[5] = visible_r ? pixel_in[3] : 1'b0; // G[0] (low bit)
	assign GPIO_0[6] = visible_r ? pixel_in[0] : 1'b0; // B[1] (high bit)
	assign GPIO_0[7] = visible_r ? pixel_in[1] : 1'b0; // B[0] (low bit)
	
endmodule