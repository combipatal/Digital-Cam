// OV7670 카메라 인터페이스 최상위 모듈
// 카메라 캡처, 프레임 버퍼, VGA 디스플레이를 통합한 메인 모듈
module digital_cam_top (
    input  wire        clk_50,         // 50MHz 시스템 클럭
    input  wire        btn_resend,     // 카메라 설정 재시작 버튼
    input  wire        sw_grayscale,   // SW[0] 그레이스케일 모드 스위치
    input  wire        sw_sobel,       // SW[1] 소벨 필터 모드 스위치
    input  wire        sw_filter,      // SW[2] 디지털 필터 모드 스위치
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
    
    // 신호 연결
    assign resend = btn_rising_edge;  // 버튼 상승 에지에서 리셋 펄스 전송
    assign vga_vsync = vSync;         // VGA 수직 동기화 연결
    assign vga_blank_N = nBlank;      // VGA 블랭킹 신호 연결
    
    // 듀얼 프레임 버퍼 - 320x240 = 76800 픽셀을 두 개의 RAM으로 분할
    // RAM1: 주소 0-32767 (첫 번째 절반) - 32K RAM
    // RAM2: 주소 32768-76799 (두 번째 절반) - 44K RAM
    
    // 쓰기 주소 할당
    assign wraddress_ram1 = wraddress[15:0];  // RAM1: 0-32767 (16비트)
    assign wraddress_ram2 = wraddress[15:0] - 16'd32768;  // RAM2: 0-44031 (오프셋 적용)
    assign wrdata_ram1 = wrdata;              // RAM1 쓰기 데이터
    assign wrdata_ram2 = wrdata;              // RAM2 쓰기 데이터
    assign wren_ram1 = wren & ~wraddress[16]; // 주소 < 32768일 때 RAM1에 쓰기
    assign wren_ram2 = wren & wraddress[16];  // 주소 >= 32768일 때 RAM2에 쓰기
    
    // 읽기 주소 할당
    assign rdaddress_ram1 = rdaddress[15:0];  // RAM1: 0-32767 (16비트)
    assign rdaddress_ram2 = rdaddress[15:0] - 16'd32768;  // RAM2: 0-44031 (오프셋 적용)
    
    // 읽기 데이터 멀티플렉싱 - 상위 비트에 따라 어느 RAM에서 읽을지 결정
    assign rddata = rdaddress[16] ? rddata_ram2 : rddata_ram1;
    
    // RGB 변환 및 그레이스케일, 소벨 필터, 디지털 필터 모드
    wire [7:0] gray_value;           // 그레이스케일 값
    wire [7:0] red_value, green_value, blue_value;  // RGB 값들
    wire [7:0] sobel_value;          // 소벨 필터 값 (그레이스케일)
    wire [23:0] filtered_pixel;      // 디지털 필터 적용된 픽셀 (RGB888) - 그레이 복제
    wire filter_ready;               // 필터 처리 완료 신호
    wire sobel_ready;                // 소벨 처리 완료 신호 (선언을 앞당겨 사용 이전에 배치)
    
    // RGB565 → RGB888 직접 변환 (화질 최적화)
    // RGB565: R[15:11] G[10:5] B[4:0]
    // RGB888: R[7:0] G[7:0] B[7:0]
    wire [7:0] r_888, g_888, b_888;  // RGB888로 확장된 값들
    
    assign r_888 = {rddata[15:11], 3'b111};  // 5비트 → 8비트 (x8 + 7) - 더 밝게
    assign g_888 = {rddata[10:5], 2'b11};    // 6비트 → 8비트 (x4 + 3) - 더 밝게
    assign b_888 = {rddata[4:0], 3'b111};    // 5비트 → 8비트 (x8 + 7) - 더 밝게
    
    // RGB888을 하나의 24비트 픽셀로 결합 (필터 입력용)
    wire [23:0] rgb888_pixel = {r_888, g_888, b_888};
    
    // 그레이스케일 계산 (RGB888 기준) - 개선된 정확도
    wire [10:0] gray_sum;            // 그레이스케일 합계 (더 큰 비트폭)
    // Y = 0.299*R + 0.587*G + 0.114*B (ITU-R BT.709 표준)
    // 더 정확한 정수 연산: Y = (76*R + 150*G + 30*B) / 256
    assign gray_sum = (r_888 << 6) + (r_888 << 3) + (r_888 << 2) +  // 76*R
                     (g_888 << 7) + (g_888 << 4) + (g_888 << 2) + (g_888 << 1) +  // 150*G
                     (b_888 << 4) + (b_888 << 3) + (b_888 << 1);  // 30*B
    assign gray_value = activeArea ? gray_sum[10:3] : 8'h00;  // >> 3 (8로 나누기)
    
    // 가우시안 필터는 소벨 필터 내부에서 처리되므로 이 변수들은 사용하지 않음
    
    // 파이프라인 지연: 정상 상태 총 4클럭 (가우시안 2 + 소벨 2)
    localparam integer PIPE_LATENCY = 4;                // pipeline latency
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
    integer i; 
    
	 // 파이프라인 정렬: 정상 상태 기준 PIPE_LATENCY 클럭 지연 체인
    always @(posedge clk_25_vga) begin
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
        end
    end

    // 가우시안 블러 (그레이스케일 8비트)
    wire [7:0] gray_blur;
    gaussian_3x3_gray8 filter_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_value),
        .pixel_addr(rdaddress),
        .vsync(vSync),
        .active_area(activeArea),
        .pixel_out(gray_blur),
        .filter_ready(filter_ready)
    );

    // 소벨 엣지 검출 (그레이스케일 8비트) - 가우시안 결과 입력
    sobel_3x3_gray8 sobel_inst (
        .clk(clk_25_vga),
        .enable(1'b1),
        .pixel_in(gray_blur),
        .pixel_addr(rdaddress),
        .vsync(vSync),
        .active_area(activeArea),
        .pixel_out(sobel_value),
        .sobel_ready(sobel_ready)
    );
    
    // 색상 값들 - RGB888 직접 사용
    assign red_value = activeArea ? r_888 : 8'h00;
    assign green_value = activeArea ? g_888 : 8'h00;
    assign blue_value = activeArea ? b_888 : 8'h00;
    
    // 그레이스케일 필터 + 가우시안 필터 적용된 픽셀
    assign filtered_pixel = {gray_blur, gray_blur, gray_blur};
    
    // 스위치에 따른 출력 선택
    wire [7:0] final_r, final_g, final_b;
    
    // 필터 적용된 픽셀에서 RGB 분리 (가우시안 그레이 결과 복제)
    wire [7:0] filter_r_888, filter_g_888, filter_b_888;
    assign filter_r_888 = filtered_pixel[23:16];  // R 채널
    assign filter_g_888 = filtered_pixel[15:8];   // G 채널
    assign filter_b_888 = filtered_pixel[7:0];    // B 채널
    
    // 우선순위: 소벨(가우시안 전처리) > 그레이스케일 > 가우시안 필터 > 원본
    // 정렬 원칙: 최종 출력 시점은 주소 등 기준 신호를 PIPE_IDX만큼 지연시킨 시점
    // - 소벨은 내부 파이프라인 지연이 STEADY_LATENCY(현재 3클럭)이므로 추가 지연은 PIPE_IDX-STEADY_LATENCY만 적용
    // 최종 출력 선택: 소벨은 원본(sobel_value) 사용, 나머지는 PIPE_LATENCY 정렬 사용
    assign final_r = sw_sobel ? sobel_value : 
                     (sw_grayscale ? gray_value_delayed[PIPE_LATENCY] : 
                      (sw_filter ? filter_r_delayed[PIPE_LATENCY] : red_value_delayed[PIPE_LATENCY]));
    assign final_g = sw_sobel ? sobel_value : 
                     (sw_grayscale ? gray_value_delayed[PIPE_LATENCY] : 
                      (sw_filter ? filter_g_delayed[PIPE_LATENCY] : green_value_delayed[PIPE_LATENCY]));
    assign final_b = sw_sobel ? sobel_value : 
                     (sw_grayscale ? gray_value_delayed[PIPE_LATENCY] : 
                      (sw_filter ? filter_b_delayed[PIPE_LATENCY] : blue_value_delayed[PIPE_LATENCY]));
    
    // VGA 출력 연결
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
    
    // VGA 컨트롤러
    VGA vga_inst (
        .CLK25(clk_25_vga),        // 25MHz VGA 클럭
        .clkout(vga_CLK),          // VGA 클럭 출력
        .Hsync(vga_hsync),         // 수평 동기화
        .Vsync(vSync),             // 수직 동기화
        .Nblank(nBlank),           // 블랭킹 신호
        .Nsync(vga_sync_N),        // 동기화 신호
        .activeArea(activeArea)    // 활성 영역
    );
    
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
    ov7670_capture capture_inst (
        .pclk(ov7670_pclk),        // 픽셀 클럭
        .vsync(ov7670_vsync),      // 수직 동기화
        .href(ov7670_href),        // 수평 참조
        .d(ov7670_data),           // 픽셀 데이터
        .addr(wraddress),          // RAM 쓰기 주소
        .dout(wrdata),             // RAM 쓰기 데이터
        .we(wren)                  // RAM 쓰기 활성화
    );
    
    // 듀얼 프레임 버퍼 RAM들 - 각각 32K x 12비트로 구성
    // RAM1: 이미지의 첫 번째 절반 저장 (픽셀 0-32767)
    frame_buffer_ram buffer_ram1 (
        .data(wrdata_ram1),         // 쓰기 데이터
        .wraddress(wraddress_ram1), // 쓰기 주소
        .wrclock(ov7670_pclk),      // 쓰기 클럭 (카메라 픽셀 클럭)
        .wren(wren_ram1),           // 쓰기 활성화
        .rdaddress(rdaddress_ram1), // 읽기 주소
        .rdclock(clk_25_vga),       // 읽기 클럭 (VGA 클럭)
        .q(rddata_ram1)             // 읽기 데이터
    );
    
    // RAM2: 이미지의 두 번째 절반 저장 (픽셀 32768-76799)
    frame_buffer_ram buffer_ram2 (
        .data(wrdata_ram2),         // 쓰기 데이터
        .wraddress(wraddress_ram2), // 쓰기 주소
        .wrclock(ov7670_pclk),      // 쓰기 클럭 (카메라 픽셀 클럭)
        .wren(wren_ram2),           // 쓰기 활성화
        .rdaddress(rdaddress_ram2), // 읽기 주소
        .rdclock(clk_25_vga),       // 읽기 클럭 (VGA 클럭)
        .q(rddata_ram2)             // 읽기 데이터
    );
    
    // 읽기용 주소 생성기
    Address_Generator addr_gen (
        .CLK25(clk_25_vga),         // 25MHz VGA 클럭
        .enable(activeArea),        // 활성 영역에서만 주소 생성
        .vsync(vSync),              // 수직 동기화
        .address(rdaddress)         // 읽기 주소 출력
    );
    
endmodule