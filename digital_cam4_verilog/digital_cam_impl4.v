// 디지털 캠 구현 #4 - 최상위 모듈
// OV7670 카메라 모듈, 프레임 버퍼, VGA 컨트롤러, 에지 검출 로직을 통합합니다.
// 스위치 입력에 따라 일반 비디오 모드 또는 실시간 에지 검출 모드로 동작합니다.

module digital_cam_impl4 (
    // --- Global Inputs ---
    input clk_50,
    input btn_RESET, // KEY0; 수동 리셋
    input slide_sw_resend_reg_values,
    input slide_sw_NORMAL_OR_EDGEDETECT,

    // --- VGA Outputs ---
    output vga_hsync,
    output vga_vsync,
    output [7:0] vga_r,
    output [7:0] vga_g,
    output [7:0] vga_b,
    output vga_blank_N,
    output vga_sync_N,
    output vga_CLK,

    // --- OV7670 Camera Interface ---
    input ov7670_pclk,
    output ov7670_xclk,
    input ov7670_vsync,
    input ov7670_href,
    input [7:0] ov7670_data,
    output ov7670_sioc,
    inout ov7670_siod,
    output ov7670_pwdn,
    output ov7670_reset,

    // --- Status LEDs ---
    output LED_config_finished,
    output LED_dll_locked,
    output LED_done
);

    // --- Clocking ---
    wire clk_25_vga, clk_50_camera,clk_133MHz;
    wire dll_locked;

    // PLL for camera and VGA clocks
    // 참고: my_altpll과 PLL_clk는 Altera/Intel FPGA의 IP입니다.
    // 시뮬레이션 또는 다른 벤더 툴 사용 시 해당 PLL 모델이 필요합니다.
    PLL_clk Inst_tw0_clocks_pll (
        .areset(~btn_RESET), // areset은 active-high
        .inclk0(clk_50),
        .c0(clk_50_camera),
        .c1(clk_25_vga),
        .locked(dll_locked)
    );
	 
	 my_altpll Inst_tw0_clocks_pll_1 (
        .areset(~btn_RESET), // areset은 active-high
        .inclk0(clk_50),
        .c0(clk_133MHz),
        .locked()
    );

    // --- Control & FSM ---
    wire reset_global = ~btn_RESET;
    wire normal_or_edgedetect; // Debounced switch
    
    debounce Inst_debounce_normal_or_edgedetect (
        .clk(clk_50), .reset(reset_global),
        .sw(slide_sw_NORMAL_OR_EDGEDETECT), .db(normal_or_edgedetect)
    );
    
    // FSM 상태 정의
    localparam S0_RESET = 0, S1_RESET_BW = 1, S2_PROCESS_BW = 2, S3_DONE_BW = 3,
               S4_RESET_ED = 4, S5_PROCESS_ED = 5, S6_DONE_ED = 6, S7_NORMAL_VIDEO_MODE = 7;
    reg [2:0] state_current, state_next;
    
    // --- Internal Signals ---
    wire done_BW, done_ED, done_capture_new_frame;
    wire activeArea, nBlank, vSync;
    
    // --- Frame Buffer 1 Signals ---
    reg wren_buf_1;
    reg [16:0] wraddress_buf_1;
    reg [11:0] wrdata_buf_1;
    reg [16:0] rdaddress_buf_1;
    wire [11:0] rddata_buf_1;
    // --- Frame Buffer 2 Signals ---
    reg wren_buf_2;
    reg [16:0] wraddress_buf_2;
    reg [11:0] wrdata_buf_2;
    reg [16:0] rdaddress_buf_2;
    wire [11:0] rddata_buf_2;

    // --- Muxed signals from components ---
    wire [16:0] rdaddress_buf12_from_addr_gen;
    wire [16:0] rdaddress_buf1_from_do_BW, wraddress_buf1_from_do_BW;
    wire [11:0] wrdata_buf1_from_do_BW;
    wire wren_buf1_from_do_BW;
    
    wire [16:0] rdaddress_buf1_from_do_ED, wraddress_buf2_from_do_ED;
    wire [11:0] wrdata_buf2_from_do_ED;
    wire wren_buf2_from_do_ED;

    wire [16:0] wraddress_buf1_from_ov7670_capture;
    wire [11:0] wrdata_buf1_from_ov7670_capture;
    wire wren_buf1_from_ov7670_capture;
    
    reg [11:0] data_to_rgb;

    // --- FSM Sequential Logic ---
    always @(posedge clk_25_vga or posedge reset_global) begin
        if (reset_global)
            state_current <= S0_RESET;
        else
            state_current <= state_next;
    end

    // --- FSM Combinatorial Logic & Muxing ---
    always @(*) begin
        // Default assignments
        state_next = state_current;
        
        // Default Mux settings for Normal Mode
        data_to_rgb = rddata_buf_1;
        wren_buf_1 = wren_buf1_from_ov7670_capture;
        wraddress_buf_1 = wraddress_buf1_from_ov7670_capture;
        wrdata_buf_1 = wrdata_buf1_from_ov7670_capture;
        rdaddress_buf_1 = rdaddress_buf12_from_addr_gen;
        wren_buf_2 = 1'b0; // Buf2 is not written in normal mode
        wraddress_buf_2 = 17'b0;
        wrdata_buf_2 = 12'b0;
        rdaddress_buf_2 = rdaddress_buf12_from_addr_gen;

        case (state_current)
            S0_RESET: begin
                if (normal_or_edgedetect) // Edge Detect Mode
                    state_next = S1_RESET_BW;
                else // Normal Mode
                    state_next = S7_NORMAL_VIDEO_MODE;
            end
            S1_RESET_BW: begin
                state_next = S2_PROCESS_BW;
            end
            S2_PROCESS_BW: begin
                // In BW process, read and write to buf1
                rdaddress_buf_1 = rdaddress_buf1_from_do_BW;
                wren_buf_1 = wren_buf1_from_do_BW;
                wraddress_buf_1 = wraddress_buf1_from_do_BW;
                wrdata_buf_1 = wrdata_buf1_from_do_BW;
                data_to_rgb = rddata_buf_2; // Show previous edge detected image
                if (done_BW)
                    state_next = S3_DONE_BW;
            end
            S3_DONE_BW: begin
                state_next = S4_RESET_ED;
            end
            S4_RESET_ED: begin
                state_next = S5_PROCESS_ED;
            end
            S5_PROCESS_ED: begin
                // In ED process, read from buf1, write to buf2
                rdaddress_buf_1 = rdaddress_buf1_from_do_ED;
                wren_buf_1 = 1'b0;
                wren_buf_2 = wren_buf2_from_do_ED;
                wraddress_buf_2 = wraddress_buf2_from_do_ED;
                wrdata_buf_2 = wrdata_buf2_from_do_ED;
                data_to_rgb = rddata_buf_2; // Show image being updated
                if (done_ED)
                    state_next = S6_DONE_ED;
            end
            S6_DONE_ED: begin
                state_next = S7_NORMAL_VIDEO_MODE;
            end
            S7_NORMAL_VIDEO_MODE: begin
                 if (normal_or_edgedetect) begin
                    data_to_rgb = rddata_buf_2; // Show last edge detected image
                    if (done_capture_new_frame) // Wait for a new frame to be captured in buf1
                        state_next = S0_RESET; // Then restart the process
                 end else begin
                    data_to_rgb = rddata_buf_1; // Normal video
                    state_next = S7_NORMAL_VIDEO_MODE;
                 end
            end
        endcase
    end
    
    // --- Component Instantiations ---
    // Frame Buffers
    frame_buffer Inst_frame_buf_1 (
			.rdaddress(rdaddress_buf_1), 
			.rdclock(clk_25_vga), 
			.q(rddata_buf_1), 
			.wrclock(ov7670_pclk), 
			.wraddress(wraddress_buf_1), 
			.data(wrdata_buf_1), 
			.wren(wren_buf_1)
			);
    frame_buffer Inst_frame_buf_2 (
			.rdaddress(rdaddress_buf_2), 
			.rdclock(clk_25_vga), 
			.q(rddata_buf_2), 
			.wrclock(clk_25_vga), 
			.wraddress(wraddress_buf_2), 
			.data(wrdata_buf_2), 
			.wren(wren_buf_2)
			);

    // Camera Controller & Capture
    ov7670_controller Inst_ov7670_controller (
			.clk(clk_50_camera), 
			.resend(slide_sw_resend_reg_values), 
			.config_finished(LED_config_finished), 
			.sioc(ov7670_sioc), 
			.siod(ov7670_siod), 
			.reset(ov7670_reset), 
			.pwdn(ov7670_pwdn), 
			.xclk(ov7670_xclk)
			);
    ov7670_capture Inst_ov7670_capture (
			.pclk(ov7670_pclk), 
			.vsync(ov7670_vsync), 
			.href(ov7670_href), 
			.d(ov7670_data), 
			.addr(wraddress_buf1_from_ov7670_capture), 
			.dout(wrdata_buf1_from_ov7670_capture), 
			.we(wren_buf1_from_ov7670_capture), 
			.end_of_frame(done_capture_new_frame)
			);

    // VGA and RGB conversion
    VGA Inst_VGA (
			.CLK25(clk_25_vga), 
			.clkout(vga_CLK), 
			.Hsync(vga_hsync), 
			.Vsync(vSync), 
			.Nblank(nBlank), 
			.Nsync(vga_sync_N), 
			.activeArea(activeArea)
			);
    assign vga_vsync = vSync;
    assign vga_blank_N = nBlank;
    RGB Inst_RGB (
			.Din(data_to_rgb), 
			.Nblank(activeArea), 
			.R(vga_r), 
			.G(vga_g), 
			.B(vga_b)
			);
    
    // Address Generator for reading frame buffers
    Address_Generator Inst_Address_Generator (
			.rst_i(reset_global), 
			.CLK25(clk_25_vga), 
			.enable(activeArea), 
			.vsync(vSync), 
			.address(rdaddress_buf12_from_addr_gen)
			);
    
    // Image Processing Modules
    wire call_black_white = (state_current == S2_PROCESS_BW);
    wire call_edge_detection = (state_current == S5_PROCESS_ED);
    
    do_black_white Inst_black_white (
			.rst_i(state_current == S1_RESET_BW || state_current == S3_DONE_BW), 
			.clk_i(clk_25_vga), 
			.enable_filter(call_black_white && ~vSync), 
			.led_done(done_BW), 
			.rdaddr_buf1(rdaddress_buf1_from_do_BW), 
			.din_buf1(rddata_buf_1), 
			.wraddr_buf1(wraddress_buf1_from_do_BW), 
			.dout_buf1(wrdata_buf1_from_do_BW), 
			.we_buf1(wren_buf1_from_do_BW)
			);
			
    do_edge_detection Inst_edge_detection (
			.rst_i(state_current == S4_RESET_ED || state_current == S6_DONE_ED), 
			.clk_i(clk_25_vga),
			.clk_133_i(clk_133MHz),
			.enable_sobel_filter(call_edge_detection && ~vSync), 
			.led_sobel_done(done_ED), 
			.rdaddr_buf1(rdaddress_buf1_from_do_ED), 
			.din_buf1(rddata_buf_1), 
			.wraddr_buf2(wraddress_buf2_from_do_ED), 
			.dout_buf2(wrdata_buf2_from_do_ED), 
			.we_buf2(wren_buf2_from_do_ED)
			);

    assign LED_dll_locked = dll_locked;
    assign LED_done = done_BW || done_ED;
endmodule
