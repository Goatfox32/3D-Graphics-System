# FPGA GPU Project Specification
**Platform:** DE0-Atlas SoC (Cyclone V 5CSEMA4U23C6)  
**Status:** In Development — Bridge bring-up phase  
**Last Updated:** 2026-03-17

---

## 1. System Overview

A triangle-rasterization GPU implemented in FPGA fabric, controlled by an ARM Linux HPS over the SoC's internal bridges. The HPS acts as the application CPU — it builds command buffers in DDR3 memory and signals the GPU via control registers. The FPGA GPU reads those commands, rasterizes triangles into a local framebuffer in block RAM, and streams pixels to a VGA display.

### Design Principles
- GPU is **read-only with respect to DDR3** — it never writes back, simplifying coherency
- Framebuffer lives in **FPGA block RAM** — deterministic latency, no DDR contention during scanout
- HPS/GPU interface is **minimal and explicit** — a small set of registers over the lightweight bridge, bulk data over F2SDRAM
- Top-level `.sv` is a **pure pin wrapper** — all logic lives below it

---

## 2. Hardware Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        HPS (ARM A9)                     │
│                       Linux OS                          │
└──────────┬──────────────────────────┬───────────────────┘
           │                          │
   LW H2F Bridge              F2SDRAM Bridge
   (control regs)           (command buffer reads)
           │                          │
           ▼                          ▼
   ┌───────────────┐         ┌─────────────────┐
   │ GPU Registers │         │   DDR3 RAM      │
   │  (PIOs in     │         │ Command Buffer  │
   │   Qsys)       │         │ Vertex Data     │
   └───────┬───────┘         └────────┬────────┘
           │                          │
           └──────────┬───────────────┘
                      │
               ┌──────▼──────┐
               │  GPU Core   │
               │  (FPGA)     │
               └──────┬──────┘
                      │
               ┌──────▼──────┐
               │  Framebuffer│
               │  (BRAM)     │
               │  320×240    │
               │  16-bit RGB │
               └──────┬──────┘
                      │
               ┌──────▼──────┐
               │VGA Controller│
               └──────┬──────┘
                      │
                   Monitor
              (via breakout board)
