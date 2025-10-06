module digital_cam_top (
    input  wire        btn_thr_up,     // Sobel threshold increase button (active low)
    input  wire        btn_thr_down,   // Sobel threshold decrease button (active low)
    input  wire        clk_50,         // 50MHz system clock
    input  wire        btn_resend,     // Camera configuration restart button
    input  wire        sw_grayscale,   // SW[0] Grayscale mode switch
    input  wire        sw_sobel,       // SW[1] Sobel filter mode switch
    input  wire        sw_filter,      // SW[2] Digital filter mode switch
    output wire        led_config_finished,  // Configuration complete LED
    
    // VGA output signals
    output wire        vga_hsync,      // VGA horizontal sync
    output wire        vga_vsync,      // VGA vertical sync
    output wire [7:0]  vga_r,          // VGA red (8-bit)
    output wire [7:0]  vga_g,          // VGA green (8-bit)
    output wire [7:0]  vga_b,          // VGA blue (8-bit)
    output wire        vga_blank_N,    // VGA blanking signal
    output wire        vga_sync_N,     // VGA sync signal
    output wire        vga_CLK,        // VGA clock
    
    // OV7670 camera interface
    input  wire        ov7670_pclk,    // Camera pixel clock
    output wire        ov7670_xclk,    // Camera system clock
    input  wire        ov7670_vsync,   // Camera vertical sync
    input  wire        ov7670_href,    // Camera horizontal reference
    input  wire [7:0]  ov7670_data,    // Camera pixel data
    output wire        ov7670_sioc,    // Camera I2C clock
    inout  wire        ov7670_siod,    // Camera I2C data
    output wire        ov7670_pwdn,    // Camera power down
    output wire        ov7670_reset,   // Camera reset

    // SDRAM (external memory)
    output wire [12:0] dram_addr,
    output wire [1:0]  dram_ba,
    output wire        dram_cas_n,
    output wire        dram_cke,
    output wire        dram_clk,
    output wire        dram_cs_n,
    inout  wire [15:0] dram_dq,
    output wire [1:0]  dram_dqm,
    output wire        dram_ras_n,
    output wire        dram_we_n
);

    // ============================================================================
    // Parameters and constants
    // ============================================================================
    // Total pipeline latency from VGA address request to final pixel output.
    // This must account for: SDRAM read latency + FIFO latency + Image processing latency.
    // Start with a conservative value and tune if necessary.
    localparam integer PIPE_LATENCY = 20;
    
    // Path delay indices
    wire clk_24_camera;  // Camera 24MHz clock
    wire clk_25_vga;     // VGA 25MHz clock
    // SDRAM clock domain
    wire sdram_clk;
    wire sdram_clk_shift;
    wire sdram_pll_locked;

    // ============================================================================
    // Camera and memory signals
    // ============================================================================
    wire cam_wren;           // Camera write enable
    wire resend;             // Camera configuration restart signal
    wire [16:0] cam_wraddress; // Camera write address
    wire [15:0] cam_wrdata;    // Camera write data (RGB565)
    wire [16:0] vga_rdaddress; // VGA read address
    wire [15:0] vga_rddata;    // VGA read data (RGB565)
    wire vga_active_area;    // VGA active area

    // ============================================================================
    // VGA signals
    // ============================================================================
    wire hsync_raw, vsync_raw;
    wire vga_blank_N_raw;
    wire vga_sync_N_raw;
    wire vga_enable;         // VGA output enable signal

    // ============================================================================
    // Image processing signals
    // ============================================================================
    wire [7:0] gray_value;           // Grayscale value
    wire [7:0] red_value, green_value, blue_value;  // RGB values
    wire [7:0] sobel_value;          // Sobel filter value (grayscale)
    wire filter_ready;               // Filter processing complete signal
    wire sobel_ready;                // Sobel processing complete signal

    // Pipeline delay arrays
    reg [16:0] vga_rdaddress_delayed [PIPE_LATENCY:0];  // Address delay
    reg activeArea_delayed [PIPE_LATENCY:0];            // Active area delay
    reg [7:0] red_value_delayed [PIPE_LATENCY:0];       // Red delay
    reg [7:0] green_value_delayed [PIPE_LATENCY:0];     // Green delay
    reg [7:0] blue_value_delayed [PIPE_LATENCY:0];      // Blue delay
    reg [7:0] gray_value_delayed [PIPE_LATENCY:0];      // Grayscale delay
    reg [7:0] sobel_value_delayed [PIPE_LATENCY:0];     // Sobel delay
    reg filter_ready_delayed [PIPE_LATENCY:0];          // Filter ready delay
    reg sobel_ready_delayed [PIPE_LATENCY:0];           // Sobel ready delay

    // ============================================================================
    // Button and control logic
    // ============================================================================
    // Camera reset button debouncing
    reg [19:0] btn_counter = 20'd0;
    reg btn_pressed = 1'b0;
    reg btn_pressed_prev = 1'b0;
    wire btn_rising_edge;

    // Sobel threshold control button debouncing
    reg [19:0] up_cnt = 20'd0;
    reg [19:0] down_cnt = 20'd0;
    reg up_stable = 1'b0, up_prev = 1'b0;
    reg down_stable = 1'b0, down_prev = 1'b0;
    wire up_pulse, down_pulse;

    // Sobel threshold
    reg [7:0] sobel_threshold_btn = 8'd64;

    // ============================================================================
    // Memory delay correction logic
    // ============================================================================
    reg activeArea_d1 = 1'b0, activeArea_d2 = 1'b0, activeArea_d3 = 1'b0, activeArea_d4 = 1'b0;
    reg [16:0] rdaddress_d1 = 17'd0, rdaddress_d2 = 17'd0, rdaddress_d3 = 17'd0, rdaddress_d4 = 17'd0;

    // ============================================================================
    // Button debouncing logic
    // ============================================================================
    // Camera reset button
    always @(posedge clk_50) begin
        if (btn_resend == 1'b0) begin
            if (btn_counter < 20'd1000000)
                btn_counter <= btn_counter + 1'b1;
            else
                btn_pressed <= 1'b1;
        end else begin
            btn_counter <= 20'd0;
            btn_pressed <= 1'b0;
        end
        btn_pressed_prev <= btn_pressed;
    end

    // Sobel threshold button
    always @(posedge clk_50) begin
        // UP button
        if (btn_thr_up == 1'b0) begin
            if (up_cnt < 20'd1000000) up_cnt <= up_cnt + 1'b1; else up_stable <= 1'b1;
        end else begin
            up_cnt <= 20'd0; up_stable <= 1'b0;
        end
        up_prev <= up_stable;
        
        // DOWN button
        if (btn_thr_down == 1'b0) begin
            if (down_cnt < 20'd1000000) down_cnt <= down_cnt + 1'b1; else down_stable <= 1'b1;
        end else begin
            down_cnt <= 20'd0; down_stable <= 1'b0;
        end
        down_prev <= down_stable;
    end

    // Sobel threshold adjustment
    always @(posedge clk_50) begin
        if (up_pulse)   sobel_threshold_btn <= (sobel_threshold_btn >= 8'd250) ? 8'd255 : (sobel_threshold_btn + 8'd5);
        if (down_pulse) sobel_threshold_btn <= (sobel_threshold_btn <= 8'd5)   ? 8'd0   : (sobel_threshold_btn - 8'd5);
    end

    // ============================================================================
    // Pipeline alignment
    // ============================================================================
    integer i;
    always @(posedge clk_25_vga) begin
        if (vsync_raw == 1'b0) begin
            // Frame start: clear all delay registers
            for (i = 0; i <= PIPE_LATENCY; i = i + 1) begin
                vga_rdaddress_delayed[i] <= 17'd0;
                activeArea_delayed[i] <= 1'b0;
                red_value_delayed[i] <= 8'd0;
                green_value_delayed[i] <= 8'd0;
                blue_value_delayed[i] <= 8'd0;
                gray_value_delayed[i] <= 8'd0;
                sobel_value_delayed[i] <= 8'd0;
                filter_ready_delayed[i] <= 1'b0;
                sobel_ready_delayed[i] <= 1'b0;
            end
        end else begin
            // Stage 0: Latch raw signals from VGA controller and memory
            vga_rdaddress_delayed[0] <= vga_rdaddress;
            activeArea_delayed[0] <= vga_active_area;
            red_value_delayed[0] <= red_value;
            green_value_delayed[0] <= green_value;
            blue_value_delayed[0] <= blue_value;
            gray_value_delayed[0] <= gray_value;
            sobel_value_delayed[0] <= sobel_value;
            filter_ready_delayed[0] <= filter_ready;
            sobel_ready_delayed[0] <= sobel_ready;
            
            // Stage 1-PIPE_LATENCY delay chain
            for (i = 1; i <= PIPE_LATENCY; i = i + 1) begin
                vga_rdaddress_delayed[i] <= vga_rdaddress_delayed[i-1];
                activeArea_delayed[i] <= activeArea_delayed[i-1];
                red_value_delayed[i] <= red_value_delayed[i-1];
                green_value_delayed[i] <= green_value_delayed[i-1];
                blue_value_delayed[i] <= blue_value_delayed[i-1];
                gray_value_delayed[i] <= gray_value_delayed[i-1];
                sobel_value_delayed[i] <= sobel_value_delayed[i-1];
                filter_ready_delayed[i] <= filter_ready_delayed[i-1];
                sobel_ready_delayed[i] <= sobel_ready_delayed[i-1];
            end
        end
    end

    // ============================================================================
    // Signal connection and data conversion
    // ============================================================================
    // Button signals
    assign btn_rising_edge = btn_pressed & ~btn_pressed_prev;
    assign resend = btn_rising_edge;
    assign up_pulse = up_stable & ~up_prev;
    assign down_pulse = down_stable & ~down_prev;
    assign vga_enable = 1'b1; // Output is always enabled, framebuffer handles blanking.

    // RGB565 → RGB888 conversion
    wire [7:0] r_888, g_888, b_888;
    assign r_888 = {vga_rddata[15:11], vga_rddata[15:13]}; // Stretch 5 bits to 8
    assign g_888 = {vga_rddata[10:5],  vga_rddata[10:9]};  // Stretch 6 bits to 8
    assign b_888 = {vga_rddata[4:0],   vga_rddata[4:2]};   // Stretch 5 bits to 8

    // RGB888 combined into single 24-bit pixel
    wire [23:0] rgb888_pixel = {r_888, g_888, b_888};

    // Grayscale calculation
    wire [16:0] gray_sum;
    assign gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) +
                     (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) +
                     (b_888 << 4) + (b_888 << 3) + (b_888 << 1);
    assign gray_value = vga_active_area ? gray_sum[16:8] : 8'h00;

    // Color values
    assign red_value = vga_active_area ? r_888 : 8'h00;
    assign green_value = vga_active_area ? g_888 : 8'h00;
    assign blue_value = vga_active_area ? b_888 : 8'h00;

    // ============================================================================
    // Image processing module instances
    // ============================================================================
    // First Gaussian blur
    wire [7:0] gray_blur;
    // gaussian_3x3_gray8 gaussian_gray_inst (
    //     .clk(clk_25_vga),
    //     .enable(1'b1),
    //     .pixel_in(gray_value),
    //     .pixel_addr(rdaddress_aligned),
    //     .vsync(vsync_raw),
    //     .active_area(activeArea_aligned),
    //     .pixel_out(gray_blur),
    //     .filter_ready(filter_ready)
    // );

    // // Second Gaussian blur removed (using only first Gaussian)

    // // Sobel edge detection (timing aligned with first Gaussian)
    // wire [16:0] rdaddress_gauss = rdaddress_delayed[GAUSS_LAT];
    // wire activeArea_gauss = activeArea_delayed[GAUSS_LAT];
    // sobel_3x3_gray8 sobel_inst (
    //     .clk(clk_25_vga),
    //     .enable(1'b1),
    //     .pixel_in(gray_blur),  // First Gaussian output
    //     .pixel_addr(rdaddress_gauss),  // Gaussian delay aligned address
    //     .vsync(vsync_raw),
    //     .active_area(activeArea_gauss),  // Gaussian delay aligned active area
    //     .threshold(sobel_threshold_btn),
    //     .pixel_out(sobel_value),
    //     .sobel_ready(sobel_ready)
    // );

    // ============================================================================
    // Output selection and VGA connection
    // ============================================================================
    // Final output selection - now using PIPE_LATENCY to select the fully delayed signals
    wire [7:0] sel_orig_r = activeArea_delayed[PIPE_LATENCY] ? red_value_delayed[PIPE_LATENCY] : 8'h00;
    wire [7:0] sel_orig_g = activeArea_delayed[PIPE_LATENCY] ? green_value_delayed[PIPE_LATENCY] : 8'h00;
    wire [7:0] sel_orig_b = activeArea_delayed[PIPE_LATENCY] ? blue_value_delayed[PIPE_LATENCY] : 8'h00;
    wire [7:0] sel_gray = activeArea_delayed[PIPE_LATENCY] ? gray_value_delayed[PIPE_LATENCY] : 8'h00;
    wire [7:0] sel_sobel = (activeArea_delayed[PIPE_LATENCY] && sobel_ready_delayed[PIPE_LATENCY]) ? sobel_value_delayed[PIPE_LATENCY] : 8'h00;

    // Switch logic
    wire [7:0] final_r, final_g, final_b;
    assign final_r = sw_sobel ? sel_sobel : (sw_grayscale ? sel_gray : sel_orig_r);
    assign final_g = sw_sobel ? sel_sobel : (sw_grayscale ? sel_gray : sel_orig_g);
    assign final_b = sw_sobel ? sel_sobel : (sw_grayscale ? sel_gray : sel_orig_b);

    // VGA output
    assign vga_r = (vga_enable && activeArea_delayed[PIPE_LATENCY]) ? final_r : 8'h00;
    assign vga_g = (vga_enable && activeArea_delayed[PIPE_LATENCY]) ? final_g : 8'h00;
    assign vga_b = (vga_enable && activeArea_delayed[PIPE_LATENCY]) ? final_b : 8'h00;

    // ============================================================================
    // External module instances
    // ============================================================================
    // PLL instance
    my_altpll pll_inst (
        .inclk0(clk_50),
        .c0(clk_24_camera),
        .c1(clk_25_vga)
    );

    // SDRAM PLL
    SDRAM_CLK sdram_pll_inst (
        .inclk0(clk_50),
        .c0(sdram_clk),
        .c1(sdram_clk_shift),
        .locked(sdram_pll_locked)
    );

    // VGA controller
    VGA vga_inst (
        .CLK25(clk_25_vga), 
        .pixel_data(16'b0), // Not used, address generation only
        .clkout(vga_CLK),
        .Hsync(hsync_raw), 
        .Vsync(vsync_raw),
        .Nblank(vga_blank_N_raw), 
        .Nsync(vga_sync_N_raw),
        .activeArea(vga_active_area), 
        .pixel_address(vga_rdaddress)
    );

    // VGA output signals
    assign vga_hsync = hsync_raw;
    assign vga_vsync = vsync_raw;
    assign vga_blank_N = vga_blank_N_raw;
    assign vga_sync_N = vga_sync_N_raw;

    // OV7670 camera controller
    ov7670_controller camera_ctrl (
        .clk_50(clk_50),
        .clk_24(clk_24_camera),
        .resend(btn_pressed), // Use the debounced level signal
        .config_finished(led_config_finished),
        .sioc(ov7670_sioc),
        .siod(ov7670_siod),
        .reset(ov7670_reset),
        .pwdn(ov7670_pwdn),
        .xclk(ov7670_xclk)
    );

    // OV7670 capture module
    ov7670_capture capture_inst (
        .pclk(ov7670_pclk),
        .vsync(ov7670_vsync),
        .href(ov7670_href),
        .d(ov7670_data),
        .addr(cam_wraddress),
        .dout(cam_wrdata),
        .we(cam_wren)
    );

    // SDRAM frame buffer
    sdram_framebuffer #(
        .FRAME_WIDTH(320),
        .FRAME_HEIGHT(240)
    ) framebuffer_sdram (
        .reset_n(sdram_pll_locked & ~btn_pressed), // Correct active-low reset
        .bist_enable(1'b0), // Disable BIST for camera input
        .cam_clk(ov7670_pclk),
        .cam_vsync(ov7670_vsync),
        .cam_we(cam_wren),
        .cam_data(cam_wrdata),
        .vga_clk(clk_25_vga),
        .vga_vsync(vsync_raw),
        .vga_addr_req(vga_rdaddress),
        .vga_data(vga_rddata),
        .sdram_clk(sdram_clk),
        .sdram_clk_out(sdram_clk_shift),
        .sdram_addr(dram_addr),
        .sdram_ba(dram_ba),
        .sdram_cas_n(dram_cas_n),
        .sdram_cke(dram_cke),
        .sdram_clk_pin(sdram_clk_shift), // CRITICAL FIX: Connect the phase-shifted clock to the pin
        .sdram_cs_n(dram_cs_n),
        .sdram_dq(dram_dq),
        .sdram_dqm(dram_dqm),
        .sdram_ras_n(dram_ras_n),
        .sdram_we_n(dram_we_n)
    );


endmodule