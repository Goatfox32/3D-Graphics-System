// Braden Vanderwoerd
// 2026-04-06
// Graphics System Top Module
// This is the top-level module that integrates the command reader, command executer, FIFOs, and the Qsys system.
// It also handles the interfacing with the HPS and the SDRAM, as well as the LED outputs for debugging.

`default_nettype none

module graphics_system_top (
    input  logic        clk50,
    input  logic        s1,
    output logic [7:0]  LED,
    output logic [35:0] GPIO_0,

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
    // Rasterizer interface
    // ==========================================
    logic         rast_enable;
    logic         rast_clear;
    logic         vertex_valid;
    logic [191:0] vertex_data;
    logic [63:0]  rast_set_pixel;
    assign rast_enable = 1'b1;

    // Debugging:
    // 100ms stretch helper — instantiate one per signal you want to see
    logic [22:0] stretch_start, stretch_busy, stretch_cmd_wr, stretch_data_wr, stretch_vvalid;

    logic start_pulse = 1'b0;
    always_ff @(posedge clk50) begin
        if (!system_reset_n) begin
            stretch_start   <= 0;
            stretch_busy    <= 0;
            stretch_cmd_wr  <= 0;
            stretch_data_wr <= 0;
            stretch_vvalid  <= 0;
        end else begin
            // Replace the signals on the right with the actual hierarchical paths
            if (start_pulse)                          stretch_start   <= 23'd5_000_000;
            else if (stretch_start   != 0)            stretch_start   <= stretch_start - 1;

            if (gpu_status_internal[0])               stretch_busy    <= 23'd5_000_000;
            else if (stretch_busy    != 0)            stretch_busy    <= stretch_busy - 1;

            if (command_buffer_write_en)              stretch_cmd_wr  <= 23'd5_000_000;
            else if (stretch_cmd_wr  != 0)            stretch_cmd_wr  <= stretch_cmd_wr - 1;

            if (data_buffer_write_en)                 stretch_data_wr <= 23'd5_000_000;
            else if (stretch_data_wr != 0)            stretch_data_wr <= stretch_data_wr - 1;

            if (vertex_valid)                         stretch_vvalid  <= 23'd5_000_000;
            else if (stretch_vvalid  != 0)            stretch_vvalid  <= stretch_vvalid - 1;
        end
    end

    /*
    assign LED[0] = (stretch_start   != 0);  // Did the reader see a start edge?
    assign LED[1] = (stretch_busy    != 0);  // Did the reader become busy?
    assign LED[2] = (stretch_cmd_wr  != 0);  // Did the reader write to cmd FIFO?
    assign LED[3] = (stretch_data_wr != 0);  // Did the reader write to data FIFO?
    assign LED[4] = (stretch_vvalid  != 0);  // Did the executer fire vertex_valid?
    assign LED[5] = gpu_status_internal[1];  // size_error (latched, no stretch needed)
    assign LED[6] = gpu_status_internal[3];  // stuck indicator
    assign LED[7] = !system_reset_n;
    */
    
    // v0 in vertex_data[63:0]
    assign LED[0] = (vertex_data[8:0]    == 9'd10) && (vertex_data[16:9]  == 8'd20);
    assign LED[1] = (vertex_data[21:17]  == 5'd31) && (vertex_data[27:22] == 6'd0)
                                                && (vertex_data[32:28] == 5'd0);

    // v1 in vertex_data[127:64]
    assign LED[2] = (vertex_data[72:64]  == 9'd20) && (vertex_data[80:73] == 8'd40);
    assign LED[3] = (vertex_data[85:81]  == 5'd0)  && (vertex_data[91:86] == 6'd63) // Failed
                                                && (vertex_data[96:92] == 5'd0);

    // v2 in vertex_data[191:128]
    assign LED[4] = (vertex_data[136:128] == 9'd30) && (vertex_data[144:137] == 8'd60);
    assign LED[5] = (vertex_data[149:145] == 5'd0)  && (vertex_data[155:150] == 6'd0) // Failed
                                                && (vertex_data[160:156] == 5'd31);

    // Padding sanity: top bits of each vertex should be zero
    assign LED[6] = (vertex_data[63:33]   == 31'd0)
                && (vertex_data[127:97]  == 31'd0)
                && (vertex_data[191:161] == 31'd0);

    // All eight checks AND'd — single "everything correct" indicator
    assign LED[7] = LED[0] & LED[1] & LED[2] & LED[3] & LED[4] & LED[5] & LED[6]; // Failed
    

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
        .rast_set_pixel      (rast_set_pixel)
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