```

---

## 3. Bridge Configuration

| Bridge | Qsys Parameter | Setting | Purpose |
|--------|---------------|---------|---------|
| H2F Lightweight AXI | `LWH2F_Enable` | true | Control register access |
| H2F Full AXI | `S2F_Width` | 0 (disabled) | Not needed |
| F2H Full AXI | `F2S_Width` | 0 (disabled) | Not needed |
| F2SDRAM port 0 | `F2SDRAM_Type` | Avalon-MM Read-Only | GPU reads DDR3 |
| F2SDRAM width | `F2SDRAM_Width` | 64-bit | 1 read = 1 vertex |

**F2SDRAM clock:** 50 MHz (clk_0, same as LW bridge)

---

## 4. Register Map

Base address of LW bridge on HPS: `0xFF200000`

| Offset | Name | Direction | Width | Description |
|--------|------|-----------|-------|-------------|
| `0x0000` | `CMD_ADDR` | HPS → GPU | 32-bit | Physical address of command buffer in DDR3 |
| `0x0010` | `CMD_SIZE` | HPS → GPU | 32-bit | Size of command buffer in bytes |
| `0x0020` | `GPU_CONTROL` | HPS → GPU | 8-bit | Control bits (see below) |
| `0x0030` | `GPU_STATUS` | GPU → HPS | 8-bit | Status bits (see below) |

> **Note:** Offsets are spaced 0x10 apart due to Avalon-MM minimum slave footprint.  
> All software must use these offsets, not the tighter layout in the architecture overview doc.

### GPU_CONTROL Bit Map (offset 0x0020)
| Bit | Name | Description |
|-----|------|-------------|
| 0 | `START` | Write 1 to begin GPU execution. GPU clears when done. |
| 1 | `RESET` | Write 1 to abort current operation and reset GPU state |
| 7:2 | — | Reserved, write 0 |

### GPU_STATUS Bit Map (offset 0x0030)
| Bit | Name | Description |
|-----|------|-------------|
| 0 | `BUSY` | 1 while GPU is executing |
| 1 | `DONE` | 1 when last render completed (cleared on next START) |
| 2 | `ERROR` | 1 if GPU encountered a malformed command |
| 7:3 | — | Reserved |

### Interrupt
`GPU_STATUS` bit 1 (`DONE`) triggers an interrupt to the HPS via the F2S interrupt line (IRQ 0 in Linux = GIC SPI 72+). Software should use this rather than polling in any production code.

---

## 5. Command Buffer Format

### Layout Rules
- Command buffer is written by HPS to DDR3 at any 64-bit aligned physical address
- **All commands must start on an 8-byte boundary.** The 64-bit F2SDRAM bus reads 8 bytes per transaction; misaligned commands will cause the parser to read garbage on the second word. Pad with `CMD_NOP` if needed.
- GPU reads sequentially from `CMD_ADDR` until `CMD_SIZE` bytes have been consumed
- Total buffer size must be a multiple of 8 bytes

### Command Header Format
Every command is at minimum 8 bytes:

```
Bytes 0-3:  Opcode       (uint32)
Bytes 4-7:  Payload word (uint32, meaning is opcode-specific)
Bytes 8+:   Variable payload (opcode-specific, always padded to 8-byte boundary)
```

### Opcode Table

| Opcode | Value | Payload Word | Extra Payload | Description |
|--------|-------|-------------|---------------|-------------|
| `CMD_NOP` | `0x00` | ignored | none | No operation, used for alignment padding |
| `CMD_CLEAR` | `0x01` | 16-bit color in low 16 bits | none | Fill framebuffer with solid color |
| `CMD_DRAW_TRIANGLES` | `0x02` | vertex_count (uint32) | vertex_count × 8 bytes | Rasterize list of triangles |
| `CMD_END` | `0xFF` | ignored | none | Signals end of buffer, sets DONE |

### DRAW_TRIANGLES Example (6 vertices = 2 triangles)

```
Offset  Content
0x00    0x00000002        (opcode CMD_DRAW_TRIANGLES)
0x04    0x00000006        (vertex_count = 6)
0x08    [vertex 0]        (8 bytes)
0x10    [vertex 1]
0x18    [vertex 2]
0x20    [vertex 3]
0x28    [vertex 4]
0x30    [vertex 5]
0x38    0x000000FF        (CMD_END)
0x3C    0x00000000        (padding to 8-byte boundary)
```

Triangles are indexed sequentially: (v0,v1,v2), (v3,v4,v5), etc. Vertex count must be a multiple of 3.

---

## 6. Vertex Format

Each vertex is **8 bytes** — exactly one 64-bit DDR read.

```c
struct Vertex {
    uint16_t x;      // bytes 0-1: screen X coordinate (0 to 319)
    uint16_t y;      // bytes 2-3: screen Y coordinate (0 to 239)
    uint16_t color;  // bytes 4-5: RGB565 color
    uint16_t extra;  // bytes 6-7: reserved for future use
};
```

### The `extra` Field — Future Use Candidates
- Z-depth (painter's algorithm ordering)
- Per-vertex alpha flag
- Texture coordinate index
- Shader mode selector

Do not rely on `extra` being zero. The GPU must ignore it until a feature is explicitly defined.

### RGB565 Color Format
```
Bit 15-11: Red   (5 bits)
Bit 10-5:  Green (6 bits)
Bit 4-0:   Blue  (5 bits)
```

---

## 7. Framebuffer

| Property | Value |
|----------|-------|
| Resolution | 320 × 240 pixels |
| Color depth | 16-bit RGB565 |
| Storage | FPGA block RAM (M10K) |
| Size | 320 × 240 × 2 = 153,600 bytes ≈ 150 KB |
| Estimated M10K usage | ~84 blocks of 10Kb = ~840 Kb — within budget |
| Address space | Linear, row-major: `addr = y * 320 + x` |

The GPU rasterizer writes pixels into BRAM. The VGA controller reads from the same BRAM. No explicit locking is needed at this stage — writes and reads are in different clock phases and tearing is acceptable for the initial version. Double buffering is a future extension.

---

## 8. VGA Output

**Target resolution:** 320×240 @ 60Hz  
**Pixel clock:** 6.25 MHz (50 MHz ÷ 8, generated by FPGA PLL from clk50)  
**Output:** Via VGA breakout board connected directly to FPGA GPIO pins

### VGA Timing (320×240 @ 60Hz)

| Parameter | Pixels |
|-----------|--------|
| Horizontal active | 320 |
| H front porch | 8 |
| H sync pulse | 48 |
| H back porch | 24 |
| H total | 400 |
| Vertical active | 240 |
| V front porch | 2 |
| V sync pulse | 3 |
| V back porch | 15 |
| V total | 260 |

Sync polarity: both negative.

VGA controller reads one pixel per pixel clock from framebuffer, outputs RGB and sync signals. During blanking intervals, RGB outputs are driven to 0.

---

## 9. GPU Pipeline (FPGA Logic)

```
CMD_ADDR/CMD_SIZE registers
        │
        ▼
  Command Reader          — reads 8-byte words from DDR via F2SDRAM
        │
        ▼
  Command Decoder         — identifies opcode, dispatches to handler
        │
        ▼
  Vertex Fetch            — reads vertex_count × 8 bytes from DDR
        │
        ▼
  Triangle Setup          — computes edge equations for each triangle
        │
        ▼
  Rasterizer              — iterates bounding box, tests each pixel
        │
        ▼
  Framebuffer Write       — writes passing pixels to BRAM at (x + y*320)
        │
        ▼ (concurrent, not sequential)
  VGA Controller          — reads BRAM, drives VGA signals
