# Braden Vanderwoerd & Jacob Edwards
# 2026-04-13
# Documented by Claude Opus 4.6 - 2026-04-14
# Qsys/Platform Designer System Definition — graphics_system
# Defines the SoC interconnect for the DE10-Nano graphics project:
#   - HPS (ARM Cortex-A9) with DDR3, Ethernet, UART, USB, SD card
#   - Lightweight AXI bridge -> four PIO registers (cmd_addr, cmd_size, gpu_control, gpu_status)
#   - F2H SDRAM0 read-only port (64-bit Avalon-MM) for GPU command DMA
# The generated .qsys file is consumed by Quartus to build the hardware system.

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

# Enable HPS peripherals (directly wired to DE10-Nano board I/O)
set_instance_parameter_value hps_0 {SDIO_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {SDIO_Mode} {4-bit Data}
set_instance_parameter_value hps_0 {UART0_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {UART0_Mode} {No Flow Control}
set_instance_parameter_value hps_0 {USB1_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {USB1_Mode} {SDR}
set_instance_parameter_value hps_0 {EMAC1_PinMuxing} {HPS I/O Set 0}
set_instance_parameter_value hps_0 {EMAC1_Mode} {RGMII}
set_instance_parameter_value hps_0 {MEM_DQ_WIDTH} {32}

# Bridge config: no S2F or F2S general bridges; only F2H SDRAM read-only (64-bit)
# The FPGA reads command buffers from DDR3 via this port (command_reader.sv)
set_instance_parameter_value hps_0 {S2F_Width} {0}
set_instance_parameter_value hps_0 {F2S_Width} {0}
set_instance_parameter_value hps_0 {F2SDRAM_Type} {"Avalon-MM Read-Only"}
set_instance_parameter_value hps_0 {F2SDRAM_Width} {64}

# PIO registers: HPS writes control/address/size, reads status back
add_instance gpu_control altera_avalon_pio
set_instance_parameter_value gpu_control {direction} {Output}    ;# HPS -> FPGA
set_instance_parameter_value gpu_control {width} {8}

add_instance gpu_status altera_avalon_pio
set_instance_parameter_value gpu_status {direction}    {Input}   ;# FPGA -> HPS
set_instance_parameter_value gpu_status {width}        {8}
set_instance_parameter_value gpu_status {generateIRQ}  {1}       ;# Level-triggered IRQ (optional, polled in current software)
set_instance_parameter_value gpu_status {irqType}      {LEVEL}

add_instance cmd_addr altera_avalon_pio
set_instance_parameter_value cmd_addr {direction} {Output}       ;# SDRAM address of command buffer
set_instance_parameter_value cmd_addr {width} {32}

add_instance cmd_size altera_avalon_pio
set_instance_parameter_value cmd_size {direction} {Output}       ;# Command size in bytes
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

# Data Bridge: PIO registers mapped into the lightweight AXI address space
# Software accesses these at LW_BRIDGE_BASE (0xFF200000) + offset
add_connection hps_0.h2f_lw_axi_master gpu_control.s1
add_connection hps_0.h2f_lw_axi_master gpu_status.s1
add_connection hps_0.h2f_lw_axi_master cmd_addr.s1
add_connection hps_0.h2f_lw_axi_master cmd_size.s1
set_connection_parameter_value hps_0.h2f_lw_axi_master/cmd_addr.s1    baseAddress {0x0000}  ;# offset 0x00
set_connection_parameter_value hps_0.h2f_lw_axi_master/cmd_size.s1    baseAddress {0x0010}  ;# offset 0x10
set_connection_parameter_value hps_0.h2f_lw_axi_master/gpu_control.s1 baseAddress {0x0020}  ;# offset 0x20
set_connection_parameter_value hps_0.h2f_lw_axi_master/gpu_status.s1  baseAddress {0x0030}  ;# offset 0x30
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