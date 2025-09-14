// Top-level module for OV7670 camera interface
module digital_cam_top (
    input  wire        clk_50,
    input  wire        btn_resend,
    output wire        led_config_finished,
    
    // VGA outputs
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_blank_N,
    output wire        vga_sync_N,
    output wire        vga_CLK,
    
    // OV7670 camera interface
    input  wire        ov7670_pclk,
    output wire        ov7670_xclk,
    input  wire        ov7670_vsync,
    input  wire        ov7670_href,
    input  wire [7:0]  ov7670_data,
    output wire        ov7670_sioc,
    inout  wire        ov7670_siod,
    output wire        ov7670_pwdn,
    output wire        ov7670_reset
);

    // Internal signals
    wire clk_50_camera;
    wire clk_25_vga;
    wire wren;
    wire resend;
    wire nBlank;
    wire vSync;
    wire [16:0] wraddress;
    wire [11:0] wrdata;
    wire [16:0] rdaddress;
    wire [11:0] rddata;
    wire activeArea;
    
    // Assignments
    assign resend = ~btn_resend;  // DE2-115 has active-low buttons
    assign vga_vsync = vSync;
    assign vga_blank_N = nBlank;
    
    // RGB conversion - inline instead of separate module
    assign vga_r = activeArea ? {rddata[11:8], rddata[11:8]} : 8'h00;
    assign vga_g = activeArea ? {rddata[7:4], rddata[7:4]} : 8'h00;
    assign vga_b = activeArea ? {rddata[3:0], rddata[3:0]} : 8'h00;
    
    // PLL instance - you'll need to configure this IP
    // Input: 50MHz, Output c0: 50MHz, c1: 25MHz
    my_altpll pll_inst (
        .inclk0(clk_50),
        .c0(clk_50_camera),
        .c1(clk_25_vga)
    );
    
    // VGA controller
    VGA vga_inst (
        .CLK25(clk_25_vga),
        .clkout(vga_CLK),
        .Hsync(vga_hsync),
        .Vsync(vSync),
        .Nblank(nBlank),
        .Nsync(vga_sync_N),
        .activeArea(activeArea)
    );
    
    // OV7670 controller
    ov7670_controller camera_ctrl (
        .clk(clk_50_camera),
        .resend(resend),
        .config_finished(led_config_finished),
        .sioc(ov7670_sioc),
        .siod(ov7670_siod),
        .reset(ov7670_reset),
        .pwdn(ov7670_pwdn),
        .xclk(ov7670_xclk)
    );
    
    // OV7670 capture
    ov7670_capture capture_inst (
        .pclk(ov7670_pclk),
        .vsync(ov7670_vsync),
        .href(ov7670_href),
        .d(ov7670_data),
        .addr(wraddress),
        .dout(wrdata),
        .we(wren)
    );
    
    // Frame buffer - you'll need to configure this as dual-port RAM IP
    // Configuration: 76800 words x 12 bits (for 320x240)
    // Port A (write): wraddress[16:0], wrdata[11:0], wren, ov7670_pclk
    // Port B (read): rdaddress[16:0], rddata[11:0], clk_25_vga
    frame_buffer_ram buffer_inst (
        .data(wrdata),
        .wraddress(wraddress),
        .wrclock(ov7670_pclk),
        .wren(wren),
        .rdaddress(rdaddress),
        .rdclock(clk_25_vga),
        .q(rddata)
    );
    
    // Address generator for reading
    Address_Generator addr_gen (
        .CLK25(clk_25_vga),
        .enable(activeArea),
        .vsync(vSync),
        .address(rdaddress)
    );
    
endmodule