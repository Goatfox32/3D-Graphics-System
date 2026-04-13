// Jacob Edwards & Braden Vanderwoerd
// 2026-04-10
// Rasterizer Module
// This module ...

module rasterizer #(
	parameter int FB_WIDTH = 320,
	parameter int FB_HEIGHT = 240,
	parameter int PIXEL_SIZE = 6,
	parameter int X_WIDTH = 9,
	parameter int Y_WIDTH = 8
)
(
	input  logic clk,
	input  logic s1,
	
	output logic rast_ready,

	input  logic [191:0] vertex_data,
    input  logic 		 vertex_valid,
	 		  
	input  logic [127:0] sprite_data,
	input  logic 		 sprite_valid,

	output logic 		 	      write_en,
	output logic [X_WIDTH-1:0]    write_x,
	output logic [Y_WIDTH-1:0]    write_y,
	output logic [PIXEL_SIZE-1:0] write_color,

	input  logic fb_busy
);
	// --- Utility functions
	function automatic [X_WIDTH-1:0] max3x
		( 
		input [X_WIDTH-1:0] a,
		input [X_WIDTH-1:0] b,
		input [X_WIDTH-1:0] c
		);
	
		begin
			max3x = (a >= b) ? ((a >= c) ? a : c)
							    : ((b >= c) ? b : c);
		end
	endfunction
	
	function automatic [X_WIDTH-1:0] min3x
		( 
		input [X_WIDTH-1:0] a,
		input [X_WIDTH-1:0] b,
		input [X_WIDTH-1:0] c
		);
	
		begin
			min3x = (a <= b) ? ((a <= c) ? a : c)
							    : ((b <= c) ? b : c);
		end
	endfunction
	
	function automatic [Y_WIDTH-1:0] max3y
		( 
		input [Y_WIDTH-1:0] a,
		input [Y_WIDTH-1:0] b,
		input [Y_WIDTH-1:0] c
		);
	
		begin
			max3y = (a >= b) ? ((a >= c) ? a : c)
							    : ((b >= c) ? b : c);
		end
	endfunction
	
	function automatic [Y_WIDTH-1:0] min3y
		( 
		input [Y_WIDTH-1:0] a,
		input [Y_WIDTH-1:0] b,
		input [Y_WIDTH-1:0] c
		);
	
		begin
			min3y = (a <= b) ? ((a <= c) ? a : c)
							    : ((b <= c) ? b : c);
		end
	endfunction

	localparam FRAC = 24;

	logic next_rast_ready;
	
	// --- Vertex and position registers
	logic [63:0] v1, v2, v3, next_v1, next_v2, next_v3;

	logic signed [31:0] sx1, sx2, sx3;
	logic signed [31:0] sy1, sy2, sy3;
	logic signed [31:0] sx_curr, sy_curr;

	// --- Bounding box registers
	logic [X_WIDTH-1:0] x_max, x_min, x_curr, next_x_curr;
	logic [Y_WIDTH-1:0] y_max, y_min, y_curr, next_y_curr;

	// --- Edge test calculations
	logic pixel_valid;

	logic signed [31:0] area;
	logic signed [31:0] area_n, next_area_n;

	logic signed [31:0] p1, q1, c1, p2, q2, c2, p3, q3, c3,
						next_p1, next_q1, next_c1, next_p2, next_q2, next_c2, next_p3, next_q3, next_c3;
	logic signed [31:0] e1_n, e2_n, e3_n, next_e1_n, next_e2_n, next_e3_n,
						e1_row, e2_row, e3_row, next_e1_row, next_e2_row, next_e3_row;

	logic signed [24:0] inv_area, next_inv_area;
	logic        [41:0] rcp_num, next_rcp_num;
	logic        [41:0] rcp_quot, next_rcp_quot;
	logic        [5:0]  rcp_bit, next_rcp_bit;

	// --- Color registers
	logic [4:0] r1, r2, r3, r_mix;
	logic [5:0] g1, g2, g3, g_mix;
	logic [4:0] b1, b2, b3, b_mix;
	logic [49:0] r_wide, g_wide, b_wide;

	logic [PIXEL_SIZE-1:0] mixed_color;

    enum logic [2:0] { IDLE, LOAD_TRIANGLE, CALC_RECIP, SCAN_TRIANGLE, LOAD_SPRITE, SCAN_SPRITE } state, next_state;

	logic next_write_en;
	logic [X_WIDTH-1:0] next_write_x;
	logic [Y_WIDTH-1:0] next_write_y;
	logic [PIXEL_SIZE-1:0] next_write_color;
	
	logic [127:0] sprite_reg, next_sprite_reg;
	logic [63:0] sprite_bits;

	logic [X_WIDTH-1:0] sprite_x, sprite_x_max;
	logic [Y_WIDTH-1:0] sprite_y, sprite_y_max;

	logic [X_WIDTH-1:0] sprite_dx_full;
	logic [Y_WIDTH-1:0] sprite_dy_full;
	logic [2:0] sprite_dx, sprite_dy;
	logic [5:0] sprite_idx;
	
	logic [15:0] sprite_color;
	logic [4:0] sprite_r;
	logic [5:0] sprite_g;
	logic [4:0] sprite_b;
	
	assign sprite_x = sprite_reg[8:0];
	assign sprite_y = sprite_reg[16:9];
	assign sprite_color = sprite_reg[32:17];
	assign sprite_bits = sprite_reg[127:64];

	assign sprite_x_max = sprite_x + 9'd7;
	assign sprite_y_max = sprite_y + 8'd7;

	assign sprite_dx_full = x_curr - sprite_x;
	assign sprite_dy_full = y_curr - sprite_y;

	assign sprite_dx = sprite_dx_full[2:0];
	assign sprite_dy = sprite_dy_full[2:0];
	assign sprite_idx = {sprite_dy, sprite_dx}; // row*8 + col
	
	assign sprite_r = sprite_color[4:0];
	assign sprite_g = sprite_color[10:5];
	assign sprite_b = sprite_color[15:11];

	// --- Sequential logic
	always_ff @(posedge clk) begin
		if (~s1) begin // Reset state
			v1 <= '0;
			v2 <= '0;
			v3 <= '0;

			area_n   <= '0;
			e1_n     <= '0;
			e2_n     <= '0;
			e3_n     <= '0;
			e1_row   <= '0;
			e2_row   <= '0;
			e3_row   <= '0;

			p1 <= '0;
			q1 <= '0;
			c1 <= '0;
			p2 <= '0;
			q2 <= '0;
			c2 <= '0;
			p3 <= '0;
			q3 <= '0;
			c3 <= '0;

			inv_area <= '0;
			rcp_num  <= '0;
			rcp_quot <= '0;
			rcp_bit  <= '0;

			x_curr <= x_min;
			y_curr <= y_min;
			sprite_reg <= '0;
			state <= IDLE;

			write_en <= 1'b0;
			write_x <= '0;
			write_y <= '0;
			write_color <= '0;

			rast_ready <= 1'b0;
			
		end else begin
			v1 <= next_v1;
			v2 <= next_v2;
			v3 <= next_v3;

			area_n <= next_area_n;
			e1_n   <= next_e1_n;
			e2_n   <= next_e2_n;
			e3_n   <= next_e3_n;
			e1_row <= next_e1_row;
			e2_row <= next_e2_row;
			e3_row <= next_e3_row;

			p1 <= next_p1;
			q1 <= next_q1;
			c1 <= next_c1;
			p2 <= next_p2;
			q2 <= next_q2;
			c2 <= next_c2;
			p3 <= next_p3;
			q3 <= next_q3;
			c3 <= next_c3;

			inv_area <= next_inv_area;
			rcp_num  <= next_rcp_num;
			rcp_quot <= next_rcp_quot;
			rcp_bit  <= next_rcp_bit;

			sprite_reg <= next_sprite_reg;
			
			x_curr <= next_x_curr;
			y_curr <= next_y_curr;
			state <= next_state;

			write_en <= next_write_en;
			write_x <= next_write_x;
			write_y <= next_write_y;
			write_color <= next_write_color;

			rast_ready <= next_rast_ready;
		end
	end

	// --- Combinational logic
	always_comb begin
		next_v1 = v1;
		next_v2 = v2;
		next_v3 = v3;

		pixel_valid = 1'b0;
		area = '0;
		next_area_n = '0;
		next_e1_n = e1_n;
		next_e2_n = e2_n;
		next_e3_n = e3_n;
		next_e1_row = e1_row;
		next_e2_row = e2_row;
		next_e3_row = e3_row;

		next_p1 = p1;  next_q1 = q1;  next_c1 = c1;
		next_p2 = p2;  next_q2 = q2;  next_c2 = c2;
		next_p3 = p3;  next_q3 = q3;  next_c3 = c3;

		next_inv_area = inv_area;
		next_rcp_num  = rcp_num;
		next_rcp_quot = rcp_quot;
		next_rcp_bit  = rcp_bit;

		next_x_curr = x_curr;
		next_y_curr = y_curr;
		next_state = state;
		next_sprite_reg = sprite_reg;
		next_rast_ready = 1'b0;

		r_mix = '0;
		g_mix = '0;
		b_mix = '0;
		r_wide = '0;
		g_wide = '0;
		b_wide = '0;
		mixed_color = '0;

        case (state)
            IDLE: begin
                next_rast_ready = 1'b1;

                if (vertex_valid) begin
                    next_v1 = vertex_data[63:0];
                    next_v2 = vertex_data[127:64];
                    next_v3 = vertex_data[191:128];

                    next_state = LOAD_TRIANGLE;
                end
				else if (sprite_valid) begin
					next_sprite_reg = sprite_data;
					next_state = LOAD_SPRITE;
				end
            end

			LOAD_TRIANGLE: begin
				next_rast_ready = 1'b0;

				next_x_curr = x_min;
				next_y_curr = y_min;

				area = sx1*(sy2 - sy3) + sx2*(sy3 - sy1) + sx3*(sy1 - sy2);

				if (area == 0) begin
					next_state = IDLE;
				end
				else begin
					if (area < 0) begin
						next_p1 = -(sy1 - sy2);
						next_q1 = -(sx2 - sx1);
						next_c1 = -(sx1*sy2 - sx2*sy1);
						next_p2 = -(sy2 - sy3);
						next_q2 = -(sx3 - sx2);
						next_c2 = -(sx2*sy3 - sx3*sy2);
						next_p3 = -(sy3 - sy1);
						next_q3 = -(sx1 - sx3);
						next_c3 = -(sx3*sy1 - sx1*sy3);

						next_e1_n = -($signed({1'b0, x_min})*(sy1 - sy2) + $signed({1'b0, y_min})*(sx2 - sx1) + (sx1*sy2 - sx2*sy1));
						next_e2_n = -($signed({1'b0, x_min})*(sy2 - sy3) + $signed({1'b0, y_min})*(sx3 - sx2) + (sx2*sy3 - sx3*sy2));
						next_e3_n = -($signed({1'b0, x_min})*(sy3 - sy1) + $signed({1'b0, y_min})*(sx1 - sx3) + (sx3*sy1 - sx1*sy3));

						next_area_n = -area;

						next_state = SCAN_TRIANGLE;
					end
					else if (area > 0) begin
						next_p1 = sy1 - sy2;
						next_q1 = sx2 - sx1;
						next_c1 = sx1*sy2 - sx2*sy1;
						next_p2 = sy2 - sy3;
						next_q2 = sx3 - sx2;
						next_c2 = sx2*sy3 - sx3*sy2;
						next_p3 = sy3 - sy1;
						next_q3 = sx1 - sx3;
						next_c3 = sx3*sy1 - sx1*sy3;

						next_e1_n = $signed({1'b0, x_min})*(sy1 - sy2) + $signed({1'b0, y_min})*(sx2 - sx1) + (sx1*sy2 - sx2*sy1);
						next_e2_n = $signed({1'b0, x_min})*(sy2 - sy3) + $signed({1'b0, y_min})*(sx3 - sx2) + (sx2*sy3 - sx3*sy2);
						next_e3_n = $signed({1'b0, x_min})*(sy3 - sy1) + $signed({1'b0, y_min})*(sx1 - sx3) + (sx3*sy1 - sx1*sy3);
						
						next_area_n = area;

						next_state = SCAN_TRIANGLE;
					end

					next_e1_row = next_e1_n;
					next_e2_row = next_e2_n;
					next_e3_row = next_e3_n;
					
					next_rcp_num = 1 << FRAC;
					next_rcp_quot = 0;
					next_rcp_bit = FRAC+1;
				end

			end

			// Code for color mixing calculation -- NOT IN USE
			CALC_RECIP: begin // Iterative divider code from Claude Opus
				if (rcp_bit == 0) begin
					next_inv_area = rcp_quot;
					next_state    = SCAN_TRIANGLE;
				end else begin
					// shift-subtract step
					if (rcp_num >= (area_n << (rcp_bit-1))) begin
						next_rcp_num  = rcp_num - (area_n << (rcp_bit-1));
						next_rcp_quot = rcp_quot | (1 << (rcp_bit-1));
					end
					next_rcp_bit = rcp_bit - 1;
				end
			end
				
            SCAN_TRIANGLE: begin
				pixel_valid = (e1_n >= 0) && (e2_n >= 0) && (e3_n >= 0);
				
				if (!fb_busy) begin
					if (y_curr > y_max) begin
						next_state = IDLE;
					end
					else if(x_curr >= x_max) begin
						next_x_curr = x_min;
						next_y_curr = y_curr + 1;

						next_e1_n = e1_row + q1;
						next_e2_n = e2_row + q2;
						next_e3_n = e3_row + q3;
						next_e1_row = e1_row + q1;
						next_e2_row = e2_row + q2;
						next_e3_row = e3_row + q3;
					end
					else begin
						next_x_curr = x_curr + 1;
						next_y_curr = y_curr;

						next_e1_n = e1_n + p1;
						next_e2_n = e2_n + p2;
						next_e3_n = e3_n + p3;
					end
				end

				/*
				r_wide = (e2_n*r1 + e3_n*r2 + e1_n*r3) * inv_area;
				g_wide = (e2_n*g1 + e3_n*g2 + e1_n*g3) * inv_area;
				b_wide = (e2_n*b1 + e3_n*b2 + e1_n*b3) * inv_area;
				
				r_mix = r_wide >>> FRAC;
				g_mix = g_wide >>> FRAC;
				b_mix = b_wide >>> FRAC;
				*/
				mixed_color = {r1[4:3], g1[5:4], b1[4:3]};
            end

			LOAD_SPRITE: begin
				next_rast_ready = 1'b0;

				next_x_curr = sprite_x;
				next_y_curr = sprite_y;

				next_state = SCAN_SPRITE;
			end
				
			SCAN_SPRITE: begin
				if (!fb_busy) begin
					if (y_curr > sprite_y_max) begin
						next_state = IDLE;
					end
					else if (x_curr >= sprite_x_max) begin
						next_x_curr = sprite_x;
						next_y_curr = y_curr + 1'b1;
					end
					else begin
						next_x_curr = x_curr + 1'b1;
						next_y_curr = y_curr;
					end
				end

				mixed_color = {sprite_r[4:3], sprite_g[5:4], sprite_b[4:3]};
				pixel_valid = sprite_bits[sprite_idx] && y_curr <= sprite_y_max;
			end

            default: next_state = IDLE;
        endcase
		
		next_write_en    = !fb_busy && ((state == SCAN_TRIANGLE) || (state == SCAN_SPRITE)) && pixel_valid;
		next_write_x     = (((state == SCAN_TRIANGLE) || (state == SCAN_SPRITE)) && pixel_valid) ? x_curr : '0;
		next_write_y     = (((state == SCAN_TRIANGLE) || (state == SCAN_SPRITE)) && pixel_valid) ? y_curr : '0;
		next_write_color = (((state == SCAN_TRIANGLE) || (state == SCAN_SPRITE)) && pixel_valid) ? mixed_color : '0;

	end

	// --- Constant calculations for edge equations and colors
	assign sx1 = $signed({1'b0,v1[8:0]});
	assign sx2 = $signed({1'b0, v2[8:0]});
	assign sx3 = $signed({1'b0, v3[8:0]});
	assign sy1 = $signed({1'b0, v1[16:9]});
	assign sy2 = $signed({1'b0, v2[16:9]});
	assign sy3 = $signed({1'b0, v3[16:9]});
	assign sx_curr = $signed({1'b0, x_curr});
	assign sy_curr = $signed({1'b0, y_curr});

	assign x_max = max3x(v1[8:0],v2[8:0],v3[8:0]);
	assign x_min = min3x(v1[8:0],v2[8:0],v3[8:0]);
	assign y_max = max3y(v1[16:9],v2[16:9],v3[16:9]);
	assign y_min = min3y(v1[16:9],v2[16:9],v3[16:9]);

	assign r1 = v1[21:17];
	assign g1 = v1[27:22];
	assign b1 = v1[32:28];
	assign r2 = v2[21:17];
	assign g2 = v2[27:22];
	assign b2 = v2[32:28];	
	assign r3 = v3[21:17];
	assign g3 = v3[27:22];
	assign b3 = v3[32:28];

endmodule