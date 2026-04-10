// Braden Vanderwoerd & Jacob Edwards
// 2026-04-06
// Graphics System Top Module
// This is the top-level module that integrates the command reader, command executer, FIFOs, and the Qsys system.
// It also handles the interfacing with the HPS and the SDRAM, as well as the LED outputs for debugging.

`default_nettype none

module graphics_system_top (
    input  logic        clk50,
    input  logic        s1,
    output logic [7:0]  LED,
    inout  wire  [35:0] GPIO_0,

    output wire [14:0]  HPS_DDR3_ADDR,
    output wire [2:0]   HPS_DDR3_BA,
    output wire         HPS_DDR3_CAS_N,
    output wire         HPS_DDR3_CKE,
    output wire         HPS_DDR3_CK_N,
    output wire         HPS_DDR3_CK_P,
    output wire         HPS_DDR3_CS_N,
    output wire [3:0]   HPS_DDR3_DM,
    inout  wire [31:0]  HPS_DDR3_DQ,
    inout  wire [3:0]   HPS_DDR3_DQS_N,
    inout  wire [3:0]   HPS_DDR3_DQS_P,
    output wire         HPS_DDR3_ODT,
    output wire         HPS_DDR3_RAS_N,
    output wire         HPS_DDR3_RESET_N,
    input  wire         HPS_DDR3_RZQ,
    output wire         HPS_DDR3_WE_N,

    output wire         HPS_ENET_GTX_CLK,
    output wire         HPS_ENET_MDC,
    inout  wire         HPS_ENET_MDIO,
    input  wire         HPS_ENET_RX_CLK,
    input  wire [3:0]   HPS_ENET_RX_DATA,
    input  wire         HPS_ENET_RX_DV,
    output wire [3:0]   HPS_ENET_TX_DATA,
    output wire         HPS_ENET_TX_EN,
    output wire         HPS_SD_CLK,
    inout  wire         HPS_SD_CMD,
    inout  wire [3:0]   HPS_SD_DATA,
    input  wire         HPS_UART_RX,
    output wire         HPS_UART_TX,
    input  wire         HPS_USB_CLKOUT,
    inout  wire [7:0]   HPS_USB_DATA,
    input  wire         HPS_USB_DIR,
    input  wire         HPS_USB_NXT,
    output wire         HPS_USB_STP
);

    // ==========================================
    // PIO signals
    // ==========================================
    logic [7:0]  gpu_control_internal;
    logic [7:0]  gpu_status_internal;
    logic [31:0] cmd_addr_internal;
    logic [31:0] cmd_size_internal;

    // ==========================================
    // F2H SDRAM0 wires
    // ==========================================
    logic [28:0] f2h_sdram0_address;
    logic        f2h_sdram0_read;
    logic [63:0] f2h_sdram0_readdata;
    logic        f2h_sdram0_readdatavalid;
    logic        f2h_sdram0_waitrequest;
    logic [7:0]  f2h_sdram0_burstcount;

    // ==========================================
    // Command buffer
    // ==========================================
    logic        command_buffer_full;
    logic        command_buffer_write_en;
    logic [63:0] command_buffer_data_in;
    logic        command_buffer_empty;
    logic [63:0] command_buffer_data_out;
    logic        command_buffer_read_en;

    // ==========================================
    // Data buffer
    // ==========================================
    logic        data_buffer_full;
    logic [4:0]  data_buffer_count;
    logic        data_buffer_write_en;
    logic [63:0] data_buffer_data_in;
    logic        data_buffer_empty;
    logic [63:0] data_buffer_data_out;
    logic        data_buffer_read_en;

    // ==========================================
    // Rasterizer-Command interface
    // ==========================================
    logic         rast_enable;
    logic         rast_clear;
    logic         vertex_valid;
    logic [191:0] vertex_data;
    logic [63:0]  rast_set_pixel;
    logic         sprite_valid;
    logic [127:0] sprite_data;

    // ==========================================
    // Rasterizer-Frame Buffer interface
    // ==========================================
    logic                  rast_write_en;
    logic [X_WIDTH-1:0]    rast_write_x;
    logic [Y_WIDTH-1:0]    rast_write_y;
    logic [PIXEL_SIZE-1:0] rast_write_color;
    logic                  fb_busy;

    // ==========================================
    // Frame Buffer - VGA interface
    // ==========================================
    logic [X_WIDTH-1:0]    fb_read_x;
    logic [Y_WIDTH-1:0]    fb_read_y;
    logic [PIXEL_SIZE-1:0] fb_read_data;
    logic                  vga_clk;

    logic [$clog2(800)-1:0] h_counter;
	logic [$clog2(525)-1:0] v_counter;

    localparam int FB_WIDTH   = 320;
	localparam int FB_HEIGHT  = 240;
	localparam int PIXEL_SIZE = 6;
	localparam int X_WIDTH    = 9;
	localparam int Y_WIDTH    = 8;

    // Reset holding logic
    logic [26:0] reset_counter;
    always_ff @(posedge clk50) begin
        if (!s1) begin
            reset_counter <= 0;
        end else if (reset_counter < 27'd50_000_000) begin // Hold reset for 1 second
            reset_counter <= reset_counter + 1;
        end
    end
    wire system_reset_n = (reset_counter >= 27'd50_000_000);

    command_reader cmd_reader (
        .clk            (clk50),
        .reset_n        (system_reset_n),

        .read_addr          (cmd_addr_internal),
        .read_size          (cmd_size_internal),
        .status             (gpu_status_internal),
        .control            (gpu_control_internal), // Edge detection is done inside the command processor !!!
  
        .avm_address        (f2h_sdram0_address),
        .avm_read           (f2h_sdram0_read),
        .avm_burstcount     (f2h_sdram0_burstcount),
        .avm_readdata       (f2h_sdram0_readdata),
        .avm_readdatavalid  (f2h_sdram0_readdatavalid),
        .avm_waitrequest    (f2h_sdram0_waitrequest),

        .command_buffer_full(command_buffer_full),
        .command_buffer_en  (command_buffer_write_en),
        .command_buffer_data(command_buffer_data_in),

        .data_buffer_full   (data_buffer_full),
        .data_buffer_count  (data_buffer_count),
        .data_buffer_en     (data_buffer_write_en),
        .data_buffer_data   (data_buffer_data_in)
    );

    fifo cmd_fifo (
        .clk        (clk50),
        .reset_n    (system_reset_n),

        .data_in    (command_buffer_data_in),
        .write_en   (command_buffer_write_en),
        .data_out   (command_buffer_data_out),
        .read_en    (command_buffer_read_en),
        .empty      (command_buffer_empty),
        .count      (), // Unused
        .full       (command_buffer_full)
    );

    fifo data_fifo (
        .clk        (clk50),
        .reset_n    (system_reset_n),

        .data_in    (data_buffer_data_in),
        .write_en   (data_buffer_write_en),
        .data_out   (data_buffer_data_out),
        .read_en    (data_buffer_read_en),
        .empty      (data_buffer_empty),
        .count      (data_buffer_count),
        .full       (data_buffer_full)
    );

    command_executer cmd_exec (
        .clk                 (clk50),
        .reset_n             (system_reset_n),

        .command_buffer_empty(command_buffer_empty),
        .command_buffer_data (command_buffer_data_out),
        .command_buffer_en   (command_buffer_read_en),

        .data_buffer_empty   (data_buffer_empty),
        .data_buffer_data    (data_buffer_data_out),
        .data_buffer_en      (data_buffer_read_en),

        .rast_ready          (rast_enable),
        .vertex_valid        (vertex_valid),
        .vertex_data         (vertex_data),
        .rast_clear          (rast_clear),
        .rast_set_pixel      (rast_set_pixel),
        .sprite_valid        (sprite_valid),
        .sprite_data         (sprite_data)
    );

    
    logic [7:0] debug_sticky;

    always_ff @(posedge clk) begin
        if (~s1) begin
            debug_sticky <= '0;
        end else begin
            if (sprite_valid)                debug_sticky[0] <= 1'b1; // executer pulsed sprite_valid
            if (rast_u.write_en)             debug_sticky[1] <= 1'b1; // rasterizer wrote a pixel
            if (fb_u.busy)                   debug_sticky[2] <= 1'b1; // FB entered clear at some point
            debug_sticky[3] <= rast_ready;   // live — is rasterizer stuck?
            debug_sticky[4] <= fb_u.busy;    // live — is FB stuck in clear?
            debug_sticky[5] <= sprite_valid; // live — momentary flash
        end
    end

    assign LED = debug_sticky;

    rasterizer #(
        .FB_WIDTH(FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT),
        .PIXEL_SIZE(PIXEL_SIZE),
        .X_WIDTH(X_WIDTH),
        .Y_WIDTH(Y_WIDTH)
	) rast_u (
        .clk(clk50),
        .s1(s1),
        .vertex_data(vertex_data),
        .vertex_valid(vertex_valid),
        .sprite_data(sprite_data),
        .sprite_valid(sprite_valid),
        .rast_ready(rast_enable),
        .write_en(rast_write_en),
        .write_x(rast_write_x),
        .write_y(rast_write_y),
        .write_color(rast_write_color),
        .fb_busy(fb_busy)
	);

    frame_buffer #(
        .FB_WIDTH(FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT),
        .PIXEL_SIZE(PIXEL_SIZE),
        .X_WIDTH(X_WIDTH),
        .Y_WIDTH(Y_WIDTH)
	) fb_u (
        .s1(s1),
        .hps_clear(rast_clear),
        .write_clk(clk50),
        .write_en(rast_write_en),
        .write_x(rast_write_x),
        .write_y(rast_write_y),
        .write_data(rast_write_color),
        .read_clk(vga_clk),
        .read_x(fb_read_x),
        .read_y(fb_read_y),
        .read_data(fb_read_data),
        .busy(fb_busy)
	);

    vga_timing vga_u (
        .clk50(clk50),
        .s1(s1),
        .pixel_in(fb_read_data),
        .clk_div(vga_clk),
        .GPIO_0(GPIO_0[7:0]),
        .h_counter(h_counter),
        .v_counter(v_counter),
        .read_x(fb_read_x),
        .read_y(fb_read_y)
	);

    // ==========================================
    // Qsys system
    // ==========================================
    graphics_system u0 (
        .clk50_clk                       (clk50),
        .clk_reset_reset_n               (s1),

        .gpu_control_export_export       (gpu_control_internal),
        .gpu_status_export_export        (gpu_status_internal),
        .cmd_addr_export_export          (cmd_addr_internal),
        .cmd_size_export_export          (cmd_size_internal),

        .f2h_sdram0_address              (f2h_sdram0_address),
        .f2h_sdram0_read                 (f2h_sdram0_read),
        .f2h_sdram0_readdata             (f2h_sdram0_readdata),
        .f2h_sdram0_readdatavalid        (f2h_sdram0_readdatavalid),
        .f2h_sdram0_waitrequest          (f2h_sdram0_waitrequest),
        .f2h_sdram0_burstcount           (f2h_sdram0_burstcount),

        .memory_mem_a                    (HPS_DDR3_ADDR),
        .memory_mem_ba                   (HPS_DDR3_BA),
        .memory_mem_ck                   (HPS_DDR3_CK_P),
        .memory_mem_ck_n                 (HPS_DDR3_CK_N),
        .memory_mem_cke                  (HPS_DDR3_CKE),
        .memory_mem_cs_n                 (HPS_DDR3_CS_N),
        .memory_mem_ras_n                (HPS_DDR3_RAS_N),
        .memory_mem_cas_n                (HPS_DDR3_CAS_N),
        .memory_mem_we_n                 (HPS_DDR3_WE_N),
        .memory_mem_reset_n              (HPS_DDR3_RESET_N),
        .memory_mem_dq                   (HPS_DDR3_DQ),
        .memory_mem_dqs                  (HPS_DDR3_DQS_P),
        .memory_mem_dqs_n                (HPS_DDR3_DQS_N),
        .memory_mem_odt                  (HPS_DDR3_ODT),
        .memory_mem_dm                   (HPS_DDR3_DM),
        .memory_oct_rzqin                (HPS_DDR3_RZQ),

        .hps_io_hps_io_emac1_inst_TX_CLK (HPS_ENET_GTX_CLK),
        .hps_io_hps_io_emac1_inst_TXD0   (HPS_ENET_TX_DATA[0]),
        .hps_io_hps_io_emac1_inst_TXD1   (HPS_ENET_TX_DATA[1]),
        .hps_io_hps_io_emac1_inst_TXD2   (HPS_ENET_TX_DATA[2]),
        .hps_io_hps_io_emac1_inst_TXD3   (HPS_ENET_TX_DATA[3]),
        .hps_io_hps_io_emac1_inst_RXD0   (HPS_ENET_RX_DATA[0]),
        .hps_io_hps_io_emac1_inst_MDIO   (HPS_ENET_MDIO),
        .hps_io_hps_io_emac1_inst_MDC    (HPS_ENET_MDC),
        .hps_io_hps_io_emac1_inst_RX_CTL (HPS_ENET_RX_DV),
        .hps_io_hps_io_emac1_inst_TX_CTL (HPS_ENET_TX_EN),
        .hps_io_hps_io_emac1_inst_RX_CLK (HPS_ENET_RX_CLK),
        .hps_io_hps_io_emac1_inst_RXD1   (HPS_ENET_RX_DATA[1]),
        .hps_io_hps_io_emac1_inst_RXD2   (HPS_ENET_RX_DATA[2]),
        .hps_io_hps_io_emac1_inst_RXD3   (HPS_ENET_RX_DATA[3]),
        .hps_io_hps_io_sdio_inst_CMD     (HPS_SD_CMD),
        .hps_io_hps_io_sdio_inst_D0      (HPS_SD_DATA[0]),
        .hps_io_hps_io_sdio_inst_D1      (HPS_SD_DATA[1]),
        .hps_io_hps_io_sdio_inst_CLK     (HPS_SD_CLK),
        .hps_io_hps_io_sdio_inst_D2      (HPS_SD_DATA[2]),
        .hps_io_hps_io_sdio_inst_D3      (HPS_SD_DATA[3]),
        .hps_io_hps_io_usb1_inst_D0      (HPS_USB_DATA[0]),
        .hps_io_hps_io_usb1_inst_D1      (HPS_USB_DATA[1]),
        .hps_io_hps_io_usb1_inst_D2      (HPS_USB_DATA[2]),
        .hps_io_hps_io_usb1_inst_D3      (HPS_USB_DATA[3]),
        .hps_io_hps_io_usb1_inst_D4      (HPS_USB_DATA[4]),
        .hps_io_hps_io_usb1_inst_D5      (HPS_USB_DATA[5]),
        .hps_io_hps_io_usb1_inst_D6      (HPS_USB_DATA[6]),
        .hps_io_hps_io_usb1_inst_D7      (HPS_USB_DATA[7]),
        .hps_io_hps_io_usb1_inst_CLK     (HPS_USB_CLKOUT),
        .hps_io_hps_io_usb1_inst_STP     (HPS_USB_STP),
        .hps_io_hps_io_usb1_inst_DIR     (HPS_USB_DIR),
        .hps_io_hps_io_usb1_inst_NXT     (HPS_USB_NXT),
        .hps_io_hps_io_uart0_inst_RX     (HPS_UART_RX),
        .hps_io_hps_io_uart0_inst_TX     (HPS_UART_TX)
    );

endmodule
