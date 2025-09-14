// Top-level module for OV7670 camera interface
module digital_cam_top (
    input  wire        clk_50,
    input  wire        btn_resend,
    input  wire        sw_grayscale,  // SW[0] for grayscale mode
    input  wire        sw_sobel,      // SW[1] for sobel filter
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
    
    // Dual frame buffer signals
    wire [15:0] wraddress_ram1, rdaddress_ram1; // RAM1: 16-bit address (0-32767)
    wire [15:0] wraddress_ram2, rdaddress_ram2; // RAM2: 16-bit address (0-44031)
    wire [11:0] wrdata_ram1, wrdata_ram2;
    wire wren_ram1, wren_ram2;
    wire [11:0] rddata_ram1, rddata_ram2;
    
    // Button debouncing for camera reset
    reg [19:0] btn_counter = 20'd0;
    reg btn_pressed = 1'b0;
    reg btn_pressed_prev = 1'b0;
    wire btn_rising_edge;
    
    // Button debouncing logic
    always @(posedge clk_50) begin
        if (btn_resend == 1'b0) begin  // Button pressed (active low)
            if (btn_counter < 20'd1000000)  // 20ms debounce at 50MHz
                btn_counter <= btn_counter + 1'b1;
            else
                btn_pressed <= 1'b1;
        end else begin
            btn_counter <= 20'd0;
            btn_pressed <= 1'b0;
        end
        btn_pressed_prev <= btn_pressed;
    end
    
    assign btn_rising_edge = btn_pressed & ~btn_pressed_prev;
    
    // Assignments
    assign resend = btn_rising_edge;  // Send reset pulse on button press
    assign vga_vsync = vSync;
    assign vga_blank_N = nBlank;
    
    // Dual frame buffer for 320x240 = 76800 pixels
    // RAM1: addresses 0-32767 (first half) - 32K RAM
    // RAM2: addresses 32768-76799 (second half) - 44K RAM
    
    // Write address assignments
    assign wraddress_ram1 = wraddress[15:0];  // RAM1: 0-32767 (16-bit)
    assign wraddress_ram2 = wraddress[15:0] - 16'd32768;  // RAM2: 0-44031 (16-bit with offset)
    assign wrdata_ram1 = wrdata;
    assign wrdata_ram2 = wrdata;
    assign wren_ram1 = wren & ~wraddress[16];  // Write to RAM1 when address < 32768
    assign wren_ram2 = wren & wraddress[16];   // Write to RAM2 when address >= 32768
    
    // Read address assignments
    assign rdaddress_ram1 = rdaddress[15:0];  // RAM1: 0-32767 (16-bit)
    assign rdaddress_ram2 = rdaddress[15:0] - 16'd32768;  // RAM2: 0-44031 (16-bit with offset)
    
    // Read data multiplexing
    assign rddata = rdaddress[16] ? rddata_ram2 : rddata_ram1;
    
    // RGB conversion with grayscale and sobel filter modes
    wire [7:0] gray_value;
    wire [7:0] red_value, green_value, blue_value;
    wire [7:0] sobel_value;
    
    // Calculate grayscale value using shift operations
    // Y = (R + 2*G + B) >> 2 (equivalent to divide by 4)
    wire [7:0] r_ext, g_ext, b_ext;
    wire [8:0] gray_sum;
    
    assign r_ext = {rddata[11:8], 4'b0000};  // R extended to 8 bits
    assign g_ext = {rddata[7:4], 4'b0000};   // G extended to 8 bits  
    assign b_ext = {rddata[3:0], 4'b0000};   // B extended to 8 bits
    
    assign gray_sum = r_ext + g_ext + g_ext + b_ext;  // R + 2*G + B
    assign gray_value = activeArea ? gray_sum[8:2] : 8'h00;  // >> 2 (divide by 4)
    
    // Sobel edge detection filter
    // This is a simplified version - full implementation would need line buffers
    reg [7:0] prev_gray = 8'h00;
    wire [7:0] edge_magnitude;
    
    always @(posedge clk_25_vga) begin
        if (activeArea) begin
            prev_gray <= gray_value;
        end
    end
    
    // Simple edge detection: |current - previous|
    assign edge_magnitude = (gray_value > prev_gray) ? (gray_value - prev_gray) : (prev_gray - gray_value);
    assign sobel_value = activeArea ? edge_magnitude : 8'h00;
    
    // Color values
    assign red_value = activeArea ? {rddata[11:8], 4'b1111} : 8'h00;
    assign green_value = activeArea ? {rddata[7:4], 4'b1111} : 8'h00;
    assign blue_value = activeArea ? {rddata[3:0], 4'b1111} : 8'h00;
    
    // Output selection based on switches
    wire [7:0] final_r, final_g, final_b;
    assign final_r = sw_sobel ? sobel_value : (sw_grayscale ? gray_value : red_value);
    assign final_g = sw_sobel ? sobel_value : (sw_grayscale ? gray_value : green_value);
    assign final_b = sw_sobel ? sobel_value : (sw_grayscale ? gray_value : blue_value);
    
    assign vga_r = final_r;
    assign vga_g = final_g;
    assign vga_b = final_b;
    
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
    
    // Dual frame buffer RAMs - each configured for 32K x 12 bits
    // RAM1: stores first half of image (pixels 0-32767)
    frame_buffer_ram buffer_ram1 (
        .data(wrdata_ram1),
        .wraddress(wraddress_ram1),
        .wrclock(ov7670_pclk),
        .wren(wren_ram1),
        .rdaddress(rdaddress_ram1),
        .rdclock(clk_25_vga),
        .q(rddata_ram1)
    );
    
    // RAM2: stores second half of image (pixels 32768-76799)
    frame_buffer_ram buffer_ram2 (
        .data(wrdata_ram2),
        .wraddress(wraddress_ram2),
        .wrclock(ov7670_pclk),
        .wren(wren_ram2),
        .rdaddress(rdaddress_ram2),
        .rdclock(clk_25_vga),
        .q(rddata_ram2)
    );
    
    // Address generator for reading
    Address_Generator addr_gen (
        .CLK25(clk_25_vga),
        .enable(activeArea),
        .vsync(vSync),
        .address(rdaddress)
    );
    
endmodule