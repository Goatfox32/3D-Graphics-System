// Jacob Edwards & Braden Vanderwoerd
// 2026-04-13
// Documented by Claude Opus 4.6 - 2026-04-14
// Frame Buffer Module
// Dual-buffered 320x240 frame buffer with 6-bit color (2 bits per channel).
// Operates across two clock domains: write_clk (system 50 MHz) for rasterizer writes
// and clear operations, read_clk (25 MHz VGA pixel clock) for display reads.
// Ping-pong buffering: while one buffer is displayed, the other receives new draws.
// Frame swaps are synchronized to the vertical blanking interval to prevent tearing.

module frame_buffer #(
   parameter H_SYNC_MAX = 800, // 640 visble pixel timings, 16 front porch timings, 96 H-Sync timings, and 48 back porch timings
   parameter V_SYNC_MAX = 525, // 480 visble line timings, 10 front porch timingss, 2 V-Sync timings, and 33 back porch timings
   parameter int FB_WIDTH  = 320, // Frame buffer width
   parameter int FB_HEIGHT = 240, // Frame buffer height
   parameter int PIXEL_SIZE = 6, //Bits per pixel
   parameter int SIZE = FB_WIDTH * FB_HEIGHT,
   parameter int ADDR_W = $clog2(SIZE), // Address width
   parameter int X_WIDTH = $clog2(FB_WIDTH), // Bits per X-coord
   parameter int Y_WIDTH = $clog2(FB_HEIGHT) // Bits per Y-coord
)(
	input logic read_clk,
	input logic write_clk,
	input logic hps_clear,
	input logic s1,
	input logic [$clog2(V_SYNC_MAX)-1:0] v_counter,
	input logic write_en, // flag to allow data to be written
	input logic [X_WIDTH-1:0] write_x, // x position of pixel
	input logic [Y_WIDTH-1:0] write_y, // y position of pixel
	input logic [PIXEL_SIZE-1:0] write_data, // data being written into frame buffer from rasterzier
	input logic [X_WIDTH-1:0] read_x,
	input logic [Y_WIDTH-1:0] read_y,
	input logic frame_ready_in,
	output logic [PIXEL_SIZE-1:0] read_data, // store pixel data
	output logic busy
);
	logic s1_w1, s1_w2, s1_w2_d; // 3-stage synchronizer for reset button (s1) into write_clk domain
	logic clear_req;             // Pulse generated on falling edge of synchronized s1

	logic [PIXEL_SIZE-1:0] mem_A_q, mem_B_q; // Registered RAM outputs (one cycle latency)
	logic oob_r;                              // Registered out-of-bounds flag for read coordinates
	
	logic [PIXEL_SIZE-1:0] mem_A [0:SIZE-1]; // Pixel storage for buffer A (76,800 entries)
	logic [PIXEL_SIZE-1:0] mem_B [0:SIZE-1]; // Pixel storage for buffer B (76,800 entries)
   logic [ADDR_W-1:0] write_addr, read_addr, clear_addr, next_clear_addr;

	// --- Display buffer select, synchronized from write_clk to read_clk domain
	logic display_sel_w;               // Write-domain: which buffer is being displayed (0=A, 1=B)
	logic display_sel_r1, display_sel_r2; // Two-stage synchronizer into read_clk domain
	
	// --- Frame swap synchronization
	logic frame_swap_d;
	logic frame_swap_r1, frame_swap_r2;   // Synchronizer for swap window signal into write_clk
	logic frame_window_rd;                // High during vertical blanking window (v_counter 481-490)
	logic frame_swap;                     // Pulse: rising edge of synchronized frame_window_rd

	logic frame_ready_pending; // Latched when software requests a swap; consumed on actual swap
	
	// --- FSM States
	// CLEAR    : zeroing the back buffer one address per cycle
	// ON       : transient state after reset, immediately transitions to OUTPUT_A or handles clear
	// OUTPUT_A : displaying buffer A, writing to buffer B
	// OUTPUT_B : displaying buffer B, writing to buffer A
	enum logic [1:0] { CLEAR, ON, OUTPUT_A, OUTPUT_B } state, next_state, last_state;

	assign busy = (state == CLEAR); // Stalls the command pipeline during clear sweeps
	
	initial begin
		state = CLEAR;
		last_state = OUTPUT_A;
      clear_addr = '0;
      read_data = '0;
		s1_w1 = 1'b1;
		s1_w2 = 1'b1;
		s1_w2_d = 1'b1;
		display_sel_w  = 1'b0; // start displaying frame A
		display_sel_r1 = 1'b0;
		display_sel_r2 = 1'b0;
		frame_swap_r1 = 1'b0;
		frame_swap_r2 = 1'b0;
		frame_swap_d = 1'b0;
		frame_window_rd = 1'b0;
		mem_A_q = '0;
		mem_B_q = '0;
		read_addr_r = '0;
		frame_ready_pending = '0;
   end
	 
	always_comb begin
		// ---- defaults values ----
		next_state = state;
		next_clear_addr = clear_addr;
		
		read_addr = FB_WIDTH * read_y + read_x;
		write_addr = FB_WIDTH * write_y + write_x;
		
		case (state)
			// ---- CLEAR LOGIC ----
			CLEAR: begin
				
				if (clear_addr == (SIZE-1)) begin // if clear_addr has finished a full cycle through memory
					next_state = last_state; // turn the frame buffer back on
					next_clear_addr = '0;
				end 
				else begin
					next_clear_addr = clear_addr + 1'b1;
				end
			end
			
			// ---- FRAME BUFFER LOGIC ----
			ON: begin
				if (clear_req)
					next_state = CLEAR;
					
				else
					next_state = OUTPUT_A;
			end
			
			OUTPUT_A: begin
				if (clear_req)
					next_state = CLEAR;
				else if (frame_swap && frame_ready_pending)
					next_state = OUTPUT_B;
				
			end
			
			OUTPUT_B: begin
				if (clear_req)
					next_state = CLEAR;
				else if (frame_swap && frame_ready_pending)
					next_state = OUTPUT_A;
			end
				
			default: begin
				next_state = OUTPUT_A;
				next_clear_addr = '0;
			end
		endcase
	end
	
	// ---- BUTTON / HPS CLEAR SYNCHRONIZATION ----
	// Synchronize (s1 AND NOT hps_clear) into the write_clk domain;
	// a falling edge produces a one-cycle clear_req pulse.
	always_ff @(posedge write_clk) begin
		s1_w1   <= s1 & (~hps_clear);
		s1_w2   <= s1_w1;
		s1_w2_d <= s1_w2;
	end

	assign clear_req = s1_w2_d & ~s1_w2; // Falling-edge detect
	
	
	// ---- FRAME SWAP SYNCHRONIZATION ----
	// Synchronize the VGA blanking window signal into write_clk and detect its rising edge.
	// The swap only occurs if frame_ready_pending is also set (software issued PRESENT_FRAME).
	always_ff @(posedge write_clk) begin
		frame_swap_r1 <= frame_window_rd;
		frame_swap_r2 <= frame_swap_r1;
		frame_swap_d  <= frame_swap_r2;
	end

	assign frame_swap = ~frame_swap_d & frame_swap_r2; // Rising-edge detect
	
	logic [X_WIDTH-1:0] read_x_r;
	logic [Y_WIDTH-1:0] read_y_r;
	logic [ADDR_W-1:0] read_addr_r;
	
	// ---- READ CLOCK DOMAIN (25 MHz VGA pixel clock) ----
	always_ff @(posedge read_clk) begin
		// Pipeline stage 1: register inputs
		read_x_r    <= read_x;
		read_y_r    <= read_y;
		read_addr_r <= read_addr;

		// Pipeline stage 2: bounds check and VGA blanking window
		oob_r           <= ~((read_x_r < FB_WIDTH) && (read_y_r < FB_HEIGHT));
		frame_window_rd <= ((v_counter > 480) && (v_counter <= 490)); // 10-line window in vertical blanking

		// Synchronize display buffer select from write_clk domain
		display_sel_r1 <= display_sel_w;
		display_sel_r2 <= display_sel_r1;

		// Pipeline stage 3: RAM read + output mux (2-cycle read latency total)
		if (display_sel_r2 == '0) begin // Displaying buffer A
			mem_A_q   <= mem_A[read_addr_r];
			read_data <= (oob_r) ? '0 : mem_A_q;
		end
		else begin // Displaying buffer B
			mem_B_q   <= mem_B[read_addr_r];
			read_data <= (oob_r) ? '0 : mem_B_q;
		end
	end
	
	// ---- WRITE CLOCK DOMAIN (50 MHz system clock) ----
	always_ff @(posedge write_clk) begin

		// --- Frame-ready latch: set by software (PRESENT_FRAME), cleared on swap or clear
		if (state == CLEAR || next_state == CLEAR)
			frame_ready_pending <= 1'b0;
		else if ((state == OUTPUT_A && next_state == OUTPUT_B) || (state == OUTPUT_B && next_state == OUTPUT_A))
			frame_ready_pending <= 1'b0; // Consumed on actual swap
		else if (frame_ready_in)
			frame_ready_pending <= 1'b1;

		// --- Remember which buffer was active before a clear, so we return to it after
		if ((state == OUTPUT_A) && (next_state == CLEAR))
			last_state <= OUTPUT_A;
		if ((state == OUTPUT_B) && (next_state == CLEAR))
			last_state <= OUTPUT_B;

		// --- Update display select for read_clk synchronizer
		if (next_state == OUTPUT_A)
			display_sel_w <= 1'b0;
		else if (next_state == OUTPUT_B)
			display_sel_w <= 1'b1;

		state <= next_state;

		// --- Memory operations
		if (state == CLEAR) begin
			// Zero the back buffer one address per cycle
			if (last_state == OUTPUT_A) begin
				mem_B[clear_addr] <= '0;
				clear_addr <= next_clear_addr;
			end
			else if (last_state == OUTPUT_B) begin
				mem_A[clear_addr] <= '0;
				clear_addr <= next_clear_addr;
			end
		end
		else if (state == OUTPUT_A) begin
			clear_addr <= '0;
			// Displaying A -> rasterizer writes to B
			if (write_en && (write_x < FB_WIDTH) && (write_y < FB_HEIGHT))
				mem_B[write_addr] <= write_data;
		end
		else if (state == OUTPUT_B) begin
			clear_addr <= '0;
			// Displaying B -> rasterizer writes to A
			if (write_en && (write_x < FB_WIDTH) && (write_y < FB_HEIGHT))
				mem_A[write_addr] <= write_data;
		end
	end
		
	
endmodule