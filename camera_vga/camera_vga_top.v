module camera_vga_top(
    input wire CLOCK_50,
    input wire [3:0] KEY,
    input wire [17:0] SW,
    
    // OV7670 Camera Interface
    input wire ov7670_pclk,
    input wire ov7670_href,
    input wire ov7670_vsync,
    input wire [7:0] ov7670_data,
    output wire ov7670_xclk,
    output wire ov7670_sioc,
    inout wire ov7670_siod,
    output wire ov7670_reset,
    output wire ov7670_pwdn,
    
    // VGA Interface
    output wire [7:0] VGA_R,
    output wire [7:0] VGA_G,
    output wire [7:0] VGA_B,
    output wire VGA_HS,
    output wire VGA_VS,
    output wire VGA_CLK,
    output wire VGA_BLANK_N,
    output wire VGA_SYNC_N,
    
    // Debug LEDs
    output wire [7:0] LEDG,
    output wire [17:0] LEDR
);

    // Clock signals
    wire clk_25mhz, clk_100mhz, pll_locked;
    wire reset = ~KEY[0] || ~pll_locked;
    
    // Camera signals
    wire [15:0] camera_data;
    wire camera_data_valid;
    wire [16:0] camera_addr;
    wire camera_wren;
    wire config_done;
    
    // VGA signals
    wire [15:0] vga_data;
    wire [16:0] vga_addr;
    
    // PLL for clock generation
    pll_camera pll_inst(
        .inclk0(CLOCK_50),
        .c0(clk_25mhz),        // 25MHz for VGA
        .c1(clk_100mhz),       // 100MHz for system
        .c2(ov7670_xclk),      // 25MHz for camera
        .locked(pll_locked)
    );
    
    // Camera interface
    ov7670_controller camera_ctrl(
        .clk(clk_100mhz),
        .reset(reset),
        
        // OV7670 interface
        .ov7670_pclk(ov7670_pclk),
        .ov7670_href(ov7670_href),
        .ov7670_vsync(ov7670_vsync),
        .ov7670_data(ov7670_data),
        .ov7670_sioc(ov7670_sioc),
        .ov7670_siod(ov7670_siod),
        .ov7670_reset(ov7670_reset),
        .ov7670_pwdn(ov7670_pwdn),
        
        // Memory interface
        .mem_addr(camera_addr),
        .mem_data(camera_data),
        .mem_wren(camera_wren),
        .data_valid(camera_data_valid),
        .config_done(config_done)
    );
    
    // Frame buffer memory
    ram_dual_port frame_buffer(
        // Port A: Camera write
        .clock_a(ov7670_pclk),
        .address_a(camera_addr),
        .data_a(camera_data),
        .wren_a(camera_wren),
        .q_a(),  // Not used
        
        // Port B: VGA read
        .clock_b(clk_25mhz),
        .address_b(vga_addr),
        .data_b(16'h0000),
        .wren_b(1'b0),
        .q_b(vga_data)
    );
    
    // VGA controller
    vga_controller vga_ctrl(
        .clk(clk_25mhz),
        .reset(reset),
        
        // Memory interface
        .mem_addr(vga_addr),
        .mem_data(vga_data),
        
        // VGA outputs
        .vga_r(VGA_R),
        .vga_g(VGA_G),
        .vga_b(VGA_B),
        .vga_hs(VGA_HS),
        .vga_vs(VGA_VS),
        .vga_blank_n(VGA_BLANK_N)
    );
    
    assign VGA_CLK = clk_25mhz;
    assign VGA_SYNC_N = 1'b0;
    
    // Debug status LEDs
    assign LEDG[0] = pll_locked;
    assign LEDG[1] = config_done;
    assign LEDG[2] = camera_data_valid;
    assign LEDG[3] = ov7670_vsync;
    assign LEDG[4] = ov7670_href;
    assign LEDG[7:5] = 3'b000;
    
    assign LEDR[16:0] = camera_addr;
    assign LEDR[17] = camera_wren;

endmodule