```

---

## 10. HPS Software Interface

### devmem Register Access (debug/testing)
```bash
# Enable LW bridge
echo 1 > /sys/class/fpga_bridge/lwhps2fpga/enable

# Write command buffer address
devmem 0xFF200000 32 0x20000000

# Write command buffer size
devmem 0xFF200010 32 512

# Trigger GPU (START=1)
devmem 0xFF200020 32 0x01

# Poll status
devmem 0xFF200030 32
```

### Production Software Flow
```c
// 1. Allocate physically contiguous buffer (use /dev/mem or CMA)
void* cmd_buf = mmap_phys(CMD_BUF_PHYS_ADDR, CMD_BUF_SIZE);

// 2. Build command buffer in userspace
write_cmd_draw_triangles(cmd_buf, vertices, vertex_count);
write_cmd_end(cmd_buf);

// 3. Flush cache (critical — GPU bypasses cache via F2SDRAM)
flush_dcache(cmd_buf, CMD_BUF_SIZE);

// 4. Write registers
writel(CMD_BUF_PHYS_ADDR, lw_base + 0x0000);
writel(CMD_BUF_SIZE,       lw_base + 0x0010);

// 5. Start GPU
writel(0x01, lw_base + 0x0020);

// 6. Wait for interrupt (preferred) or poll STATUS DONE bit
wait_for_irq();  // or: while(!(readl(lw_base + 0x0030) & 0x02));
```

> **Cache flush is mandatory.** The HPS data cache is not visible to the F2SDRAM bridge. If you don't flush after writing the command buffer, the GPU may read stale data from DDR.

---

## 11. Development Stages

| Stage | Goal | Status |
|-------|------|--------|
| 1 | LW bridge verified — devmem writes light LEDs | 🔄 In progress |
| 2 | F2SDRAM bridge verified — GPU reads test pattern from DDR | ⬜ Not started |
| 3 | VGA controller outputs solid color from BRAM | ⬜ Not started |
| 4 | Command reader parses CMD_CLEAR and CMD_END | ⬜ Not started |
| 5 | Rasterizer draws filled triangles | ⬜ Not started |
| 6 | HPS userspace library drives the GPU | ⬜ Not started |
| 7 | Interrupt-driven completion, cache flush in driver | ⬜ Not started |
| 8 | Double buffering, extra field features | ⬜ Future |

---

## 12. Known Constraints and Decisions

- **No GPU writes to DDR.** Framebuffer is BRAM only. This is a deliberate simplification.
- **Single framebuffer.** Tearing is acceptable in initial versions. Double buffering is a future extension.
- **Physical addressing.** HPS software must use physical addresses for CMD_ADDR. Virtual addresses will not work. Use `/dev/mem` or a kernel driver with `dma_alloc_coherent`.
- **Command buffer alignment.** Every command must start on an 8-byte boundary. This is a hard requirement of the 64-bit F2SDRAM bus.
- **F2SDRAM is read-only.** Chosen intentionally. GPU has no write path to DDR.
- **50 MHz system clock.** Both LW bridge and F2SDRAM run at 50 MHz from clk_0. This is conservative and can be increased later if timing closure requires it.

---

## 13. Files

| File | Purpose |
|------|---------|
| `graphics_system.tcl` | Qsys system generation script |
| `graphics_system.qsys` | Generated Qsys system (do not edit directly) |
| `graphics_system_top.sv` | Top-level pin wrapper |
| `gpu_project_spec.md` | This document |

---

## 14. Future Extensions

- Indexed vertex buffers (reuse vertices across triangles)
- Texture mapping (using `extra` field as texture coordinate index)
- Double buffered framebuffer (ping-pong between two BRAM banks)
- DMA command streaming (HPS DMA engine feeds GPU without CPU involvement)
- Z-buffer / painter's algorithm for 3D scenes
- Tile-based rasterization for better cache behavior
- Higher resolution (640×480) if BRAM budget allows after GPU logic is placed