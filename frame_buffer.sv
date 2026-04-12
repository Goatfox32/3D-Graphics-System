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
	logic s1_w1, s1_w2, s1_w2_d; // Used for clock synchronization and edge detection
	logic clear_req;

	logic [PIXEL_SIZE-1:0] mem_A_q, mem_B_q;
	logic oob_r;
	
	logic [PIXEL_SIZE-1:0] mem_A [0:SIZE-1]; // Memory array that stores pixel data
	logic [PIXEL_SIZE-1:0] mem_B [0:SIZE-1]; // Memory array that stores pixel data
   logic [ADDR_W-1:0] write_addr, read_addr, clear_addr, next_clear_addr; // Write Address, Read Address, and Clear Address
	
	// synchronized display buffer select for read_clk domain
	logic display_sel_w;
	logic display_sel_r1, display_sel_r2;
	
	logic frame_swap_d;
	logic frame_swap_r1, frame_swap_r2;
	logic frame_window_rd; // frame swap window
	logic frame_swap;
	
	logic frame_ready_pending;
	
	enum logic [1:0] { CLEAR, ON, OUTPUT_A, OUTPUT_B } state, next_state, last_state;
	
	assign busy = (state == CLEAR); // Busy is set high whenever CLEAR is on
	
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
	
	// ---- BUTTON SYNCHRONIZATION + PULSE CONTROL & CLEAR SIGNAL ----
	always_ff @(posedge write_clk) begin
		s1_w1 <= s1 & (~hps_clear);
		s1_w2 <= s1_w1;
		s1_w2_d <= s1_w2;
	end
	
	assign clear_req = s1_w2_d & ~s1_w2; 
	
	
	// ---- FRAME SWAP SYNCHRONIZATION + PULSE CONTROL ----
	always_ff @(posedge write_clk) begin
		frame_swap_r1 <= frame_window_rd;
		frame_swap_r2 <= frame_swap_r1;
		frame_swap_d <= frame_swap_r2;
	end
	
	assign frame_swap = ~frame_swap_d & frame_swap_r2;
	
	logic [X_WIDTH-1:0] read_x_r;
	logic [Y_WIDTH-1:0] read_y_r;
	logic [ADDR_W-1:0] read_addr_r;
	
	always_ff @(posedge read_clk) begin
		read_x_r <= read_x;
		read_y_r <= read_y;
		read_addr_r <= read_addr;
		
		oob_r <= ~((read_x_r < FB_WIDTH) && (read_y_r < FB_HEIGHT)); //out of bounds -> ready
		frame_window_rd <= ((v_counter > 480) && (v_counter <= 490)); // 10 cycle window to latch frame_swap
		
		// synchronize which buffer is currently being displayed
		display_sel_r1 <= display_sel_w;
		display_sel_r2 <= display_sel_r1; // The read clock's version of the write clocks state machine
		
		if (display_sel_r2 == '0) begin // OUTPUT_A
			mem_A_q <= mem_A[read_addr_r];                  // pure RAM read
			read_data <= (oob_r) ? '0 : mem_A_q;            // separate output mux
		end
		else begin // OUTPUT_B
			mem_B_q <= mem_B[read_addr_r];                  // pure RAM read
			read_data <= (oob_r) ? '0 : mem_B_q;            // separate output mux
		end
	end
	
	always_ff @(posedge write_clk) begin
		
		if (state == CLEAR || next_state == CLEAR)
			frame_ready_pending <= 1'b0;
		else if ((state == OUTPUT_A && next_state == OUTPUT_B) || (state == OUTPUT_B && next_state == OUTPUT_A))
			frame_ready_pending <= 1'b0;
		else if (frame_ready_in)
			frame_ready_pending <= 1'b1;
		
	
		if ((state == OUTPUT_A) && (next_state == CLEAR))
			last_state <= OUTPUT_A;
		if ((state == OUTPUT_B) && (next_state == CLEAR))
			last_state <= OUTPUT_B;
			
		if (next_state == OUTPUT_A)
			display_sel_w <= 1'b0;
		else if (next_state == OUTPUT_B)
			display_sel_w <= 1'b1;
			
		state <= next_state;
		
		if (state == CLEAR) begin // if state is set to "CLEAR" then cycle through memory
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

			if (write_en && (write_x < FB_WIDTH) && (write_y < FB_HEIGHT))
				mem_B[write_addr] <= write_data; // write data to address
		end
		else if (state == OUTPUT_B) begin
			clear_addr <= '0;

			if (write_en && (write_x < FB_WIDTH) && (write_y < FB_HEIGHT))
				mem_A[write_addr] <= write_data; // write data to address
		end
	end
		
	
endmodule