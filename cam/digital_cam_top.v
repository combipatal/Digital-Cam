// 디지털 카메라 시스템 최상위 모듈
// OV7670 카메라 인터페이스, 이미지 처리 파이프라인, 프레임 버퍼, VGA 디스플레이 제어를 통합합니다.
module digital_cam_top (
    // 시스템 입력
    input  wire        clk_50,         // 50MHz 시스템 클럭
    input  wire        btn_resend,     // 카메라 설정 재전송 버튼 (Active Low)
    input  wire        btn_thr_up,     // 소벨 임계값 증가 버튼 (Active Low)
    input  wire        btn_thr_down,   // 소벨 임계값 감소 버튼 (Active Low)
    input  wire        sw_grayscale,   // SW[0] 그레이스케일 모드 스위치
    input  wire        sw_sobel,       // SW[1] 소벨 필터 모드 스위치
    input  wire        sw_filter,      // SW[2] 가우시안 필터 모드 스위치
    
    // 시스템 출력
    output wire        led_config_finished, // 카메라 설정 완료 표시 LED
    
    // VGA 출력 신호
    output wire        vga_hsync,      // VGA 수평 동기화
    output wire        vga_vsync,      // VGA 수직 동기화
    output wire [7:0]  vga_r,          // VGA Red 채널 (8비트)
    output wire [7:0]  vga_g,          // VGA Green 채널 (8비트)
    output wire [7:0]  vga_b,          // VGA Blue 채널 (8비트)
    output wire        vga_blank_N,    // VGA 블랭킹 신호 (Active High)
    output wire        vga_sync_N,     // VGA 동기화 신호 (TFT용, 여기선 미사용)
    output wire        vga_CLK,        // VGA 픽셀 클럭 (25.175MHz)
    
    // OV7670 카메라 인터페이스
    input  wire        ov7670_pclk,    // 카메라 픽셀 클럭
    output wire        ov7670_xclk,    // 카메라 시스템 클럭 (24MHz)
    input  wire        ov7670_vsync,   // 카메라 수직 동기화
    input  wire        ov7670_href,    // 카메라 수평 참조
    input  wire [7:0]  ov7670_data,    // 카메라 픽셀 데이터 (8비트)
    output wire        ov7670_sioc,    // I2C 클럭
    inout  wire        ov7670_siod,    // I2C 데이터
    output wire        ov7670_pwdn,    // 카메라 파워다운
    output wire        ov7670_reset    // 카메라 리셋
);

    // --- 내부 신호 선언 ---
    // 클럭 신호
    wire clk_24_camera;  // 카메라용 24MHz 클럭
    wire clk_25_vga;     // VGA용 25.175MHz 클럭

    // 프레임 버퍼 인터페이스 신호
    wire wren;           // RAM 쓰기 활성화
    wire [16:0] wraddress;  // RAM 쓰기 주소 (320*240 = 76800)
    wire [15:0] wrdata;     // RAM 쓰기 데이터 (RGB565)
    wire [16:0] rdaddress;  // RAM 읽기 주소
    wire [15:0] rddata;     // RAM 읽기 데이터 (RGB565)

    // VGA 컨트롤러 신호
    wire vga_active_area; // VGA 유효 영상 영역
    wire vga_vsync_raw;   // 지연되지 않은 원본 Vsync

    // 이미지 처리 파이프라인 신호
    wire [7:0] gray_value;      // 그레이스케일 변환 결과
    wire [7:0] r_888, g_888, b_888; // RGB565 to RGB888 변환 결과
    
    wire [7:0] gray_blur1;      // 1차 가우시안 블러 결과
    wire [7:0] gray_blur2;      // 2차 가우시안 블러 결과
    wire [7:0] sobel_out;       // 소벨 필터 결과
    
    wire ready_blur1;         // 1차 가우시안 필터 유효
    wire ready_blur2;         // 2차 가우시안 필터 유효
    wire ready_sobel;         // 소벨 필터 유효

    // 소벨 임계값
    reg [7:0] sobel_threshold; // 소벨 필터 임계값 레지스터
    wire      thr_up_pulse;   // 임계값 증가 펄스
    wire      thr_down_pulse; // 임계값 감소 펄스


    // --- 버튼 디바운싱 ---
    wire resend; // 카메라 설정 재전송 펄스
    debounce #( .WIDTH(1), .POLARITY(0) ) BTN_RESEND_DEBOUNCER ( .clk(clk_50), .button_in(~btn_resend), .button_pulse(resend) );
    debounce #( .WIDTH(1), .POLARITY(0) ) BTN_THR_UP_DEBOUNCER   ( .clk(clk_50), .button_in(~btn_thr_up),   .button_pulse(thr_up_pulse) );
    debounce #( .WIDTH(1), .POLARITY(0) ) BTN_THR_DOWN_DEBOUNCER ( .clk(clk_50), .button_in(~btn_thr_down), .button_pulse(thr_down_pulse) );

    // --- 소벨 임계값 제어 로직 ---
    always @(posedge clk_50) begin
        if (resend) begin // 리셋 (카메라 재설정 시)
            sobel_threshold <= 8'd50; // 기본값으로 초기화
        end else if (thr_up_pulse) begin
            if (sobel_threshold < 8'd255) // 최대값 255
                sobel_threshold <= sobel_threshold + 8;
        end else if (thr_down_pulse) begin
            if (sobel_threshold > 8'd0) // 최소값 0
                sobel_threshold <= sobel_threshold - 8;
        end
    end
    
    // --- 듀얼 프레임 버퍼 로직 ---
    // 320x240 = 76800 픽셀을 두 개의 RAM으로 분할 (각 32K x 16bit)
    // RAM1: 주소 0 ~ 32767
    // RAM2: 주소 32768 ~ 76799
    wire [15:0] wraddress_ram1, wraddress_ram2;
    wire [15:0] rdaddress_ram1, rdaddress_ram2;
    wire [15:0] rddata_ram1, rddata_ram2;
    wire wren_ram1, wren_ram2;

    assign wraddress_ram1 = wraddress[15:0];
    assign wraddress_ram2 = wraddress[15:0] - 16'd32768; // 주소 오프셋
    assign wren_ram1 = wren & ~wraddress[16]; // 상위 비트가 0일 때
    assign wren_ram2 = wren &  wraddress[16]; // 상위 비트가 1일 때

    assign rdaddress_ram1 = rdaddress[15:0];
    assign rdaddress_ram2 = rdaddress[15:0] - 16'd32768; // 주소 오프셋
    assign rddata = rdaddress[16] ? rddata_ram2 : rddata_ram1;

    
    // --- 이미지 포맷 변환 ---
    // RAM에서 읽어온 RGB565 데이터를 RGB888로 변환
    assign r_888 = {rddata[15:11], rddata[15:13]}; // 5bit -> 8bit
    assign g_888 = {rddata[10:5],  rddata[10:9]};  // 6bit -> 8bit
    assign b_888 = {rddata[4:0],   rddata[4:2]};   // 5bit -> 8bit

    // 그레이스케일 변환 (Y = 0.299R + 0.587G + 0.114B)
    // 정수 근사 연산: Y = (77*R + 150*G + 29*B) >> 8
    wire [16:0] gray_sum;
    // 곱셈을 시프트와 덧셈 연산으로 대체하여 하드웨어 효율성 향상
    assign gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) + r_888      // 77*R = (64+8+4+1)*R
                   + (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) // 150*G = (128+16+4+2)*G
                   + (b_888 << 4) + (b_888 << 3) + (b_888 << 2) + b_888;     // 29*B = (16+8+4+1)*B
    assign gray_value = vga_active_area ? gray_sum[15:8] : 8'h00;


    // --- 파이프라인 지연 보상 ---
    // 각 필터의 지연 시간(Latency) 정의
    localparam GAUSS_LAT = 2; // 가우시안 필터 지연 (라인버퍼+연산)
    localparam SOBEL_LAT = 2; // 소벨 필터 지연

    // 파이프라인 총 지연 시간
    localparam PIPE_LAT_BLUR1 = GAUSS_LAT;                      // 2
    localparam PIPE_LAT_BLUR2 = PIPE_LAT_BLUR1 + GAUSS_LAT;     // 4
    localparam PIPE_LAT_SOBEL = PIPE_LAT_BLUR2 + SOBEL_LAT;     // 6
    localparam MAX_LATENCY    = PIPE_LAT_SOBEL;                // 최대 지연 시간: 6

    // 신호 지연을 위한 레지스터 배열
    reg [MAX_LATENCY-1:0] active_area_pipe;
    reg [7:0] r_pipe [MAX_LATENCY-1:0], g_pipe [MAX_LATENCY-1:0], b_pipe [MAX_LATENCY-1:0];
    reg [7:0] gray_pipe [MAX_LATENCY-1:0];
    reg [7:0] blur2_pipe [MAX_LATENCY-1:0];
    reg [7:0] sobel_pipe [MAX_LATENCY-1:0];
    reg ready_blur2_pipe [MAX_LATENCY-1:0];
    reg ready_sobel_pipe [MAX_LATENCY-1:0];

    integer i;

    // 파이프라인 레지스터 동작
    always @(posedge clk_25_vga) begin
        // 0단계: 현재 신호 입력
        active_area_pipe <= {active_area_pipe[MAX_LATENCY-2:0], vga_active_area};        

        for (i = 0; i < MAX_LATENCY; i = i + 1) begin
            r_pipe[i] <= (i == 0) ? r_888 : r_pipe[i-1];
            g_pipe[i] <= (i == 0) ? g_888 : g_pipe[i-1];
            b_pipe[i] <= (i == 0) ? b_888 : b_pipe[i-1];
            gray_pipe[i] <= (i == 0) ? gray_value : gray_pipe[i-1];
            blur2_pipe[i] <= (i == 0) ? gray_blur2 : blur2_pipe[i-1];
            sobel_pipe[i] <= (i == 0) ? sobel_out  : sobel_pipe[i-1];
            ready_blur2_pipe[i] <= (i == 0) ? ready_blur2 : ready_blur2_pipe[i-1];
            ready_sobel_pipe[i] <= (i == 0) ? ready_sobel : ready_sobel_pipe[i-1];
        end
    end


    // --- 이미지 처리 필터 인스턴스 ---
    // 1차 가우시안 블러 (노이즈 제거)
    gaussian_3x3_gray8 gauss1 (
        .clk(clk_25_vga), 
        .enable(1'b1), 
        .pixel_in(gray_value),
        .pixel_addr(rdaddress), 
        .vsync(vga_vsync_raw), 
        .active_area(vga_active_area),
        .pixel_out(gray_blur1), 
        .filter_ready(ready_blur1)
    );

    // 2차 가우시안 블러 (더 강한 블러 효과)
    gaussian_3x3_gray8 gauss2 (
        .clk(clk_25_vga), 
        .enable(ready_blur1), 
        .pixel_in(gray_blur1),
        .pixel_addr(rdaddress), 
        .vsync(vga_vsync_raw), 
        .active_area(vga_active_area),
        .pixel_out(gray_blur2), 
        .filter_ready(ready_blur2)
    );

    // 소벨 엣지 검출
    sobel_3x3_gray8 sobel (
        .clk(clk_25_vga), 
        .enable(ready_blur2), 
        .pixel_in(gray_blur2),
        .pixel_addr(rdaddress), 
        .vsync(vga_vsync_raw), 
        .active_area(vga_active_area),
        .threshold(sobel_threshold),
        .pixel_out(sobel_out), 
        .sobel_ready(ready_sobel)
    );


    // --- 최종 출력 선택 ---
    wire [7:0] final_r, final_g, final_b;
    
    // 지연된 신호 중에서 선택
    wire active_final = active_area_pipe[MAX_LATENCY-1];
    wire ready_blur2_final = ready_blur2_pipe[PIPE_LAT_BLUR2-1];
    wire ready_sobel_final = ready_sobel_pipe[PIPE_LAT_SOBEL-1];

    // 원본 RGB
    wire [7:0] orig_r = active_final ? r_pipe[MAX_LATENCY-1] : 8'h00;
    wire [7:0] orig_g = active_final ? g_pipe[MAX_LATENCY-1] : 8'h00;
    wire [7:0] orig_b = active_final ? b_pipe[MAX_LATENCY-1] : 8'h00;
    // 그레이스케일
    wire [7:0] gray_final = active_final ? gray_pipe[MAX_LATENCY-1] : 8'h00;
    // 가우시안 필터
    wire [7:0] gauss_final = (active_area_pipe[PIPE_LAT_BLUR2-1] && ready_blur2_final) ? blur2_pipe[PIPE_LAT_BLUR2-1] : 8'h00;
    // 소벨 필터
    wire [7:0] sobel_final = (active_area_pipe[PIPE_LAT_SOBEL-1] && ready_sobel_final) ? sobel_pipe[PIPE_LAT_SOBEL-1] : 8'h00;

    // 스위치 값에 따라 최종 출력 결정
    assign final_r = sw_sobel     ? sobel_final :
                     sw_filter    ? gauss_final :
                     sw_grayscale ? gray_final  :
                                    orig_r;
    assign final_g = sw_sobel     ? sobel_final :
                     sw_filter    ? gauss_final :
                     sw_grayscale ? gray_final  :
                                    orig_g;
    assign final_b = sw_sobel     ? sobel_final :
                     sw_filter    ? gauss_final :
                     sw_grayscale ? gray_final  :
                                    orig_b;

    // VGA 출력 연결
    assign vga_r = final_r;
    assign vga_g = final_g;
    assign vga_b = final_b;
    assign vga_blank_N = vga_active_area;


    // --- 모듈 인스턴스화 ---
    // PLL: 50MHz -> 24MHz (카메라), 25.175MHz (VGA)
    my_altpll pll_inst (
        .inclk0(clk_50), 
        .c0(clk_24_camera), 
        .c1(clk_25_vga)
    );
    
    // VGA 컨트롤러
    VGA vga_inst (
        .CLK25(clk_25_vga), 
        .pixel_data(rddata), 
        .clkout(vga_CLK),
        .Hsync(vga_hsync_raw), 
        .Vsync(vga_vsync_raw),
        .Nblank(vga_blank_N_raw), 
        .Nsync(vga_sync_N),
        .activeArea(vga_active_area), 
        .pixel_address(rdaddress)
    );

    // Hsync/Vsync 파이프라인 지연 (MAX_LATENCY)
    reg [MAX_LATENCY-1:0] hsync_pipe, vsync_pipe;
    always @(posedge clk_25_vga) begin
        hsync_pipe <= {hsync_pipe[MAX_LATENCY-2:0], vga_hsync_raw};
        vsync_pipe <= {vsync_pipe[MAX_LATENCY-2:0], vga_vsync_raw};
    end
    assign vga_hsync = hsync_pipe[MAX_LATENCY-1];
    assign vga_vsync = vsync_pipe[MAX_LATENCY-1];
    
    // OV7670 카메라 컨트롤러 (I2C 설정)
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
    
    // 듀얼 프레임 버퍼 RAM
    frame_buffer_ram ram1 (
        .data(wrdata), 
        .wraddress(wraddress_ram1), 
        .wrclock(ov7670_pclk), 
        .wren(wren_ram1),
        .rdaddress(rdaddress_ram1), 
        .rdclock(clk_25_vga), 
        .q(rddata_ram1)
    );
    frame_buffer_ram ram2 (
        .data(wrdata), 
        .wraddress(wraddress_ram2), 
        .wrclock(ov7670_pclk), 
        .wren(wren_ram2),
        .rdaddress(rdaddress_ram2), 
        .rdclock(clk_25_vga), 
        .q(rddata_ram2)
    );

endmodule