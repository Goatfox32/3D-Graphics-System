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
	input logic write_en, // flag to allow data to be written
	input logic [X_WIDTH-1:0] write_x, // x position of pixel
	input logic [Y_WIDTH-1:0] write_y, // y position of pixel
	input logic [PIXEL_SIZE-1:0] write_data, // data being written into frame buffer from rasterzier
	input logic [X_WIDTH-1:0] read_x,
	input logic [Y_WIDTH-1:0] read_y,
	output logic [PIXEL_SIZE-1:0] read_data, // store pixel data
	output logic busy
);
	logic busy_r1, busy_r2; // Used for clock synchronization and edge detection
	logic s1_w1, s1_w2, s1_w2_d; // Used for clock synchronization and edge detection
	logic clear_req;

	
	logic [PIXEL_SIZE-1:0] mem [0:SIZE-1]; // Memory array that stores pixel data
   logic [ADDR_W-1:0] write_addr, read_addr, clear_addr, next_clear_addr; // Write Address, Read Address, and Clear Address
	
	enum logic [0:0] { CLEAR, ON } state, next_state;
	
	assign busy = (state == CLEAR); // Busy is set high whenever CLEAR is on
	
	initial begin
		state = ON;
      clear_addr = '0;
      read_data = '0;
		busy_r1 = 1'b0;
      busy_r2 = 1'b0;
		s1_w1 = 1'b1;
		s1_w2 = 1'b1;
		s1_w2_d = 1'b1;
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
					next_state = ON; // turn the frame buffer back on
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
			end
				
			default: begin
				next_state = ON;
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
	
	// ---- BUSY SYNCHRONIZATION ----
	always_ff @(posedge read_clk) begin
		busy_r1 <= busy; // first stage
		busy_r2 <= busy_r1; // second stage to ensure stability
	end
	
	always_ff @(posedge read_clk) begin
	
		if (busy_r2) begin
			read_data <= '0;
		end
		
		else begin // STATE = ON
			if ((read_x < FB_WIDTH) && (read_y < FB_HEIGHT))
				read_data <= mem[read_addr]; // pull pixel data from memory address and store it
			else
				read_data <= '0;
		end
	end
	
	always_ff @(posedge write_clk) begin
		state <= next_state;
		
		if (state == CLEAR) begin // if state is set to "CLEAR" then cycle through memory
			mem[clear_addr] <= '0;
			clear_addr <= next_clear_addr;
		end
		
		else begin // STATE = ON
			clear_addr <= '0;

			if (write_en && (write_x < FB_WIDTH) && (write_y < FB_HEIGHT))
				mem[write_addr] <= write_data; // write data to address
		end
	end
		
	
endmodule