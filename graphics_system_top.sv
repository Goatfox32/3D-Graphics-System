module graphics_system_top (
    // FPGA fabric
    input  logic        clk50,
    input  logic        s1,
    output logic [7:0]  LED,

    // HPS DDR3 — required, connects to HPS hard memory controller
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

    // HPS IO — required for SD boot, SSH, UART debug, USB
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
    // F2H SDRAM0 interface — tied off until GPU
    // master module is instantiated here
    // ==========================================
    wire [28:0] f2h_sdram0_address;
    wire        f2h_sdram0_read;
    wire [63:0] f2h_sdram0_readdata;
    wire        f2h_sdram0_readdatavalid;
    wire        f2h_sdram0_waitrequest;
    wire [7:0]  f2h_sdram0_burstcount;

    assign f2h_sdram0_address    = '0;
    assign f2h_sdram0_read       = 1'b0;
    assign f2h_sdram0_burstcount = 8'd1;

    graphics_system u0 (
        .clk50_clk                       (clk50),
        .clk_reset_reset_n               (s1),

        .gpu_control_export_export       (LED),
        .gpu_status_export_export        (8'b0),
        .cmd_addr_export_export          (),   // unconnected until GPU core exists
        .cmd_size_export_export          (),   // unconnected until GPU core exists

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