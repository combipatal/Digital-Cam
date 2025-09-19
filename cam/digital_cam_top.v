// OV7670 카메라 인터페이스 최상위 모듈
// 카메라 캡처, 프레임 버퍼, VGA 디스플레이를 통합한 메인 모듈
module digital_cam_top (
    input  wire        clk_50,         // 50MHz 시스템 클럭
    input  wire        btn_resend,     // 카메라 설정 재시작 버튼
    input  wire        btn_thr_up,     // 소벨 임계 증가 버튼 (액티브 로우 가정 시 디바운싱 동일 처리)
    input  wire        btn_thr_down,   // 소벨 임계 감소 버튼
    input  wire        sw_grayscale,   // SW[0] 그레이스케일 모드 스위치
    input  wire        sw_sobel,       // SW[1] 소벨 필터 모드 스위치
    input  wire        sw_filter,      // SW[2] 디지털 필터 모드 스위치
    input  wire        sw_canny,       // SW[3] 캐니 엣지 모드 스위치
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

    // 내부 신호들
    wire clk_24_camera;  // 카메라용 24MHz 클럭
    wire clk_25_vga;     // VGA용 25MHz 클럭
    wire wren;           // RAM 쓰기 활성화
    wire resend;         // 카메라 설정 재시작
    wire nBlank;         // VGA 블랭킹 신호
    wire vSync;          // VGA 수직 동기화
    wire [16:0] wraddress;  // RAM 쓰기 주소
    wire [15:0] wrdata;     // RAM 쓰기 데이터 (RGB565)
    wire [16:0] rdaddress;  // RAM 읽기 주소
    wire [15:0] rddata;     // RAM 읽기 데이터 (RGB565)
    wire activeArea;        // VGA 활성 영역
    
    // 듀얼 프레임 버퍼 신호들 (320x240 = 76800 픽셀을 두 개의 RAM으로 분할)
    wire [15:0] wraddress_ram1, rdaddress_ram1; // RAM1: 16비트 주소 (0-32767)
    wire [15:0] wraddress_ram2, rdaddress_ram2; // RAM2: 16비트 주소 (0-44031)
    wire [15:0] wrdata_ram1, wrdata_ram2;       // 각 RAM의 쓰기 데이터 (RGB565)
    wire wren_ram1, wren_ram2;                  // 각 RAM의 쓰기 활성화
    wire [15:0] rddata_ram1, rddata_ram2;       // 각 RAM의 읽기 데이터 (RGB565)
    
    // RAM2 오프셋 계산은 하위 16비트에서 오프셋을 적용 (원복)
    
    // 카메라 리셋용 버튼 디바운싱
    reg [19:0] btn_counter = 20'd0;     // 버튼 카운터 (20ms 디바운싱용)
    reg btn_pressed = 1'b0;             // 버튼 눌림 상태
    reg btn_pressed_prev = 1'b0;        // 이전 버튼 상태
    wire btn_rising_edge;               // 버튼 상승 에지
    
    // 버튼 디바운싱 로직 - 채터링 방지
    always @(posedge clk_50) begin
        if (btn_resend == 1'b0) begin  // 버튼이 눌렸을 때 (액티브 로우)
            if (btn_counter < 20'd1000000)  // 20ms 디바운싱 (50MHz에서)
                btn_counter <= btn_counter + 1'b1;
            else
                btn_pressed <= 1'b1;  // 버튼이 안정적으로 눌림
        end else begin
            btn_counter <= 20'd0;     // 카운터 리셋
            btn_pressed <= 1'b0;      // 버튼 상태 리셋
        end
        btn_pressed_prev <= btn_pressed;  // 이전 상태 저장
    end
    
    assign btn_rising_edge = btn_pressed & ~btn_pressed_prev;  // 상승 에지 감지

    // 소벨 임계값 조절 버튼 디바운싱 (업/다운) - 액티브 로우 동일 가정
    reg [19:0] btn_up_counter = 20'd0;
    reg [19:0] btn_down_counter = 20'd0;
    reg btn_up_pressed = 1'b0;
    reg btn_down_pressed = 1'b0;
    reg btn_up_prev = 1'b0;
    reg btn_down_prev = 1'b0;
    wire btn_up_rise;
    wire btn_down_rise;

    always @(posedge clk_50) begin
        // UP
        if (btn_thr_up == 1'b0) begin
            if (btn_up_counter < 20'd1000000)
                btn_up_counter <= btn_up_counter + 1'b1;
            else
                btn_up_pressed <= 1'b1;
        end else begin
            btn_up_counter <= 20'd0;
            btn_up_pressed <= 1'b0;
        end
        btn_up_prev <= btn_up_pressed;

        // DOWN
        if (btn_thr_down == 1'b0) begin
            if (btn_down_counter < 20'd1000000)
                btn_down_counter <= btn_down_counter + 1'b1;
            else
                btn_down_pressed <= 1'b1;
        end else begin
            btn_down_counter <= 20'd0;
            btn_down_pressed <= 1'b0;
        end
        btn_down_prev <= btn_down_pressed;
    end

    assign btn_up_rise = btn_up_pressed & ~btn_up_prev;
    assign btn_down_rise = btn_down_pressed & ~btn_down_prev;

    // 소벨 임계값 레지스터 (포화 증감)
    reg [7:0] sobel_threshold = 8'd32; // 기본 임계값
    always @(posedge clk_50) begin
        if (btn_up_rise) begin
            if (sobel_threshold != 8'hFF)
                sobel_threshold <= sobel_threshold + 8'd4;
        end else if (btn_down_rise) begin
            if (sobel_threshold != 8'h00)
                sobel_threshold <= sobel_threshold - 8'd4;
        end
    end
    
    // 신호 연결
    assign resend = btn_rising_edge;  // 버튼 상승 에지에서 리셋 펄스 전송
    // vSync는 내부 파이프라인 정렬에 사용
    assign vga_blank_N = nBlank;      // VGA 블랭킹 신호 연결
    
    // 듀얼 프레임 버퍼 - 320x240 = 76800 픽셀을 두 개의 RAM으로 분할
    // RAM1: 주소 0-32767 (첫 번째 절반) - 32K RAM
    // RAM2: 주소 32768-76799 (두 번째 절반) - 44K RAM
    
    // 쓰기 주소 할당
    assign wraddress_ram1 = wraddress[15:0];  // RAM1: 0-32767 (16비트)
    wire [16:0] wraddr_sub = wraddress - 17'd32768;
    assign wraddress_ram2 = wraddr_sub[15:0];  // RAM2: 0-44031 (정상 오프셋)
    assign wrdata_ram1 = wrdata;              // RAM1 쓰기 데이터
    assign wrdata_ram2 = wrdata;              // RAM2 쓰기 데이터
    assign wren_ram1 = wren & ~wraddress[16]; // 주소 < 32768일 때 RAM1에 쓰기
    assign wren_ram2 = wren & wraddress[16];  // 주소 >= 32768일 때 RAM2에 쓰기
    
    // 읽기 주소 할당
    assign rdaddress_ram1 = rdaddress[15:0];  // RAM1: 0-32767 (16비트)
    wire [16:0] rdaddr_sub = rdaddress - 17'd32768;
    assign rdaddress_ram2 = rdaddr_sub[15:0];  // RAM2: 0-44031 (정상 오프셋)
    
    // 읽기 데이터 멀티플렉싱 - 상위 비트에 따라 어느 RAM에서 읽을지 결정
    assign rddata = rdaddress[16] ? rddata_ram2 : rddata_ram1;
    
    // RGB 변환 및 그레이스케일, 소벨 필터, 디지털 필터 모드
    wire [7:0] gray_value;           // 그레이스케일 값
    wire [7:0] red_value, green_value, blue_value;  // RGB 값들
    wire [7:0] sobel_value;          // 소벨 필터 값 (그레이스케일)
    wire [7:0] canny_value;          // 캐니 엣지 값 (이진)
    wire [23:0] filtered_pixel;      // 디지털 필터 적용된 픽셀 (RGB888) - 그레이 복제
    wire filter_ready;               // 필터 처리 완료 신호
    wire filter_ready2;              // 2차 가우시안 ready
    wire sobel_ready;                // 소벨 처리 완료 신호 (선언을 앞당겨 사용 이전에 배치)
    
    // RGB565 → RGB888 직접 변환 (화질 최적화)
    // RGB565: R[15:11] G[10:5] B[4:0]
    // RGB888: R[7:0] G[7:0] B[7:0]
    wire [7:0] r_888, g_888, b_888;  // RGB888로 확장된 값들
    
    assign r_888 = {rddata[15:11], 3'b111};  // 5비트 → 8비트 비트복제
    assign g_888 = {rddata[10:5], 2'b11};   // 6비트 → 8비트 비트복제
    assign b_888 = {rddata[4:0],  3'b11};    // 5비트 → 8비트 비트복제
    
    // RGB888을 하나의 24비트 픽셀로 결합 (필터 입력용)
    wire [23:0] rgb888_pixel = {r_888, g_888, b_888};
    
    // 그레이스케일 계산 (RGB888 기준) - 개선된 정확도
    wire [16:0] gray_sum;            // 그레이스케일 합계 (17비트: 76*255 + 150*255 + 30*255 = 65280)
    // Y = 0.299*R + 0.587*G + 0.114*B (ITU-R BT.709 표준)
    // 더 정확한 정수 연산: Y = (76*R + 150*G + 30*B) / 256
    assign gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) +  // 76*R
                     (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) +  // 150*G
                     (b_888 << 4) + (b_888 << 3) + (b_888 << 1);  // 30*B
    assign gray_value = activeArea ? gray_sum[16:8] : 8'h00;  // >> 8 (256으로 나누기)
    
    // 필터 적용된 픽셀에서 RGB 분리 (가우시안 그레이 결과 복제)
    // 선언을 앞당겨 파이프라인 정렬 블록에서 참조 가능하게 함
    wire [7:0] filter_r_888, filter_g_888, filter_b_888;

    // 파이프라인 지연: 경로별 상이
    // - 가우시안 2회: 4클럭, 소벨 추가: 2클럭 → 총 6클럭
    localparam integer GAUSS_LAT = 4;
    localparam integer SOBEL_EXTRA_LAT = 2;
    localparam integer PIPE_LATENCY = GAUSS_LAT + SOBEL_EXTRA_LAT; // 6
    reg [16:0] rdaddress_delayed [PIPE_LATENCY:0];      // rdaddress delayed value
    reg activeArea_delayed [PIPE_LATENCY:0];            // active area delayed value
    reg [7:0] red_value_delayed [PIPE_LATENCY:0];       // red delayed value
    reg [7:0] green_value_delayed [PIPE_LATENCY:0];     // green delayed value
    reg [7:0] blue_value_delayed [PIPE_LATENCY:0];      // blue delayed value
    reg [7:0] gray_value_delayed [PIPE_LATENCY:0];      // gray delayed value
    reg [23:0] filtered_pixel_delayed [PIPE_LATENCY:0]; // filtered pixel delayed value
    reg [7:0] filter_r_delayed [PIPE_LATENCY:0];        // filter r delayed value
    reg [7:0] filter_g_delayed [PIPE_LATENCY:0];        // filter g delayed value
    reg [7:0] filter_b_delayed [PIPE_LATENCY:0];        // filter b delayed value
    reg [7:0] sobel_value_delayed [PIPE_LATENCY:0];     // sobel value delayed value
    reg [7:0] canny_value_delayed [PIPE_LATENCY:0];     // canny value delayed value
    reg       filter_ready_delayed [PIPE_LATENCY:0];     // filter ready delayed
    reg       sobel_ready_delayed  [PIPE_LATENCY:0];     // sobel ready delayed
    reg       canny_ready_delayed  [PIPE_LATENCY:0];     // canny ready delayed
    integer i; 
    
	// 파이프라인 정렬: 정상 상태 기준 PIPE_LATENCY 클럭 지연 체인
    always @(posedge clk_25_vga) begin
        // 프레임 시작(Vsync 로우) 시 모든 지연 레지스터 클리어
        if (vSync == 1'b0) begin
            for (i = 0; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= 17'd0;
                activeArea_delayed[i] <= 1'b0;
                red_value_delayed[i] <= 8'd0;
                green_value_delayed[i] <= 8'd0;
                blue_value_delayed[i] <= 8'd0;
                gray_value_delayed[i] <= 8'd0;
                filtered_pixel_delayed[i] <= 24'd0;
                filter_r_delayed[i] <= 8'd0;
                filter_g_delayed[i] <= 8'd0;
                filter_b_delayed[i] <= 8'd0;
                sobel_value_delayed[i] <= 8'd0;
                canny_value_delayed[i] <= 8'd0;
                filter_ready_delayed[i] <= 1'b0;
                sobel_ready_delayed[i] <= 1'b0;
                canny_ready_delayed[i] <= 1'b0;
            end
        end else begin
            // 0단계
            rdaddress_delayed[0] <= rdaddress;
            activeArea_delayed[0] <= activeArea;
            red_value_delayed[0] <= red_value;
            green_value_delayed[0] <= green_value;
            blue_value_delayed[0] <= blue_value;
            gray_value_delayed[0] <= gray_value;
            filtered_pixel_delayed[0] <= filtered_pixel;
            filter_r_delayed[0] <= filter_r_888;
            filter_g_delayed[0] <= filter_g_888;
            filter_b_delayed[0] <= filter_b_888;
            sobel_value_delayed[0] <= sobel_value; // 정렬 용도로만 유지, 값은 그대로
            canny_value_delayed[0] <= canny_value;
            // 2차 가우시안 기준으로 ready 정렬
            filter_ready_delayed[0] <= filter_ready2;
            sobel_ready_delayed[0]  <= sobel_ready;
            canny_ready_delayed[0]  <= canny_ready;
            
            // 1-PIPE_LATENCY 단계 지연 체인
            for (i= 1; i <= PIPE_LATENCY; i = i + 1) begin
                rdaddress_delayed[i] <= rdaddress_delayed[i-1];
                activeArea_delayed[i] <= activeArea_delayed[i-1];
                red_value_delayed[i] <= red_value_delayed[i-1];
                green_value_delayed[i] <= green_value_delayed[i-1];
                blue_value_delayed[i] <= blue_value_delayed[i-1];
                gray_value_delayed[i] <= gray_value_delayed[i-1];
                filtered_pixel_delayed[i] <= filtered_pixel_delayed[i-1];
                filter_r_delayed[i] <= filter_r_delayed[i-1];
                filter_g_delayed[i] <= filter_g_delayed[i-1];
                filter_b_delayed[i] <= filter_b_delayed[i-1];
                sobel_value_delayed[i] <= sobel_value_delayed[i-1];
                canny_value_delayed[i] <= canny_value_delayed[i-1];
                filter_ready_delayed[i] <= filter_ready_delayed[i-1];
                sobel_ready_delayed[i]  <= sobel_ready_delayed[i-1];
                canny_ready_delayed[i]  <= canny_ready_delayed[i-1];
            end
        end
    end

    // 가우시안 블러 1차 (그레이스케일 8비트)
    wire [7:0] gray_blur1;
    gaussian_3x3_gray8 gaussian_gray_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_value),
        .pixel_addr(rdaddress),
        .vsync(vSync),
        .active_area(activeArea),
        .pixel_out(gray_blur1),
        .filter_ready(filter_ready)
    );

    // 가우시안 블러 2차 (강도 상승)
    wire [7:0] gray_blur2;
    gaussian_3x3_gray8 gaussian_gray2_inst (
        .clk(clk_25_vga),
        .enable(filter_ready),
        .pixel_in(gray_blur1),
        .pixel_addr(rdaddress),
        .vsync(vSync),
        .active_area(activeArea),
        .pixel_out(gray_blur2),
        .filter_ready(filter_ready2)
    );

    // 소벨 엣지 검출 (그레이스케일 8비트) - 2차 가우시안 결과 입력
    sobel_3x3_gray8 sobel_inst (
        .clk(clk_25_vga),
        .enable(filter_ready2),
        .pixel_in(gray_blur2),
        .pixel_addr(rdaddress),
        .vsync(vSync),
        .active_area(activeArea),
        .threshold(sobel_threshold),
        .pixel_out(sobel_value),
        .sobel_ready(sobel_ready)
    );

    // 캐니 엣지 검출 (히스테리시스만 적용, NMS 생략) - 2차 가우시안 결과 입력
    wire canny_ready;
    reg  [7:0] canny_thr_low  = 8'd24;  // 기본 낮은 임계
    reg  [7:0] canny_thr_high = 8'd64;  // 기본 높은 임계
    canny_3x3_gray8 canny_inst (
        .clk(clk_25_vga),
        .enable(filter_ready2),
        .pixel_in(gray_blur2),
        .pixel_addr(rdaddress),
        .vsync(vSync),
        .active_area(activeArea),
        .threshold_low(canny_thr_low),
        .threshold_high(canny_thr_high),
        .pixel_out(canny_value),
        .canny_ready(canny_ready)
    );
    
    // 색상 값들 - RGB888 직접 사용
    assign red_value = activeArea ? r_888 : 8'h00;
    assign green_value = activeArea ? g_888 : 8'h00;
    assign blue_value = activeArea ? b_888 : 8'h00;
    
    // 그레이스케일 샤프닝(언샤프 마스크): gray + 0.5*(gray - gray_blur2)
    wire signed [9:0] g_gray  = {2'b00, gray_value};
    wire signed [9:0] g_blur  = {2'b00, gray_blur2};
    wire signed [10:0] g_unsharp_w = g_gray + ((g_gray - g_blur) >>> 1); // 50% 가중
    wire [7:0] unsharp_gray = g_unsharp_w[10] ? 8'd0 : (g_unsharp_w > 11'sd255 ? 8'd255 : g_unsharp_w[7:0]);
    assign filtered_pixel = {unsharp_gray, unsharp_gray, unsharp_gray};
    
    // 스위치에 따른 출력 선택
    wire [7:0] final_r, final_g, final_b;
    
    // 필터 적용된 픽셀에서 RGB 분리 (가우시안 그레이 결과 복제)
    assign filter_r_888 = filtered_pixel[23:16];  // R 채널
    assign filter_g_888 = filtered_pixel[15:8];   // G 채널
    assign filter_b_888 = filtered_pixel[7:0];    // B 채널
    
    // 경로별 지연 인덱스
    localparam integer IDX_ORIG  = PIPE_LATENCY;    // 최종 경로 정렬 인덱스 (6)
    localparam integer IDX_GRAY  = PIPE_LATENCY;    // 최종 경로 정렬 인덱스 (6)
    localparam integer IDX_GAUSS = PIPE_LATENCY - GAUSS_LAT;        // 가우시안 출력 정렬 인덱스 (2)
    localparam integer IDX_SOBEL = 0;                              // 소벨 전용 경로(즉시 출력 경로용) 인덱스
    localparam integer IDX_CANNY = PIPE_LATENCY;    // 캐니는 전체 파이프라인(6클럭) 후에 유효

    // 최종 출력 선택(경로별 인덱스 및 ready 게이팅)
    wire [7:0] sel_orig_r = activeArea_delayed[IDX_ORIG] ? red_value_delayed[IDX_ORIG] : 8'h00;
    wire [7:0] sel_orig_g = activeArea_delayed[IDX_ORIG] ? green_value_delayed[IDX_ORIG] : 8'h00;
    wire [7:0] sel_orig_b = activeArea_delayed[IDX_ORIG] ? blue_value_delayed[IDX_ORIG] : 8'h00;

    wire [7:0] sel_gray   = activeArea_delayed[IDX_GRAY] ? gray_value_delayed[IDX_GRAY] : 8'h00;

    wire [7:0] sel_gauss_r = (activeArea_delayed[IDX_GAUSS] && filter_ready_delayed[IDX_GAUSS]) ? filter_r_delayed[IDX_GAUSS] : 8'h00;
    wire [7:0] sel_gauss_g = (activeArea_delayed[IDX_GAUSS] && filter_ready_delayed[IDX_GAUSS]) ? filter_g_delayed[IDX_GAUSS] : 8'h00;
    wire [7:0] sel_gauss_b = (activeArea_delayed[IDX_GAUSS] && filter_ready_delayed[IDX_GAUSS]) ? filter_b_delayed[IDX_GAUSS] : 8'h00;

    wire [7:0] sel_sobel   = (activeArea_delayed[IDX_SOBEL] && sobel_ready_delayed[IDX_SOBEL]) ? sobel_value_delayed[IDX_SOBEL] : 8'h00;
    wire [7:0] sel_canny   = (activeArea_delayed[IDX_CANNY] && canny_ready_delayed[IDX_CANNY]) ? canny_value_delayed[IDX_CANNY] : 8'h00;

    assign final_r = sw_canny ? sel_canny : (sw_sobel ? sel_sobel :
                     (sw_grayscale ? sel_gray :
                     (sw_filter ? sel_gauss_r : sel_orig_r)));
    assign final_g = sw_canny ? sel_canny : (sw_sobel ? sel_sobel :
                     (sw_grayscale ? sel_gray :
                     (sw_filter ? sel_gauss_g : sel_orig_g)));
    assign final_b = sw_canny ? sel_canny : (sw_sobel ? sel_sobel :
                     (sw_grayscale ? sel_gray :
                     (sw_filter ? sel_gauss_b : sel_orig_b)));
    
    // VGA 출력 연결 (마스킹 제거)
    assign vga_r = final_r;
    assign vga_g = final_g;
    assign vga_b = final_b;
    
    // PLL 인스턴스 - 클럭 생성 (IP 설정 필요)
    // 입력: 50MHz, 출력 c0: 50MHz, c1: 25MHz
    my_altpll pll_inst (
        .inclk0(clk_50),           // 50MHz 입력 클럭
        .c0(clk_24_camera),        // 카메라용 24MHz 클럭
        .c1(clk_25_vga)            // VGA용 25MHz 클럭

    );
    
    // VGA 동기화 신호 지연용 원본 신호
    wire hsync_raw, vsync_raw;

    // VGA 컨트롤러
    VGA vga_inst (
        .CLK25(clk_25_vga),        // 25MHz VGA 클럭
        .pixel_data(rddata),       // 픽셀 데이터 입력
        .clkout(vga_CLK),          // VGA 클럭 출력
        .Hsync(hsync_raw),         // 수평 동기화 (원본)
        .Vsync(vsync_raw),         // 수직 동기화 (원본)
        .Nblank(nBlank),           // 블랭킹 신호
        .Nsync(vga_sync_N),        // 동기화 신호
        .activeArea(activeArea),   // 활성 영역
        .pixel_address(rdaddress)  // 픽셀 주소 출력
    );

    // Hsync/Vsync를 데이터 경로 지연과 일치시키기 위한 파이프라인 (6클럭 지연)
    reg [5:0] hsync_delay_pipe = 6'b0;
    reg [5:0] vsync_delay_pipe = 6'b0;
    always @(posedge clk_25_vga) begin
        hsync_delay_pipe <= {hsync_delay_pipe[4:0], hsync_raw};
        vsync_delay_pipe <= {vsync_delay_pipe[4:0], vsync_raw};
    end

    assign vga_hsync = hsync_delay_pipe[5];
    assign vga_vsync = vsync_delay_pipe[5];
    
    // OV7670 카메라 컨트롤러
    ov7670_controller camera_ctrl (
        .clk_50(clk_50),           // 50MHz 카메라 클럭
        .clk_24(clk_24_camera),    // 24MHz 카메라 클럭
        .resend(resend),           // 설정 재시작
        .config_finished(led_config_finished),  // 설정 완료 LED
        .sioc(ov7670_sioc),        // I2C 클럭
        .siod(ov7670_siod),        // I2C 데이터
        .reset(ov7670_reset),      // 카메라 리셋
        .pwdn(ov7670_pwdn),        // 카메라 파워다운
        .xclk(ov7670_xclk)         // 카메라 시스템 클럭
    );
    
    // OV7670 캡처 모듈
    ov7670_capture #(
        .H_SKIP_LEFT(8),
        .H_SKIP_RIGHT(8),
        .V_SKIP_TOP(4),
        .V_SKIP_BOTTOM(4)
    ) capture_inst (
        .pclk(ov7670_pclk),        // 픽셀 클럭
        .vsync(ov7670_vsync),      // 수직 동기화
        .href(ov7670_href),        // 수평 참조
        .d(ov7670_data),           // 픽셀 데이터
        .addr(wraddress),          // RAM 쓰기 주소
        .dout(wrdata),             // RAM 쓰기 데이터
        .we(wren)                  // RAM 쓰기 활성화
    );
    
    // 읽기 주소 동기화
    wire [16:0] rdaddress_sync = rdaddress;

    // 듀얼 프레임 버퍼 RAM들 - 각각 32K x 12비트로 구성
    // RAM1: 이미지의 첫 번째 절반 저장 (픽셀 0-32767)
    frame_buffer_ram buffer_ram1 (
        .data(wrdata_ram1),         // 쓰기 데이터
        .wraddress(wraddress_ram1), // 쓰기 주소
        .wrclock(ov7670_pclk),      // 쓰기 클럭 (카메라 픽셀 클럭)
        .wren(wren_ram1),           // 쓰기 활성화
        .rdaddress(rdaddress_sync[15:0]), // 읽기 주소 (동기화)
        .rdclock(clk_25_vga),       // 읽기 클럭 (VGA 클럭)
        .q(rddata_ram1)             // 읽기 데이터
    );
    
    // RAM2: 이미지의 두 번째 절반 저장 (픽셀 32768-76799)
    frame_buffer_ram buffer_ram2 (
        .data(wrdata_ram2),         // 쓰기 데이터
        .wraddress(wraddress_ram2), // 쓰기 주소
        .wrclock(ov7670_pclk),      // 쓰기 클럭 (카메라 픽셀 클럭)
        .wren(wren_ram2),           // 쓰기 활성화
        .rdaddress(rdaddress_sync[15:0]), // 읽기 주소 (동기화)
        .rdclock(clk_25_vga),       // 읽기 클럭 (VGA 클럭)
        .q(rddata_ram2)             // 읽기 데이터
    );
    
    
    
endmodule