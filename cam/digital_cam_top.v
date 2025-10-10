module digital_cam_top (
    input  wire        clk_50,         // 50MHz 시스템 클럭
    input  wire        btn_resend,     // 카메라 설정 재시작 버튼
    input  wire        ir_rx,          // IR 수신기 입력
    output wire        led_config_finished,  // 설정 완료 LED
    
    // VGA 출력 신호들
    output wire        vga_hsync,      // VGA 수평 동기화
    output wire        vga_vsync,      // VGA 수직 동기화
    output wire [7:0]  vga_r,          // VGA 빨간색 (8비트)
    output wire [7:0]  vga_g,          // VGA 초록색 (8비트)
    output wire [7:0]  vga_b,          // VGA 파란색 (8비트)
    output wire        vga_blank_N,    // VGA 블랭킹 신호
    output wire        vga_sync_N,     // VGA 동기화 신호
    output wire        vga_CLK,        // VGA 클럭
    
    // OV7670 카메라 인터페이스
    input  wire        ov7670_pclk,    // 카메라 픽셀 클럭
    output wire        ov7670_xclk,    // 카메라 시스템 클럭
    input  wire        ov7670_vsync,   // 카메라 수직 동기화
    input  wire        ov7670_href,    // 카메라 수평 참조
    input  wire [7:0]  ov7670_data,    // 카메라 픽셀 데이터
    output wire        ov7670_sioc,    // 카메라 I2C 클럭
    inout  wire        ov7670_siod,    // 카메라 I2C 데이터
    output wire        ov7670_pwdn,    // 카메라 파워다운
    output wire        ov7670_reset    // 카메라 리셋
);

    // ============================================================================
    // 파라미터 및 상수 정의
    // ============================================================================
    localparam integer MEM_RD_LAT = 2;           // 메모리 읽기 지연
    localparam integer GAUSS_LAT = 2;             // 가우시안 필터 지연
    localparam integer SOBEL_EXTRA_LAT = 5;       // 소벨 실제 지연 (3x3 윈도우 + 그래디언트 + 크기 + 임계값)
    localparam integer PIPE_LATENCY = GAUSS_LAT + SOBEL_EXTRA_LAT; // 7클럭 (가우시안 + 소벨)
    
    // 경로별 지연 인덱스
    localparam integer IDX_ORIG  = PIPE_LATENCY;  // 원본: 7클럭
    localparam integer IDX_GRAY  = PIPE_LATENCY;  // 그레이스케일: 7클럭
    localparam integer IDX_SOBEL = PIPE_LATENCY;  // 소벨: 7클럭
    localparam integer IDX_CANNY = PIPE_LATENCY;  // 캐니: 7클럭

    // ============================================================================
    // 클럭 및 기본 신호
    // ============================================================================
    wire clk_24_camera;  // 카메라용 24MHz 클럭
    wire clk_25_vga;     // VGA용 25MHz 클럭

    // ============================================================================
    // 카메라 및 메모리 신호
    // ============================================================================
    wire wren;               // RAM 쓰기 활성화
    wire resend;             // 카메라 설정 재시작
    wire [16:0] wraddress;   // RAM 쓰기 주소
    wire [15:0] wrdata;      // RAM 쓰기 데이터 (RGB565)
    wire [16:0] rdaddress;   // RAM 읽기 주소 (VGA에서 생성)
    wire [15:0] rddata;      // RAM 읽기 데이터 (RGB565)
    wire activeArea;         // VGA 활성 영역

    // 듀얼 프레임 버퍼 신호들 (320x240 = 76800 픽셀을 두 개의 RAM으로 분할)
    wire [15:0] wraddress_ram1, rdaddress_ram1; // RAM1: 16비트 주소 (0-32767)
    wire [15:0] wraddress_ram2, rdaddress_ram2; // RAM2: 16비트 주소 (0-44031)
    wire [15:0] wrdata_ram1, wrdata_ram2;       // 각 RAM의 쓰기 데이터 (RGB565)
    wire wren_ram1, wren_ram2;                  // 각 RAM의 쓰기 활성화
    wire [15:0] rddata_ram1, rddata_ram2;       // 각 RAM의 읽기 데이터 (RGB565)

    // ============================================================================
    // VGA 신호
    // ============================================================================
    wire hsync_raw, vsync_raw;
    wire vga_blank_N_raw;
    wire vga_sync_N_raw;
    wire vga_enable;         // VGA 출력 활성화 신호

    // ============================================================================
    // 이미지 처리 신호
    // ============================================================================
    wire [7:0] gray_value;           // 그레이스케일 값
    wire [7:0] red_value, green_value, blue_value;  // RGB 값들
    wire [7:0] sobel_value;          // 소벨 필터 값 (그레이스케일)
    wire [7:0] canny_value;          // 캐니 엣지 값 (이진)
    wire filter_ready;               // 필터 처리 완료 신호
    wire sobel_ready;                // 소벨 처리 완료 신호
    wire canny_ready;                // 캐니 처리 완료 신호

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
    reg [7:0] red_value_delayed [PIPE_LATENCY:0];       // 빨간색 지연
    reg [7:0] green_value_delayed [PIPE_LATENCY:0];     // 초록색 지연
    reg [7:0] blue_value_delayed [PIPE_LATENCY:0];      // 파란색 지연
    reg [7:0] gray_value_delayed [PIPE_LATENCY:0];      // 그레이스케일 지연
    reg [7:0] sobel_value_delayed [PIPE_LATENCY:0];     // 소벨 지연
    reg [7:0] canny_value_delayed [PIPE_LATENCY:0];     // 캐니 지연
    reg filter_ready_delayed [PIPE_LATENCY:0];          // 필터 준비 지연
    reg sobel_ready_delayed [PIPE_LATENCY:0];           // 소벨 준비 지연
    reg canny_ready_delayed [PIPE_LATENCY:0];           // 캐니 준비 지연

    // 배경 제거 출력을 위한 파이프라인
    reg [15:0] bg_sub_out_delayed [4:0];

    // ============================================================================
    // 버튼 및 제어 로직
    // ============================================================================
    // 카메라 리셋용 버튼 디바운싱
    reg [19:0] btn_counter = 20'd0;
    reg btn_pressed = 1'b0;
    reg btn_pressed_prev = 1'b0;
    wire btn_rising_edge;



    // IR Control Logic
    // Key Codes
    localparam KEY_A    = 8'h0F;
    localparam KEY_B    = 8'h13;
    localparam KEY_C    = 8'h10;
    localparam KEY_1    = 8'h01;
    localparam KEY_UP   = 8'h1A;
    localparam KEY_DOWN = 8'h1E;
    localparam KEY_ORIG = 8'h12; // Using 'OK' button for original mode
    localparam KEY_BG_MODE    = 8'h04;

    // Filter mode state register
    localparam MODE_ORIG  = 3'd0;
    localparam MODE_GRAY  = 3'd1;
    localparam MODE_SOBEL = 3'd2;
    localparam MODE_CANNY = 3'd3;
    localparam MODE_COLOR = 3'd4;
    localparam MODE_BG_SUB = 3'd5; // 배경 제거 모드

    reg [2:0] active_filter_mode = MODE_ORIG;

    // Adaptive background signals
    wire [15:0] bg_sub_out;
    wire        adaptive_fg_flag;
    wire [15:0] rddata_bg;
    wire [15:0] rddata_bg_ram1, rddata_bg_ram2;
    wire [16:0] bg_wr_addr;
    wire [15:0] bg_wr_data;
    wire        bg_wr_en;
    wire [15:0] bg_wraddress_ram1;
    wire [15:0] bg_wraddress_ram2;
    wire        wren_bg_ram1, wren_bg_ram2;


    // IR Receiver outputs
    wire [7:0] ir_code;
    wire ir_valid;
    wire rst_n_50m;

    // IR command pulses
    reg ir_up_pulse = 1'b0;
    reg ir_down_pulse = 1'b0;

    assign rst_n_50m = ~btn_pressed; // Active low reset from debounced button

    // Instantiate IR Receiver
    IR_RECEVER ir_inst (
        .clk(clk_50),
        .rst_n(rst_n_50m),
        .IRDA_RXD(ir_rx),
        .captured_code(ir_code),
        .data_valid(ir_valid)
    );

    // IR Command Decoder
    always @(posedge clk_50) begin
        // Pulses are active for one cycle
        ir_up_pulse <= 1'b0;
        ir_down_pulse <= 1'b0;

        if (ir_valid) begin
            case (ir_code)
                KEY_A:    active_filter_mode <= MODE_GRAY;
                KEY_B:    active_filter_mode <= MODE_SOBEL;
                KEY_C:    active_filter_mode <= MODE_CANNY;
                KEY_1:    active_filter_mode <= MODE_COLOR;
                KEY_ORIG: active_filter_mode <= MODE_ORIG;
                KEY_UP:   ir_up_pulse <= 1'b1;
                KEY_DOWN: ir_down_pulse <= 1'b1;
                KEY_BG_MODE: active_filter_mode <= MODE_BG_SUB;
                default:  ; // Do nothing for other keys
            endcase
        end
    end

    // Sobel 임계값
    reg [7:0] sobel_threshold_btn = 8'd64;

    // 캐니 임계값
    reg [7:0] canny_thr_low = 8'd24;
    reg [7:0] canny_thr_high = 8'd64;

    // ============================================================================
    // 프레임 제어 로직
    // ============================================================================
    reg first_frame_captured = 1'b0;  // 첫 프레임 캡처 완료 플래그
    reg vsync_prev_pclk = 1'b0;       // vsync 이전 값 (pclk 도메인)
    reg frame_ready_sync1 = 1'b0;
    reg frame_ready_sync2 = 1'b0;
    reg vga_enable_reg = 1'b0;
    reg vsync_prev_display = 1'b1;

    // ============================================================================
    // 메모리 지연 보정 로직 (RAM 2클럭)
    // ============================================================================
    reg activeArea_d1 = 1'b0, activeArea_d2 = 1'b0;
    reg [16:0] rdaddress_d1 = 17'd0, rdaddress_d2 = 17'd0;

    // ============================================================================
    // 버튼 디바운싱 로직
    // ============================================================================
    // 카메라 리셋 버튼
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



    // Sobel 임계값 조정
    always @(posedge clk_50) begin
        if (ir_up_pulse)   sobel_threshold_btn <= (sobel_threshold_btn >= 8'd250) ? 8'd255 : (sobel_threshold_btn + 8'd5);
        if (ir_down_pulse) sobel_threshold_btn <= (sobel_threshold_btn <= 8'd5)   ? 8'd0   : (sobel_threshold_btn - 8'd5);
    end

    // ============================================================================
    // 프레임 제어 로직
    // ============================================================================
    // 첫 프레임 완료 감지 (캡처 클럭 도메인)
    always @(posedge ov7670_pclk) begin
        vsync_prev_pclk <= ov7670_vsync;
        if (vsync_prev_pclk && !ov7670_vsync && !first_frame_captured) begin
            first_frame_captured <= 1'b1;
        end
        if (resend) begin
            first_frame_captured <= 1'b0;
        end
    end
    
    // CDC 동기화: pclk → clk_25_vga
    always @(posedge clk_25_vga) begin
        frame_ready_sync1 <= first_frame_captured;
        frame_ready_sync2 <= frame_ready_sync1;
    end
    
    // VGA 출력 활성화
    always @(posedge clk_25_vga) begin
        vsync_prev_display <= vsync_raw;
        if (!frame_ready_sync2) begin
            vga_enable_reg <= 1'b0;
        end else if (!vsync_prev_display && vsync_raw) begin
            vga_enable_reg <= 1'b1;
        end
    end

    // ============================================================================
    // 메모리 지연 보정
    // ============================================================================
    always @(posedge clk_25_vga) begin
        activeArea_d1 <= activeArea;
        activeArea_d2 <= activeArea_d1;
        rdaddress_d1  <= rdaddress;
        rdaddress_d2  <= rdaddress_d1;
    end

    // ============================================================================
    // 파이프라인 정렬
    // ============================================================================
    integer i;
    always @(posedge clk_25_vga) begin
        // Delay for color tracker output to align with main pipeline
        color_track_out_d1 <= color_track_out;

        if (vsync_raw == 1'b0) begin
            // 프레임 시작 시 모든 지연 레지스터 클리어
            for (i = 0; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= 17'd0;
                activeArea_delayed[i] <= 1'b0;
                red_value_delayed[i] <= 8'd0;
                green_value_delayed[i] <= 8'd0;
                blue_value_delayed[i] <= 8'd0;
                gray_value_delayed[i] <= 8'd0;
                sobel_value_delayed[i] <= 8'd0;
                canny_value_delayed[i] <= 8'd0;
                filter_ready_delayed[i] <= 1'b0;
                sobel_ready_delayed[i] <= 1'b0;
                canny_ready_delayed[i] <= 1'b0;
                adaptive_fg_flag_delayed[i] <= 1'b0;
            end
        end else begin
            // 0단계 (정렬 기준 d2)
            rdaddress_delayed[0] <= rdaddress_d2;
            activeArea_delayed[0] <= activeArea_d2;
            red_value_delayed[0] <= red_value;
            green_value_delayed[0] <= green_value;
            blue_value_delayed[0] <= blue_value;
            gray_value_delayed[0] <= gray_value;
            sobel_value_delayed[0] <= sobel_value;
            canny_value_delayed[0] <= canny_value;
            filter_ready_delayed[0] <= filter_ready;
            sobel_ready_delayed[0] <= sobel_ready;
            canny_ready_delayed[0] <= canny_ready;
            adaptive_fg_flag_delayed[0] <= adaptive_fg_flag;
            
            // 1-PIPE_LATENCY 단계 지연 체인
            for (i = 1; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= rdaddress_delayed[i-1];
                activeArea_delayed[i] <= activeArea_delayed[i-1];
                red_value_delayed[i] <= red_value_delayed[i-1];
                green_value_delayed[i] <= green_value_delayed[i-1];
                blue_value_delayed[i] <= blue_value_delayed[i-1];
                gray_value_delayed[i] <= gray_value_delayed[i-1];
                sobel_value_delayed[i] <= sobel_value_delayed[i-1];
                canny_value_delayed[i] <= canny_value_delayed[i-1];
                filter_ready_delayed[i] <= filter_ready_delayed[i-1];
                sobel_ready_delayed[i] <= sobel_ready_delayed[i-1];
                canny_ready_delayed[i] <= canny_ready_delayed[i-1];
                adaptive_fg_flag_delayed[i] <= adaptive_fg_flag_delayed[i-1];
            end

            // 배경 제거 출력 파이프라인
            bg_sub_out_delayed[0] <= bg_sub_out;
            for (i = 0; i < 4; i = i + 1) begin
                bg_sub_out_delayed[i+1] <= bg_sub_out_delayed[i];
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
    assign btn_rising_edge = btn_pressed & ~btn_pressed_prev;
    assign resend = btn_rising_edge;

    assign vga_enable = vga_enable_reg;

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
    assign bg_wraddress_ram2 = bg_wraddr_sub[15:0];
    assign wren_bg_ram1 = bg_wr_en & ~bg_wr_addr[16];
    assign wren_bg_ram2 = bg_wr_en &  bg_wr_addr[16];

    // 읽기 주소 할당 (RAM에는 rdaddress 직접 입력 → RAM 2클럭 후 d2와 정렬)
    assign rdaddress_ram1 = rdaddress[15:0];
    wire [16:0] rdaddr_sub = rdaddress - 17'd65536;
    assign rdaddress_ram2 = rdaddr_sub[15:0];

    // 읽기 데이터 멀티플렉싱 (조합 논리)
    assign rddata = rdaddress_d2[16] ? rddata_ram2 : rddata_ram1;
    assign rddata_bg = rdaddress_d2[16] ? rddata_bg_ram2 : rddata_bg_ram1;

    // RGB565 → RGB888 변환
    wire [7:0] r_888, g_888, b_888;
    assign r_888 = {rddata[15:11], 3'b111};
    assign g_888 = {rddata[10:5], 2'b11};
    assign b_888 = {rddata[4:0], 3'b111};

    // RGB888을 하나의 24비트 픽셀로 결합
    wire [23:0] rgb888_pixel = {r_888, g_888, b_888};

    // 그레이스케일 계산
    wire [16:0] gray_sum;
    assign gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) +
                     (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) +
                     (b_888 << 4) + (b_888 << 3) + (b_888 << 1);
    assign gray_value = activeArea_aligned ? gray_sum[16:8] : 8'h00;

    // 색상 값들
    assign red_value = activeArea_aligned ? r_888 : 8'h00;
    assign green_value = activeArea_aligned ? g_888 : 8'h00;
    assign blue_value = activeArea_aligned ? b_888 : 8'h00;

    // ============================================================================
    // 이미지 처리 모듈 인스턴스
    // ============================================================================
    // 1차 가우시안 블러 (640 픽셀 처리)
    wire [7:0] gray_blur;
    gaussian_3x3_gray8 #(
        .IMG_WIDTH(640)
    ) gaussian_gray_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_value),
        .pixel_addr(rdaddress_aligned),
        .vsync(vsync_raw),
        .active_area(activeArea_aligned),
        .pixel_out(gray_blur),
        .filter_ready(filter_ready)
    );

    // 2차 가우시안 블러 제거 (1차 가우시안만 사용)

    // 소벨 엣지 검출 (1차 가우시안 지연에 맞춘 타이밍)
    wire [16:0] rdaddress_gauss = rdaddress_delayed[GAUSS_LAT];
    wire activeArea_gauss = activeArea_delayed[GAUSS_LAT];
    sobel_3x3_gray8 #(
        .IMG_WIDTH(640),
        .IMG_HEIGHT(480)
    ) sobel_inst (
        .clk(clk_25_vga),
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
        .clk(clk_25_vga),
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
        .clk(clk_25_vga),
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

    color_tracker color_tracker_inst (
        .clk(clk_25_vga),
        .rst_n(rst_n_vga_domain),
        .valid_in(hsv_valid),
        .h_in(h_out),
        .s_in(s_out),
        .v_in(v_out),
        .valid_out(color_track_valid),
        .is_target_out(color_track_out)
    );

    // ============================================================================
    // 출력 선택 및 VGA 연결
    // ============================================================================
    // 최종 출력 선택
    wire [7:0] sel_orig_r = activeArea_delayed[IDX_ORIG] ? red_value_delayed[IDX_ORIG] : 8'h00;
    wire [7:0] sel_orig_g = activeArea_delayed[IDX_ORIG] ? green_value_delayed[IDX_ORIG] : 8'h00;
    wire [7:0] sel_orig_b = activeArea_delayed[IDX_ORIG] ? blue_value_delayed[IDX_ORIG] : 8'h00;
    wire [7:0] sel_gray = activeArea_delayed[IDX_GRAY] ? gray_value_delayed[IDX_GRAY] : 8'h00;
    wire [7:0] sel_sobel = (activeArea_delayed[IDX_SOBEL] && sobel_ready_delayed[IDX_SOBEL]) ? sobel_value_delayed[IDX_SOBEL] : 8'h00;
    wire [7:0] sel_canny = (activeArea_delayed[IDX_CANNY] && canny_ready_delayed[IDX_CANNY]) ? canny_value_delayed[IDX_CANNY] : 8'h00;
    
    // Define color for the tracking output mask
    wire [7:0] sel_colortrack_r = color_track_out_d1 ? 8'hFF : 8'h00; // Red
    wire [7:0] sel_colortrack_g = 8'h00;                               // Black
    wire [7:0] sel_colortrack_b = 8'h00;                               // Black

    // Background subtraction output (RGB565 -> RGB888)
    wire [7:0] sel_bg_sub_r = {bg_sub_out_delayed[4][15:11], 3'b111};
    wire [7:0] sel_bg_sub_g = {bg_sub_out_delayed[4][10:5],  2'b11};
    wire [7:0] sel_bg_sub_b = {bg_sub_out_delayed[4][4:0],   3'b111};

    // 배경 제거 플래그 지연
    reg adaptive_fg_flag_delayed [PIPE_LATENCY:0];
    // This flag's pipeline is now integrated into the main pipeline block for synchronization.

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
            MODE_COLOR: begin
                final_r = sel_colortrack_r;
                final_g = sel_colortrack_g;
                final_b = sel_colortrack_b;
            end
            MODE_BG_SUB: begin
                if (adaptive_fg_flag_delayed[IDX_ORIG]) begin
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

    // activeArea_aligned 대신 파이프라인 최종단에 정렬된 activeArea_delayed[IDX_ORIG] 사용
    assign vga_r = (vga_enable && activeArea_delayed[IDX_ORIG]) ? final_r : 8'h00;
    assign vga_g = (vga_enable && activeArea_delayed[IDX_ORIG]) ? final_g : 8'h00;
    assign vga_b = (vga_enable && activeArea_delayed[IDX_ORIG]) ? final_b : 8'h00;

    // ============================================================================
    // 외부 모듈 인스턴스
    // ============================================================================
    // ============================================================================
    // 적응형 배경제거 모듈
    // ============================================================================
    reg  bg_load_active = 1'b0;

    // On the first frame after reset/startup, load it as the initial background.
    // This signal stays high until the first VSYNC, then goes low.
    always @(posedge clk_25_vga) begin
        if (!frame_ready_sync2) begin
            bg_load_active <= 1'b1; // Initialize background on first frame
        end else if (!vsync_prev_display && vsync_raw) begin // De-assert at the start of the next frame
            bg_load_active <= 1'b0;
        end
    end

    adaptive_background #(
        .ADDR_WIDTH(17),
        .PIXEL_WIDTH(16),
        .SHIFT_LG2(4),
        .THRESHOLD(9'd180) // Increased from 160 to further reduce noise
    ) adaptive_bg_inst (
        .clk(clk_25_vga),
        .rst(1'b0),
        .enable(1'b1),
        .addr_in(rdaddress_d2),
        .live_pixel_in(rddata),
        .bg_pixel_in(rddata_bg),
        .active_in(activeArea_d2),
        .load_frame(bg_load_active),
        .bg_wr_addr(bg_wr_addr),
        .bg_wr_data(bg_wr_data),
        .bg_wr_en(bg_wr_en),
        .fg_pixel_out(bg_sub_out),
        .foreground_flag(adaptive_fg_flag)
    );

    // PLL 인스턴스
    my_altpll pll_inst (
        .inclk0(clk_50),
        .c0(clk_24_camera),
        .c1(clk_25_vga)
    );

    // VGA 컨트롤러
    vga_640 vga_inst (
        .CLK25(clk_25_vga),
        .pixel_data(rddata),
        .clkout(vga_CLK),
        .Hsync(hsync_raw),
        .Vsync(vsync_raw),
        .Nblank(vga_blank_N_raw), 
        .Nsync(vga_sync_N_raw),
        .activeArea(activeArea), 
        .pixel_address(rdaddress)
    );

    // VGA 출력 신호들
    assign vga_hsync = hsync_raw;
    assign vga_vsync = vsync_raw;
    assign vga_blank_N = vga_blank_N_raw;
    assign vga_sync_N = vga_sync_N_raw;

    // OV7670 카메라 컨트롤러
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

    // OV7670 캡처 모듈
    ov7670_capture capture_inst (
        .pclk(ov7670_pclk),
        .vsync(ov7670_vsync),
        .href(ov7670_href),
        .d(ov7670_data),
        .addr(wraddress),
        .dout(wrdata),
        .we(wren)
    );

    // 듀얼 프레임 버퍼 RAM들
    frame_buffer_ram buffer_ram1 (
        .data(wrdata_ram1),
        .wraddress(wraddress_ram1),
        .wrclock(ov7670_pclk),
        .wren(wren_ram1),
        .rdaddress(rdaddress_ram1[15:0]),
        .rdclock(clk_25_vga),
        .q(rddata_ram1)
    );

    frame_buffer_ram_11k buffer_ram2 (
        .data(wrdata_ram2),
        .wraddress(wraddress_ram2[13:0]),
        .wrclock(ov7670_pclk),
        .wren(wren_ram2),
        .rdaddress(rdaddress_ram2[13:0]),
        .rdclock(clk_25_vga),
        .q(rddata_ram2)
    );

    frame_buffer_ram bg_buffer_ram1 (
        .data(bg_wr_data),
        .wraddress(bg_wraddress_ram1),
        .wrclock(clk_25_vga),
        .wren(wren_bg_ram1),
        .rdaddress(rdaddress_ram1[15:0]),
        .rdclock(clk_25_vga),
        .q(rddata_bg_ram1)
    );

    frame_buffer_ram_11k bg_buffer_ram2 (
        .data(bg_wr_data),
        .wraddress(bg_wraddress_ram2[13:0]),
        .wrclock(clk_25_vga),
        .wren(wren_bg_ram2),
        .rdaddress(rdaddress_ram2[13:0]),
        .rdclock(clk_25_vga),
        .q(rddata_bg_ram2)
    );

endmodule
