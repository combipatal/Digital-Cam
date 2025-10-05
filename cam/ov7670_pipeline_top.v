module ov7670_pipeline_top (
    input  wire        clk_50,
    input  wire        btn_resend_n,
    input  wire [1:0]  sw_mode,
    output wire        led_config_finished,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_blank_N,
    output wire        vga_sync_N,
    output wire        vga_clk,
    input  wire        ov7670_pclk,
    input  wire        ov7670_vsync,
    input  wire        ov7670_href,
    input  wire [7:0]  ov7670_data,
    output wire        ov7670_sioc,
    inout  wire        ov7670_siod,
    output wire        ov7670_pwdn,
    output wire        ov7670_reset,
    output wire        ov7670_xclk
);
    localparam [1:0] MODE_GRAY  = 2'b00;
    localparam [1:0] MODE_GAUSS = 2'b01;
    localparam [1:0] MODE_SOBEL = 2'b10;

    localparam [7:0] SOBEL_THRESHOLD = 8'd64;

    localparam integer GAUSS_LAT = 2;
    localparam integer SOBEL_EXTRA_LAT = 2;
    localparam integer PIPE_LATENCY = GAUSS_LAT * 2 + SOBEL_EXTRA_LAT; // 6
    localparam integer MEM_RD_LAT = 2;
    localparam integer TOTAL_DATA_LAT = PIPE_LATENCY + MEM_RD_LAT;     // 8
    localparam integer SYNC_DELAY = TOTAL_DATA_LAT;

    wire clk_24_camera;
    wire clk_25_vga;

    // Mode selection sampled in VGA domain
    reg [1:0] sw_mode_sync1 = 2'b00;
    reg [1:0] sw_mode_sync2 = 2'b00;
    always @(posedge clk_25_vga) begin
        sw_mode_sync1 <= sw_mode;
        sw_mode_sync2 <= sw_mode_sync1;
    end
    wire [1:0] mode_sel = sw_mode_sync2;

    // Resend button debounce (active-low)
    reg [19:0] btn_counter = 20'd0;
    reg        btn_pressed = 1'b0;
    reg        btn_pressed_prev = 1'b0;
    wire       btn_rising_edge;
    wire       resend;

    always @(posedge clk_50) begin
        if (!btn_resend_n) begin
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

    assign btn_rising_edge = btn_pressed & ~btn_pressed_prev;
    assign resend = btn_rising_edge;

    // First-frame detection (camera clock domain)
    reg first_frame_captured = 1'b0;
    reg vsync_prev_pclk = 1'b0;

    always @(posedge ov7670_pclk) begin
        vsync_prev_pclk <= ov7670_vsync;
        if (vsync_prev_pclk && !ov7670_vsync && !first_frame_captured)
            first_frame_captured <= 1'b1;
        if (resend)
            first_frame_captured <= 1'b0;
    end

    // Synchronize frame-ready into VGA domain
    reg frame_ready_sync1 = 1'b0;
    reg frame_ready_sync2 = 1'b0;

    always @(posedge clk_25_vga) begin
        frame_ready_sync1 <= first_frame_captured;
        frame_ready_sync2 <= frame_ready_sync1;
    end

    // Write-side capture signals
    wire [16:0] wraddress;
    wire [15:0] wrdata;
    wire        wren;

    wire [15:0] wraddress_ram1 = wraddress[15:0];
    wire [16:0] wraddr_sub     = wraddress - 17'd65000;
    wire [13:0] wraddress_ram2 = wraddr_sub[13:0];

    wire        wren_ram1 = wren && (wraddress < 17'd65000);
    wire        wren_ram2 = wren && (wraddress >= 17'd65000);

    wire [15:0] wrdata_ram1 = wrdata;
    wire [15:0] wrdata_ram2 = wrdata;

    // Read-side (VGA domain)
    wire [16:0] rdaddress;
    wire [15:0] rdaddress_ram1;
    wire [13:0] rdaddress_ram2;
    wire [15:0] rddata_ram1;
    wire [15:0] rddata_ram2;
    wire [15:0] rddata;

    wire        activeArea;
    wire        hsync_raw;
    wire        vsync_raw;
    wire        vga_blank_N_raw;
    wire        vga_sync_N_raw;

    // Align BRAM outputs with active window
    reg        activeArea_d1 = 1'b0;
    reg        activeArea_d2 = 1'b0;
    reg [16:0] rdaddress_d1 = 17'd0;
    reg [16:0] rdaddress_d2 = 17'd0;

    wire       active_rise = activeArea && !activeArea_d1;
    wire [16:0] rdaddress_pre = rdaddress;

    always @(posedge clk_25_vga) begin
        activeArea_d1 <= activeArea;
        activeArea_d2 <= activeArea_d1;
        rdaddress_d1  <= rdaddress_pre;
        rdaddress_d2  <= rdaddress_d1;
    end

    wire        activeArea_aligned = activeArea_d2;
    wire [16:0] rdaddress_aligned  = rdaddress_d2;

    assign rdaddress_ram1 = rdaddress_aligned[15:0];
    wire [16:0] rdaddr_sub = rdaddress_aligned - 17'd65000;
    assign rdaddress_ram2 = rdaddr_sub[13:0];

    assign rddata = (rdaddress_aligned >= 17'd65000) ? rddata_ram2 : rddata_ram1;

    // Sobel coordinate tracking (aligned domain)
    reg        active_aligned_prev = 1'b0;
    reg        vsync_prev_aligned = 1'b1;
    reg [8:0]  sobel_x = 9'd0;
    reg [7:0]  sobel_y = 8'd0;

    always @(posedge clk_25_vga) begin
        vsync_prev_aligned  <= vsync_raw;
        active_aligned_prev <= activeArea_aligned;
        if (!vsync_prev_aligned && vsync_raw)
            sobel_y <= 8'd0;
        if (activeArea_aligned && !active_aligned_prev)
            sobel_x <= 9'd0;
        else if (activeArea_aligned && sobel_x < 9'd319)
            sobel_x <= sobel_x + 1'b1;
        if (!activeArea_aligned && active_aligned_prev) begin
            if (sobel_y < 8'd239)
                sobel_y <= sobel_y + 1'b1;
        end
    end

    wire [16:0] sobel_addr_aligned = {sobel_y, sobel_x};

    // RGB565 -> RGB888 conversion
    wire [7:0] r_888 = {rddata[15:11], 3'b111};
    wire [7:0] g_888 = {rddata[10:5],  2'b11};
    wire [7:0] b_888 = {rddata[4:0],   3'b111};

    // Grayscale conversion
    wire [16:0] gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) +
                           (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) +
                           (b_888 << 4) + (b_888 << 3) + (b_888 << 1);
    wire [7:0] gray_value = activeArea_aligned ? gray_sum[16:8] : 8'd0;

    // Pipeline bookkeeping arrays
    reg [16:0] rdaddress_delayed [0:PIPE_LATENCY];
    reg        activeArea_delayed [0:PIPE_LATENCY];
    reg [7:0]  gray_value_delayed [0:PIPE_LATENCY];
    reg [7:0]  gauss1_value_delayed [0:PIPE_LATENCY];
    reg [7:0]  sobel_value_delayed [0:PIPE_LATENCY];
    reg        gauss1_ready_delayed [0:PIPE_LATENCY];
    reg        sobel_ready_delayed [0:PIPE_LATENCY];
    integer    i;

    wire [16:0] rdaddress_gauss2 = rdaddress_delayed[GAUSS_LAT];
    wire        activeArea_gauss2 = activeArea_delayed[GAUSS_LAT];

    // Gaussian filters (two passes)
    wire [7:0] gray_blur;
    wire       gauss1_ready;
    gaussian_3x3_gray8 gaussian_gray_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_value),
        .pixel_addr(rdaddress_aligned),
        .vsync(vsync_raw),
        .active_area(activeArea_aligned),
        .pixel_out(gray_blur),
        .filter_ready(gauss1_ready)
    );

    wire [7:0] gray_blur2;
    wire       gauss2_ready;
    gaussian_3x3_gray8 gaussian_gray2_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_blur),
        .pixel_addr(rdaddress_gauss2),
        .vsync(vsync_raw),
        .active_area(activeArea_gauss2),
        .pixel_out(gray_blur2),
        .filter_ready(gauss2_ready)
    );

    // Sobel on double-blurred grayscale
    wire [7:0] sobel_value;
    wire       sobel_ready;
    sobel_3x3_gray8 sobel_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_blur2),
        .pixel_addr(sobel_addr_aligned),
        .vsync(vsync_raw),
        .active_area(activeArea_aligned),
        .threshold(SOBEL_THRESHOLD),
        .pixel_out(sobel_value),
        .sobel_ready(sobel_ready)
    );

    wire line_end = !activeArea_aligned && activeArea_d1;

    always @(posedge clk_25_vga) begin
        if (vsync_raw == 1'b0 || line_end) begin
            for (i = 0; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= 17'd0;
                activeArea_delayed[i] <= 1'b0;
                gray_value_delayed[i] <= 8'd0;
                gauss1_value_delayed[i] <= 8'd0;
                sobel_value_delayed[i] <= 8'd0;
                gauss1_ready_delayed[i] <= 1'b0;
                sobel_ready_delayed[i] <= 1'b0;
            end
        end else begin
            rdaddress_delayed[0] <= rdaddress_aligned;
            activeArea_delayed[0] <= activeArea_aligned;
            gray_value_delayed[0] <= gray_value;
            gauss1_value_delayed[0] <= gauss1_ready ? gray_blur : 8'd0;
            sobel_value_delayed[0] <= (sobel_ready && gauss2_ready) ? sobel_value : 8'd0;
            gauss1_ready_delayed[0] <= gauss1_ready;
            sobel_ready_delayed[0] <= sobel_ready && gauss2_ready;
            for (i = 1; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= rdaddress_delayed[i-1];
                activeArea_delayed[i] <= activeArea_delayed[i-1];
                gray_value_delayed[i] <= gray_value_delayed[i-1];
                gauss1_value_delayed[i] <= gauss1_value_delayed[i-1];
                sobel_value_delayed[i] <= sobel_value_delayed[i-1];
                gauss1_ready_delayed[i] <= gauss1_ready_delayed[i-1];
                sobel_ready_delayed[i] <= sobel_ready_delayed[i-1];
            end
        end
    end

    wire [7:0] stage_gray  = activeArea_delayed[PIPE_LATENCY] ? gray_value_delayed[PIPE_LATENCY] : 8'd0;
    wire [7:0] stage_gauss = (activeArea_delayed[PIPE_LATENCY] && gauss1_ready_delayed[PIPE_LATENCY]) ? gauss1_value_delayed[PIPE_LATENCY] : 8'd0;
    wire [7:0] stage_sobel = (activeArea_delayed[PIPE_LATENCY] && sobel_ready_delayed[PIPE_LATENCY]) ? sobel_value_delayed[PIPE_LATENCY] : 8'd0;

    wire [7:0] final_pixel =
        (mode_sel == MODE_SOBEL) ? stage_sobel :
        (mode_sel == MODE_GAUSS) ? stage_gauss :
                                   stage_gray;

    // VGA enable once a full frame is captured
    reg vga_enable_reg = 1'b0;
    reg vsync_prev_display = 1'b1;
    always @(posedge clk_25_vga) begin
        vsync_prev_display <= vsync_raw;
        if (!frame_ready_sync2)
            vga_enable_reg <= 1'b0;
        else if (!vsync_prev_display && vsync_raw)
            vga_enable_reg <= 1'b1;
    end
    wire vga_enable = vga_enable_reg;

    // Line warm-up tracker (start on raw activeArea; force 0 for MEM_RD_LAT cycles)
    reg [TOTAL_DATA_LAT-1:0] line_valid_pipe = {TOTAL_DATA_LAT{1'b0}};
    reg [1:0] bram_settle_cnt = 2'd0; // force 0 for first 2 cycles (MEM_RD_LAT)
    wire line_start_raw = activeArea && !activeArea_d1;
    always @(posedge clk_25_vga) begin
        if (!vga_enable) begin
            line_valid_pipe <= {TOTAL_DATA_LAT{1'b0}};
            bram_settle_cnt <= 2'd0;
        end else if (line_start_raw) begin
            line_valid_pipe <= {TOTAL_DATA_LAT{1'b1}}; // 라인 시작에도 유효로 유지
            bram_settle_cnt <= 2'd0;
        end else if (activeArea) begin
            if (bram_settle_cnt < MEM_RD_LAT[1:0]) begin
                bram_settle_cnt <= bram_settle_cnt + 1'b1;
                line_valid_pipe <= {line_valid_pipe[TOTAL_DATA_LAT-2:0], 1'b0};
            end else begin
                line_valid_pipe <= {line_valid_pipe[TOTAL_DATA_LAT-2:0], 1'b1};
            end
        end else begin
            line_valid_pipe <= {TOTAL_DATA_LAT{1'b0}};
            bram_settle_cnt <= 2'd0;
        end
    end
    wire line_warm_ok = line_valid_pipe[TOTAL_DATA_LAT-1];

    // Final RGB outputs (black elsewhere)
    assign vga_r = (vga_enable && line_warm_ok) ? final_pixel : 8'h00;
    assign vga_g = (vga_enable && line_warm_ok) ? final_pixel : 8'h00;
    assign vga_b = (vga_enable && line_warm_ok) ? final_pixel : 8'h00;

    // Sync alignment to match data latency
    reg [SYNC_DELAY-1:0] hsync_delay_pipe = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY-1:0] vsync_delay_pipe = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY-1:0] nblank_delay_pipe = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY-1:0] nsync_delay_pipe = {SYNC_DELAY{1'b0}};

    always @(posedge clk_25_vga) begin
        hsync_delay_pipe  <= {hsync_delay_pipe[SYNC_DELAY-2:0], hsync_raw};
        vsync_delay_pipe  <= {vsync_delay_pipe[SYNC_DELAY-2:0], vsync_raw};
        nblank_delay_pipe <= {nblank_delay_pipe[SYNC_DELAY-2:0], vga_blank_N_raw};
        nsync_delay_pipe  <= {nsync_delay_pipe[SYNC_DELAY-2:0], vga_sync_N_raw};
    end

    assign vga_hsync   = hsync_delay_pipe[SYNC_DELAY-1];
    assign vga_vsync   = vsync_delay_pipe[SYNC_DELAY-1];
    assign vga_blank_N = nblank_delay_pipe[SYNC_DELAY-1];
    assign vga_sync_N  = nsync_delay_pipe[SYNC_DELAY-1];

    // PLL: generate 24MHz camera clock and 25MHz VGA clock
    my_altpll pll_inst (
        .inclk0(clk_50),
        .c0(clk_24_camera),
        .c1(clk_25_vga)
    );

    // OV7670 controller (I2C configuration + timing)
    ov7670_controller camera_ctrl (
        .clk_50(clk_50),
        .clk_24(clk_24_camera),
        .resend(resend),
        .config_finished(led_config_finished),
        .sioc(ov7670_sioc),
        .siod(ov7670_siod),
        .reset(ov7670_reset),
        .pwdn(ov7670_pwdn),
        .xclk(ov7670_xclk)
    );

    // OV7670 capture with 2x2 average -> 320x240
    ov7670_capture capture_inst (
        .pclk(ov7670_pclk),
        .vsync(ov7670_vsync),
        .href(ov7670_href),
        .d(ov7670_data),
        .addr(wraddress),
        .dout(wrdata),
        .we(wren)
    );

    // Frame buffers (65k + 16k words)
    frame_buffer_ram buffer_ram1 (
        .data(wrdata_ram1),
        .wraddress(wraddress_ram1),
        .wrclock(ov7670_pclk),
        .wren(wren_ram1),
        .rdaddress(rdaddress_ram1),
        .rdclock(clk_25_vga),
        .q(rddata_ram1)
    );

    frame_buffer_ram_11k buffer_ram2 (
        .data(wrdata_ram2),
        .wraddress(wraddress_ram2),
        .wrclock(ov7670_pclk),
        .wren(wren_ram2),
        .rdaddress(rdaddress_ram2),
        .rdclock(clk_25_vga),
        .q(rddata_ram2)
    );

    // VGA timing (640x480 with centered 320x240 active window)
    VGA vga_inst (
        .CLK25(clk_25_vga),
        .pixel_data(rddata),
        .clkout(vga_clk),
        .Hsync(hsync_raw),
        .Vsync(vsync_raw),
        .Nblank(vga_blank_N_raw),
        .Nsync(vga_sync_N_raw),
        .activeArea(activeArea),
        .pixel_address(rdaddress)
    );
endmodule
