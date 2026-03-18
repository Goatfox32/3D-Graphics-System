package require -exact qsys 14.0

create_system {graphics_system}
set_project_property DEVICE_FAMILY {Cyclone V}
set_project_property DEVICE {5CSEMA4U23C6}

# ==========================================
# 1. Add Components
# ==========================================
add_instance clk_0 clock_source
set_instance_parameter_value clk_0 {clockFrequency} {50000000}
set_instance_parameter_value clk_0 {clockFrequencyKnown} {true}

add_instance hps_0 altera_hps

# Enable Peripherals
set_instance_parameter_value hps_0 {SDIO_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {SDIO_Mode} {4-bit Data}
set_instance_parameter_value hps_0 {UART0_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {UART0_Mode} {No Flow Control}
set_instance_parameter_value hps_0 {USB1_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {USB1_Mode} {SDR}
set_instance_parameter_value hps_0 {EMAC1_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {EMAC1_Mode} {RGMII}

# Bridge config
set_instance_parameter_value hps_0 {S2F_Width} {0}
set_instance_parameter_value hps_0 {F2S_Width} {0}
set_instance_parameter_value hps_0 {F2SDRAM_Type} {"Avalon-MM Read-Only"}
set_instance_parameter_value hps_0 {F2SDRAM_Width} {64}

add_instance gpu_control altera_avalon_pio
set_instance_parameter_value gpu_control {direction} {Output}
set_instance_parameter_value gpu_control {width} {8}

add_instance gpu_status altera_avalon_pio
set_instance_parameter_value gpu_status {direction}    {Input}
set_instance_parameter_value gpu_status {width}        {8}
set_instance_parameter_value gpu_status {generateIRQ}  {1}
set_instance_parameter_value gpu_status {irqType}      {LEVEL}

add_instance cmd_addr altera_avalon_pio
set_instance_parameter_value cmd_addr {direction} {Output}
set_instance_parameter_value cmd_addr {width} {32}

add_instance cmd_size altera_avalon_pio
set_instance_parameter_value cmd_size {direction} {Output}
set_instance_parameter_value cmd_size {width} {32}

# ==========================================
# 2. Internal Connections
# ==========================================
# Clocks
add_connection clk_0.clk hps_0.h2f_lw_axi_clock
add_connection clk_0.clk hps_0.f2h_sdram0_clock
add_connection clk_0.clk gpu_control.clk
add_connection clk_0.clk gpu_status.clk
add_connection clk_0.clk cmd_addr.clk
add_connection clk_0.clk cmd_size.clk

# Resets
add_connection hps_0.h2f_reset clk_0.clk_in_reset
add_connection clk_0.clk_reset gpu_control.reset
add_connection clk_0.clk_reset gpu_status.reset
add_connection clk_0.clk_reset cmd_addr.reset
add_connection clk_0.clk_reset cmd_size.reset

# Data Bridge (HPS to PIO via Lightweight bridge)
add_connection hps_0.h2f_lw_axi_master gpu_control.s1
add_connection hps_0.h2f_lw_axi_master gpu_status.s1
add_connection hps_0.h2f_lw_axi_master cmd_addr.s1
add_connection hps_0.h2f_lw_axi_master cmd_size.s1
set_connection_parameter_value hps_0.h2f_lw_axi_master/cmd_addr.s1    baseAddress {0x0000}
set_connection_parameter_value hps_0.h2f_lw_axi_master/cmd_size.s1    baseAddress {0x0010}
set_connection_parameter_value hps_0.h2f_lw_axi_master/gpu_control.s1 baseAddress {0x0020}
set_connection_parameter_value hps_0.h2f_lw_axi_master/gpu_status.s1  baseAddress {0x0030}
add_connection gpu_status.irq hps_0.f2s_interrupts_peripheral
set_connection_parameter_value gpu_status.irq/hps_0.f2s_interrupts_peripheral irqNumber {0}

# ==========================================
# 3. External Exports
# ==========================================
add_interface clk50 clock sink
set_interface_property clk50 EXPORT_OF clk_0.clk_in

add_interface clk_reset reset sink
set_interface_property clk_reset EXPORT_OF clk_0.clk_in_reset

add_interface memory conduit end
set_interface_property memory EXPORT_OF hps_0.memory

add_interface hps_io conduit end
set_interface_property hps_io EXPORT_OF hps_0.hps_io

add_interface gpu_control_export conduit end
set_interface_property gpu_control_export EXPORT_OF gpu_control.external_connection

add_interface gpu_status_export conduit end
set_interface_property gpu_status_export EXPORT_OF gpu_status.external_connection

add_interface cmd_addr_export conduit end
set_interface_property cmd_addr_export EXPORT_OF cmd_addr.external_connection

add_interface cmd_size_export conduit end
set_interface_property cmd_size_export EXPORT_OF cmd_size.external_connection

add_interface f2h_sdram0 avalon slave
set_interface_property f2h_sdram0 EXPORT_OF hps_0.f2h_sdram0_data

# Save
save_system {graphics_system.qsys}