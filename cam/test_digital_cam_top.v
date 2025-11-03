module test_digital_cam_top (
    input  wire        clk_50MHz,         // 50MHz 시스템 클럭
    //input  wire        btn_resend,     // 카메라 설정 재시작 버튼
    //input  wire        ir_rx,           // IR 수신기 입력
    
    // OV7670 카메라 인터페이스
    input  wire        clk_25MHz,    // 카메라 픽셀 클럭
    // output wire        ov7670_xclk,    // 카메라 시스템 클럭
    // input  wire        ov7670_vsync,   // 카메라 수직 동기화
    // input  wire        ov7670_href,    // 카메라 수평 참조
    // input  wire [7:0]  ov7670_data,    // 카메라 픽셀 데이터
    // output wire        ov7670_sioc,    // 카메라 I2C 클럭
    // inout  wire        ov7670_siod,    // 카메라 I2C 데이터
    // output wire        ov7670_pwdn,    // 카메라 파워다운
    // output wire        ov7670_reset    // 카메라 리셋,

    input  wire        wren,               // RAM 쓰기 활성화
    input  wire [16:0] wraddress,          // RAM 쓰기 주소
    input  wire [15:0] wrdata,             // RAM 쓰기 데이터 (RGB565)
    // input [16:0] rdaddress,   // RAM 읽기 주소 (VGA에서 생성)
    // input [15:0] rddata,      // RAM 읽기 데이터 (RGB565)

    input  wire [2:0]  active_filter_mode,
    output wire        vga_enable,         // VGA 출력 활성화 신호 노출
    output wire        pixel_valid,        // 파이프라인 정렬된 활성 영역 플래그
    output wire [7:0]  sobel_value,        // 소벨 필터 값 (그레이스케일)
    output wire        sobel_ready,        // 소벨 결과 유효 플래그
    output wire [7:0]  gaussian_value,     // 가우시안 필터 결과 (그레이스케일)
    output wire        gaussian_ready,     // 가우시안 결과 유효 플래그
    output wire [7:0]  canny_value,        // 캐니 필터 결과 (이진)
    output wire        canny_ready         // 캐니 결과 유효 플래그
);

    // ============================================================================
    // 파라미터 및 상수 정의
    // ============================================================================
    localparam integer MEM_RD_LAT = 2;           // 메모리 읽기 지연
    localparam integer GAUSS_LAT = 2;             // 가우시안 필터 지연
    localparam integer SOBEL_LAT = 5;       // 소벨 실제 지연 (3x3 윈도우 + 그래디언트 + 크기 + 임계값)
    localparam integer PIPE_LATENCY = GAUSS_LAT + SOBEL_LAT; // 7클럭 (가우시안 + 소벨)
    
    // 경로별 지연은 현재 모두 PIPE_LATENCY(7클럭)로 동일하게 사용

    // ============================================================================
    // 클럭 및 기본 신호
    // ============================================================================
    // wire clk_24_camera;  // 카메라용 24MHz 클럭
    // wire clk_25MHz;     // VGA용 25MHz 클럭

    // ============================================================================
    // 카메라 및 메모리 신호
    // ============================================================================

    wire activeArea;         // VGA 활성 영역

    // 듀얼 프레임 버퍼 신호들 (320x240 = 76800 픽셀을 두 개의 RAM으로 분할)
    wire [15:0] wraddress_ram1, rdaddress_ram1; // RAM1: 16비트 주소 (0-32767)
    wire [15:0] wraddress_ram2, rdaddress_ram2; // RAM2: 16비트 주소 (0-44031)
    wire [15:0] wrdata_ram1, wrdata_ram2;       // 각 RAM의 쓰기 데이터 (RGB565)
    wire wren_ram1, wren_ram2;                  // 각 RAM의 쓰기 활성화
    wire [15:0] rddata_ram1, rddata_ram2;       // 각 RAM의 읽기 데이터 (RGB565)

    wire [16:0] rdaddress;
    wire [15:0] rddata;

    // ============================================================================
    // VGA 신호
    // ============================================================================
    wire vsync_raw;
    //wire vga_enable;         // VGA 출력 활성화 신호
    // VGA 즉시 출력 신호를 2클럭 지연시키기 위한 레지스터들 (파이프라인 기준 d2)
    reg [16:0] rdaddress_d1, rdaddress_d2;
    reg activeArea_d1, activeArea_d2;

    // ============================================================================
    // 이미지 처리 신호
    // ============================================================================
    wire [7:0] gray_value;           // 그레이스케일 값
    wire [7:0] gray_blur;            // 가우시안 필터 출력
    //wire [7:0] sobel_value;          // 소벨 필터 값 (그레이스케일)
    wire filter_ready;               // 필터 처리 완료 신호

    // Color Tracking Signals
    wire [7:0] h_out, s_out, v_out;
    wire hsv_valid;
    wire color_track_out;
    wire color_track_valid;
    reg color_track_out_d1;

    // Reset signal for VGA domain (active low)
    wire rst_n_vga_domain = 1'b1;  // 항상 활성화 (리셋 해제)

    // 파이프라인 지연 배열
    reg [16:0] rdaddress_delayed [PIPE_LATENCY:0];      // 주소 지연
    reg activeArea_delayed [PIPE_LATENCY:0];            // 활성 영역 지연
    reg [15:0] rddata_delayed [PIPE_LATENCY:0];         // RGB565 픽셀 데이터 지연
    reg [7:0] gray_value_delayed [PIPE_LATENCY:0];      // 그레이스케일 지연
    reg [7:0] gray_blur_delayed [PIPE_LATENCY:0];       // 가우시안 필터 결과 지연
    reg gaussian_ready_delayed [PIPE_LATENCY:0];        // 가우시안 유효 신호 지연
    reg [15:0] rddata_bg_delayed [PIPE_LATENCY:0];      // 배경 픽셀 데이터 지연
    reg bg_load_active_delayed [PIPE_LATENCY:0];        // 배경 로드 신호 지연
    reg adaptive_flag_delayed [PIPE_LATENCY:0];
    wire  bg_load_active;

    // ============================================================================
    // 버튼 및 제어 로직
    // ============================================================================
    // 카메라 리셋용 버튼 디바운싱
    // reg [19:0] btn_counter = 20'd0;
    // reg btn_pressed = 1'b0;
    // reg btn_pressed_prev = 1'b0;
    // wire btn_rising_edge;

    // IR Control Logic
    // Key Codes
    localparam KEY_A    = 8'h0F;
    localparam KEY_B    = 8'h13;
    localparam KEY_C    = 8'h10;
    localparam KEY_1    = 8'h01; // Red
    localparam KEY_2    = 8'h02; // Green
    localparam KEY_3    = 8'h03; // Blue
    localparam KEY_UP   = 8'h1A;
    localparam KEY_DOWN = 8'h1E;
    localparam KEY_ORIG = 8'h12; 
    localparam KEY_BG_MODE    = 8'h04;
    localparam KEY_BG_THR_UP  = 8'h1B; 
    localparam KEY_BG_THR_DOWN= 8'h1F;

    // Filter mode state register
    localparam MODE_ORIG  = 3'd0;
    localparam MODE_GRAY  = 3'd1;
    localparam MODE_SOBEL = 3'd2;
    localparam MODE_CANNY = 3'd3;
    localparam MODE_COLOR = 3'd4;
    localparam MODE_BG_SUB = 3'd5; 
    localparam MODE_GAUSS = 3'd6;

    //reg [2:0] active_filter_mode = MODE_ORIG;
    reg [1:0] color_track_select = 2'b00; // 00:Red, 01:Green, 10:Blue

    // Background subtraction threshold, adjustable via IR remote
    reg [8:0] bg_sub_threshold_btn = 9'd40;

    // Adaptive background signals
    wire        adaptive_fg_flag;
    wire [7:0]  rddata_bg;
    wire [7:0]  rddata_bg_ram1, rddata_bg_ram2;
    wire [16:0] bg_wr_addr;
    wire [7:0]  bg_wr_data;
    wire        bg_wr_en;
    wire [15:0] bg_wraddress_ram1;
    wire [15:0] bg_wraddress_ram2;
    wire        wren_bg_ram1, wren_bg_ram2;

    // IR Receiver outputs
    // wire [7:0] ir_code;
    // wire ir_valid;
    //wire rst_n_50m;

    // IR command pulses
    // reg ir_up_pulse = 1'b0;
    // reg ir_down_pulse = 1'b0;
    // reg ir_bg_thr_up_pulse = 1'b0;
    // reg ir_bg_thr_down_pulse = 1'b0;

   // assign rst_n_50m = ~btn_pressed; // Active low reset from debounced button

    // // Instantiate IR Receiver
    // IR_RECEVER ir_inst (
    //     .clk(clk_50MHz),
    //     .rst_n(rst_n_50m),
    //     .IRDA_RXD(ir_rx),
    //     .captured_code(ir_code),
    //     .data_valid(ir_valid)
    // );

    // IR Command Decoder
    // always @(posedge clk_50MHz) begin
    //     // Pulses are active for one cycle
    //     ir_up_pulse <= 1'b0;
    //     ir_down_pulse <= 1'b0;
    //     ir_bg_thr_up_pulse <= 1'b0;
    //     ir_bg_thr_down_pulse <= 1'b0;

    //     if (ir_valid) begin
    //         case (ir_code)
    //             KEY_A:    active_filter_mode <= MODE_GRAY;
    //             KEY_B:    active_filter_mode <= MODE_SOBEL;
    //             KEY_C:    active_filter_mode <= MODE_CANNY;
    //             KEY_1:    begin active_filter_mode <= MODE_COLOR; color_track_select <= 2'b00; end // Red
    //             KEY_2:    begin active_filter_mode <= MODE_COLOR; color_track_select <= 2'b01; end // Green
    //             KEY_3:    begin active_filter_mode <= MODE_COLOR; color_track_select <= 2'b10; end // Blue
    //             KEY_ORIG: active_filter_mode <= MODE_ORIG;
    //             KEY_UP:   ir_up_pulse <= 1'b1;
    //             KEY_DOWN: ir_down_pulse <= 1'b1;
    //             KEY_BG_MODE:    active_filter_mode <= MODE_BG_SUB;
    //             KEY_BG_THR_UP:  ir_bg_thr_up_pulse <= 1'b1;
    //             KEY_BG_THR_DOWN:ir_bg_thr_down_pulse <= 1'b1;
    //             default:  ; // Do nothing for other keys
    //         endcase
    //     end
    // end

    // Sobel 임계값
    reg [7:0] sobel_threshold_btn = 8'd64;

    // 캐니 임계값
    reg [7:0] canny_thr_low = 8'd24;
    reg [7:0] canny_thr_high = 8'd64;

    // ============================================================================
    // 프레임 제어 로직
    // ============================================================================
    // reg first_frame_captured = 1'b0;  // 첫 프레임 캡처 완료 플래그
    // reg vsync_prev_pclk = 1'b0;       // vsync 이전 값 (pclk 도메인)
    reg frame_ready_sync1 = 1'b0;
    reg frame_ready_sync2 = 1'b0;
    reg vga_enable_reg = 1'b0;
    reg vsync_prev_display = 1'b1;

    // ============================================================================
    // 버튼 디바운싱 로직
    // ============================================================================
    // 카메라 리셋 버튼
    // always @(posedge clk_50MHz) begin
    //     if (btn_resend == 1'b0) begin
    //         if (btn_counter < 20'd1000000)
    //             btn_counter <= btn_counter + 1'b1;
    //         else
    //             btn_pressed <= 1'b1;
    //     end else begin
    //         btn_counter <= 20'd0;
    //         btn_pressed <= 1'b0;
    //     end
    //     btn_pressed_prev <= btn_pressed;
    // end

    // Sobel & Background Subtraction Threshold Adjustment
    // always @(posedge clk_50MHz) begin
    //     // Sobel
    //     if (ir_up_pulse)   sobel_threshold_btn <= (sobel_threshold_btn >= 8'd250) ? 8'd255 : (sobel_threshold_btn + 8'd5);
    //     if (ir_down_pulse) sobel_threshold_btn <= (sobel_threshold_btn <= 8'd5)   ? 8'd0   : (sobel_threshold_btn - 8'd5);
    //     // Background Subtraction
    //     if (ir_bg_thr_up_pulse)   bg_sub_threshold_btn <= (bg_sub_threshold_btn >= 9'd255) ? 9'd255 : (bg_sub_threshold_btn + 9'd5);
    //     if (ir_bg_thr_down_pulse) bg_sub_threshold_btn <= (bg_sub_threshold_btn <= 9'd5)   ? 9'd0   : (bg_sub_threshold_btn - 9'd5);
    // end

    // ============================================================================
    // 프레임 제어 로직
    // ============================================================================
    // 첫 프레임 완료 감지 (캡처 클럭 도메인)
    // always @(posedge clk_25MHz) begin
    //     vsync_prev_pclk <= ov7670_vsync;
    //     if (vsync_prev_pclk && !ov7670_vsync && !first_frame_captured) begin
    //         first_frame_captured <= 1'b1;
    //     end
    //     if (resend) begin
    //         first_frame_captured <= 1'b0;
    //     end
    // end

    wire first_frame_captured = 1'b1;
    // CDC 동기화: pclk → clk_25MHz
    always @(posedge clk_25MHz) begin
        frame_ready_sync1 <= first_frame_captured;
        frame_ready_sync2 <= frame_ready_sync1;
    end
    
    // VGA 출력 활성화
    always @(posedge clk_25MHz) begin
        vsync_prev_display <= vsync_raw;
        if (!frame_ready_sync2) begin
            vga_enable_reg <= 1'b0;
        end else if (!vsync_prev_display && vsync_raw) begin
            vga_enable_reg <= 1'b1;
        end
    end

    // ============================================================================
    // 파이프라인 기준 신호 2클럭 지연 생성 (RAM 읽기 지연 보상용 d2)
    // ============================================================================
    always @(posedge clk_25MHz) begin
        rdaddress_d1 <= rdaddress;
        rdaddress_d2 <= rdaddress_d1;
        activeArea_d1 <= activeArea;
        activeArea_d2 <= activeArea_d1;
    end

    // ============================================================================
    // 파이프라인 정렬
    // ============================================================================
    integer i;
        always @(posedge clk_25MHz) begin  // Delay for color tracker output to align with main pipeline
            color_track_out_d1 <= color_track_out;
    
            if (vsync_raw == 1'b0) begin
                // 프레임 시작 시 모든 지연 레지스터 클리어
                for (i = 0; i <= PIPE_LATENCY; i = i + 1) begin
                    rdaddress_delayed[i] <= 17'd0;
                    activeArea_delayed[i] <= 1'b0;
                    rddata_delayed[i] <= 16'd0;
                    gray_value_delayed[i] <= 8'd0;
                    gray_blur_delayed[i] <= 8'd0;
                    gaussian_ready_delayed[i] <= 1'b0;
                    adaptive_flag_delayed[i] <= 1'b0;
                    rddata_bg_delayed[i] <= 8'd0;
                    bg_load_active_delayed[i] <= 1'b0;
                end
            end else begin
                // 0단계 (정렬 기준 d2)
                rdaddress_delayed[0] <= rdaddress_d2;
                activeArea_delayed[0] <= activeArea_d2;
                rddata_delayed[0] <= rddata;
                gray_value_delayed[0] <= gray_value;
                gray_blur_delayed[0] <= gray_blur;
                gaussian_ready_delayed[0] <= filter_ready;
                adaptive_flag_delayed[0] <= adaptive_fg_flag;
                rddata_bg_delayed[0] <= rddata_bg;
                bg_load_active_delayed[0] <= bg_load_active;
                
                // 1-PIPE_LATENCY 단계 지연 체인
                for (i = 1; i <= PIPE_LATENCY; i = i + 1) begin
                    rdaddress_delayed[i] <= rdaddress_delayed[i-1];
                    activeArea_delayed[i] <= activeArea_delayed[i-1];
                    rddata_delayed[i] <= rddata_delayed[i-1];
                    gray_value_delayed[i] <= gray_value_delayed[i-1];
                    gray_blur_delayed[i] <= gray_blur_delayed[i-1];
                    gaussian_ready_delayed[i] <= gaussian_ready_delayed[i-1];
                    adaptive_flag_delayed[i] <= adaptive_flag_delayed[i-1];
                    rddata_bg_delayed[i] <= rddata_bg_delayed[i-1];
                    bg_load_active_delayed[i] <= bg_load_active_delayed[i-1];
                end

            end
        end

    // ============================================================================
    // 신호 연결 및 데이터 변환
    // ============================================================================
    // 정렬된 신호 (RAM 2클럭 반영 후)
    wire activeArea_aligned = activeArea_d2; 
    wire [16:0] rdaddress_aligned = rdaddress_d2;

    // 버튼 신호
    // assign btn_rising_edge = btn_pressed & ~btn_pressed_prev;
    // assign resend = btn_rising_edge;

    assign vga_enable = vga_enable_reg;
    assign pixel_valid = activeArea_delayed[PIPE_LATENCY];

    // 메모리 주소 할당
    assign wraddress_ram1 = wraddress[15:0];
    wire [16:0] wraddr_sub = wraddress - 17'd65536;
    assign wraddress_ram2 = wraddr_sub[15:0];
    assign wrdata_ram1 = wrdata;
    assign wrdata_ram2 = wrdata;
    assign wren_ram1 = wren & ~wraddress[16];
    assign wren_ram2 = wren & wraddress[16];

    assign bg_wraddress_ram1 = bg_wr_addr[15:0];
    wire [16:0] bg_wraddr_sub = bg_wr_addr - 17'd65536;
    assign bg_wraddress_ram2 = bg_wr_addr[16] ? bg_wraddr_sub[15:0] : 16'd0; // Bank 2만 접근할 때만 유효 주소 전달
    assign wren_bg_ram1 = bg_wr_en & ~bg_wr_addr[16];
    assign wren_bg_ram2 = bg_wr_en &  bg_wr_addr[16];

    // 읽기 주소 할당 (RAM에는 지연 없는 rdaddress를 직접 입력)
    assign rdaddress_ram1 = rdaddress[15:0];
    wire [16:0] rdaddr_sub = rdaddress - 17'd65536;
    assign rdaddress_ram2 = rdaddress[16] ? rdaddr_sub[15:0] : 16'd0; // 사용하지 않을 때는 0으로 묶어 경고 방지

    // 읽기 데이터 멀티플렉싱 (조합 논리)
    assign rddata = rdaddress_d2[16] ? rddata_ram2 : rddata_ram1;
    assign rddata_bg = rdaddress_d2[16] ? rddata_bg_ram2 : rddata_bg_ram1;

    // RGB565 → RGB888 변환
    wire [7:0] r_888, g_888, b_888;
    assign r_888 = {rddata[15:11], 3'b111};
    assign g_888 = {rddata[10:5], 2'b11};
    assign b_888 = {rddata[4:0], 3'b111};

    // 그레이스케일 계산
    wire [16:0] gray_sum;
    assign gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) +
                     (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) +
                     (b_888 << 4) + (b_888 << 3) + (b_888 << 1);
    assign gray_value = activeArea_aligned ? gray_sum[16:8] : 8'h00;

    // ============================================================================
    // 이미지 처리 모듈 인스턴스
    // ============================================================================
    // 1차 가우시안 블러 (640 픽셀 처리)
    gaussian_3x3_gray8 #(
        .IMG_WIDTH(640)
    ) gaussian_gray_inst (
        .clk(clk_25MHz),
        .enable(1'b1),
        .pixel_in(gray_value),
        .pixel_addr(rdaddress_aligned),
        .vsync(vsync_raw),
        .active_area(activeArea_aligned),
        .pixel_out(gray_blur),
        .filter_ready(filter_ready)
    );

    // 소벨 엣지 검출 (1차 가우시안 지연에 맞춘 타이밍)
    wire [16:0] rdaddress_gauss = rdaddress_delayed[GAUSS_LAT];
    wire activeArea_gauss = activeArea_delayed[GAUSS_LAT];
    sobel_3x3_gray8 #(
        .IMG_WIDTH(640),
        .IMG_HEIGHT(480)
    ) sobel_inst (
        .clk(clk_25MHz),
        .enable(1'b1),
        .pixel_in(gray_blur),  // 1차 가우시안 출력
        .pixel_addr(rdaddress_gauss),  // 가우시안 지연에 맞춘 주소
        .vsync(vsync_raw),
        .active_area(activeArea_gauss),
        .threshold(sobel_threshold_btn),
        .pixel_out(sobel_value),
        .sobel_ready(sobel_ready)
    );

    // 캐니 엣지 검출 (1차 가우시안 지연에 맞춘 타이밍)
    canny_3x3_gray8 #(
        .IMG_WIDTH(640)
    ) canny_inst (
        .clk(clk_25MHz),
        .enable(filter_ready),
        .pixel_in(gray_blur),   // 1차 가우시안 출력
        .pixel_addr(rdaddress_gauss),  // 가우시안 지연에 맞춘 주소
        .vsync(vsync_raw),
        .active_area(activeArea_gauss),
        .threshold_low(canny_thr_low),
        .threshold_high(canny_thr_high),
        .pixel_out(canny_value),
        .canny_ready(canny_ready)
    );

    // --- Color Tracking Modules ---
    rgb_to_hsv rgb_to_hsv_inst (
        .clk(clk_25MHz),
        .rst_n(rst_n_vga_domain),
        .valid_in(activeArea_d2),
        .r_in(r_888),
        .g_in(g_888),
        .b_in(b_888),
        .valid_out(hsv_valid),
        .h_out(h_out),
        .s_out(s_out),
        .v_out(v_out)
    );

    color_tracker #(
        .DATA_WIDTH(8)
    ) color_tracker_inst (
        .clk(clk_25MHz),
        .rst_n(rst_n_vga_domain),
        .valid_in(hsv_valid),
        .color_select(color_track_select),
        .h_in(h_out),
        .s_in(s_out),
        .v_in(v_out),
        .valid_out(color_track_valid),
        .is_target_out(color_track_out)
    );

    assign bg_load_active = ~vga_enable_reg; // Automatically capture first frame
    assign gaussian_value = gray_blur_delayed[PIPE_LATENCY];
    assign gaussian_ready = gaussian_ready_delayed[PIPE_LATENCY];

    adaptive_background #(
        .ADDR_WIDTH(17),
        .PIXEL_WIDTH(8), // 8-bit Grayscale
        .SHIFT_LG2(4),
        .FG_SHIFT_LG2(8)
    ) adaptive_bg_inst (
        .clk(clk_25MHz),
        .rst(1'b0),
        .enable(1'b1),
        .addr_in(rdaddress_delayed[GAUSS_LAT]),
        .live_pixel_in(gray_blur), // Connect 8-bit grayscale directly
        .bg_pixel_in(rddata_bg_delayed[GAUSS_LAT]), 
        .active_in(activeArea_delayed[GAUSS_LAT]),
        .load_frame(bg_load_active_delayed[GAUSS_LAT]), 
        .threshold_in(bg_sub_threshold_btn), 
        .bg_wr_addr(bg_wr_addr),
        .bg_wr_data(bg_wr_data),
        .bg_wr_en(bg_wr_en),
        .foreground_flag(adaptive_fg_flag)
    );

    // ============================================================================
    // 출력 선택 및 VGA 연결
    // ============================================================================
    // 최종 출력 선택
    wire [15:0] sel_rddata_orig = rddata_delayed[PIPE_LATENCY];
    wire [7:0] sel_r_888 = {sel_rddata_orig[15:11], 3'b111};
    wire [7:0] sel_g_888 = {sel_rddata_orig[10:5],  2'b11};
    wire [7:0] sel_b_888 = {sel_rddata_orig[4:0],   3'b111};

    wire [7:0] sel_orig_r = activeArea_delayed[PIPE_LATENCY] ? sel_r_888 : 8'h00;
    wire [7:0] sel_orig_g = activeArea_delayed[PIPE_LATENCY] ? sel_g_888 : 8'h00;
    wire [7:0] sel_orig_b = activeArea_delayed[PIPE_LATENCY] ? sel_b_888 : 8'h00;
    wire [7:0] sel_gray = activeArea_delayed[PIPE_LATENCY] ? gray_value_delayed[PIPE_LATENCY] : 8'h00;
    wire [7:0] sel_gaussian = activeArea_delayed[PIPE_LATENCY] ? gray_blur_delayed[PIPE_LATENCY] : 8'h00;
    wire [7:0] sel_sobel = (activeArea_delayed[PIPE_LATENCY] && sobel_ready) ? sobel_value : 8'h00;
    wire [7:0] sel_canny = (activeArea_delayed[PIPE_LATENCY] && canny_ready) ? canny_value : 8'h00;
    
    // Define color for the tracking output mask
    // 추적된 픽셀을 해당 색상으로 표시
    reg [7:0] sel_colortrack_r, sel_colortrack_g, sel_colortrack_b;
    always @(*) begin
        case (color_track_select)
            2'b00: begin // Red tracking
                sel_colortrack_r = color_track_out_d1 ? 8'hFF : 8'h00;
                sel_colortrack_g = 8'h00;
                sel_colortrack_b = 8'h00;
            end
            2'b01: begin // Green tracking
                sel_colortrack_r = 8'h00;
                sel_colortrack_g = color_track_out_d1 ? 8'hFF : 8'h00;
                sel_colortrack_b = 8'h00;
            end
            2'b10: begin // Blue tracking
                sel_colortrack_r = 8'h00;
                sel_colortrack_g = 8'h00;
                sel_colortrack_b = color_track_out_d1 ? 8'hFF : 8'h00;
            end
            default: begin
                sel_colortrack_r = color_track_out_d1 ? 8'hFF : 8'h00;
                sel_colortrack_g = 8'h00;
                sel_colortrack_b = 8'h00;
            end
        endcase
    end



    // 스위치 로직
    reg [7:0] final_r, final_g, final_b;
    always @(*) begin
        case (active_filter_mode)
            MODE_ORIG: begin
                final_r = sel_orig_r;
                final_g = sel_orig_g;
                final_b = sel_orig_b;
            end
            MODE_GRAY: begin
                final_r = sel_gray;
                final_g = sel_gray;
                final_b = sel_gray;
            end
            MODE_SOBEL: begin
                final_r = sel_sobel;
                final_g = sel_sobel;
                final_b = sel_sobel;
            end
            MODE_CANNY: begin
                final_r = sel_canny;
                final_g = sel_canny;
                final_b = sel_canny;
            end
            MODE_GAUSS: begin
                final_r = sel_gaussian;
                final_g = sel_gaussian;
                final_b = sel_gaussian;
            end
            MODE_COLOR: begin
                final_r = sel_colortrack_r;
                final_g = sel_colortrack_g;
                final_b = sel_colortrack_b;
            end
            MODE_BG_SUB: begin
                // adaptive_fg_flag 파이프라인 정렬:
                //   - adaptive_bg_inst 입력: rdaddress_delayed[2] (GAUSS_LAT)
                //   - adaptive_bg_inst 지연: 3 클럭 (리팩토링으로 3클럭으로 수정됨)
                //   - adaptive_fg_flag 생성 시점: 2(입력) + 3(모듈) = 5 클럭
                //   - adaptive_flag_delayed[2] 최종 사용 시점: 5 + 2 = 7 클럭
                //   - 최종 데이터(sel_orig_r 등) 출력 시점: PIPE_LATENCY = 7 클럭. 타이밍 일치.
                if (adaptive_flag_delayed[2]) begin 
                    // 전경: 원본 색상 출력
                    final_r = sel_orig_r;
                    final_g = sel_orig_g;
                    final_b = sel_orig_b;
                end else begin
                    // 배경: 검은색 출력
                    final_r = 8'h00;
                    final_g = 8'h00;
                    final_b = 8'h00;
                end
            end
            default: begin
                final_r = sel_orig_r;
                final_g = sel_orig_g;
                final_b = sel_orig_b;
            end
        endcase
    end

    // // PLL 인스턴스
    // my_altpll pll_inst (
    //     .inclk0(clk_50MHz),
    //     .c0(clk_24_camera),
    //     .c1(clk_25MHz)
    // );

    // VGA 컨트롤러 (지연 없는 주소/active 출력)
    vga_640 vga_inst (
        .CLK25(clk_25MHz),
        .clkout(),         // 테스트 환경에서는 VGA 클럭 신호 사용 안 함
        .Hsync(),          // 테스트 환경에서는 Hsync 신호 사용 안 함
        .Vsync(vsync_raw), //output
        .Nblank(),         // 테스트 환경에서는 Nblank 신호 사용 안 함
        .activeArea(activeArea), 
        .pixel_address(rdaddress)
    );


    // 듀얼 프레임 버퍼 RAM들
    frame_buffer_ram buffer_ram1 (
        .data(wrdata_ram1),
        .wraddress(wraddress_ram1),
        .wrclock(clk_25MHz),
        .wren(wren_ram1),
        .rdaddress(rdaddress_ram1[15:0]),
        .rdclock(clk_25MHz),
        .q(rddata_ram1)
    );

    frame_buffer_ram_11k buffer_ram2 (
        .data(wrdata_ram2),
        .wraddress(wraddress_ram2[13:0]),
        .wrclock(clk_25MHz),
        .wren(wren_ram2),
        .rdaddress(rdaddress_ram2[13:0]),
        .rdclock(clk_25MHz),
        .q(rddata_ram2)
    );

    frame_buffer_ram_8bit bg_buffer_ram1 (
        .data(bg_wr_data),
        .wraddress(bg_wraddress_ram1),
        .wrclock(clk_25MHz),
        .wren(wren_bg_ram1),
        .rdaddress(rdaddress_ram1[15:0]),
        .rdclock(clk_25MHz),
        .q(rddata_bg_ram1)
    );

    frame_buffer_ram_11k_8bit bg_buffer_ram2 (
        .data(bg_wr_data),
        .wraddress(bg_wraddress_ram2[13:0]),
        .wrclock(clk_25MHz),
        .wren(wren_bg_ram2),
        .rdaddress(rdaddress_ram2[13:0]),
        .rdclock(clk_25MHz),
        .q(rddata_bg_ram2)
    );

endmodule
