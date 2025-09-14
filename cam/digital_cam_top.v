// OV7670 카메라 인터페이스 최상위 모듈
// 카메라 캡처, 프레임 버퍼, VGA 디스플레이를 통합한 메인 모듈
module digital_cam_top (
    input  wire        clk_50,         // 50MHz 시스템 클럭
    input  wire        btn_resend,     // 카메라 설정 재시작 버튼
    input  wire        sw_grayscale,   // SW[0] 그레이스케일 모드 스위치
    input  wire        sw_sobel,       // SW[1] 소벨 필터 모드 스위치
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
    wire clk_50_camera;  // 카메라용 50MHz 클럭
    wire clk_25_vga;     // VGA용 25MHz 클럭
    wire wren;           // RAM 쓰기 활성화
    wire resend;         // 카메라 설정 재시작
    wire nBlank;         // VGA 블랭킹 신호
    wire vSync;          // VGA 수직 동기화
    wire [16:0] wraddress;  // RAM 쓰기 주소
    wire [11:0] wrdata;     // RAM 쓰기 데이터
    wire [16:0] rdaddress;  // RAM 읽기 주소
    wire [11:0] rddata;     // RAM 읽기 데이터
    wire activeArea;        // VGA 활성 영역
    
    // 듀얼 프레임 버퍼 신호들 (320x240 = 76800 픽셀을 두 개의 RAM으로 분할)
    wire [15:0] wraddress_ram1, rdaddress_ram1; // RAM1: 16비트 주소 (0-32767)
    wire [15:0] wraddress_ram2, rdaddress_ram2; // RAM2: 16비트 주소 (0-44031)
    wire [11:0] wrdata_ram1, wrdata_ram2;       // 각 RAM의 쓰기 데이터
    wire wren_ram1, wren_ram2;                  // 각 RAM의 쓰기 활성화
    wire [11:0] rddata_ram1, rddata_ram2;       // 각 RAM의 읽기 데이터
    
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
    
    // RGB 변환 및 그레이스케일, 소벨 필터 모드
    wire [7:0] gray_value;           // 그레이스케일 값
    wire [7:0] red_value, green_value, blue_value;  // RGB 값들
    wire [7:0] sobel_value;          // 소벨 필터 값
    
    // 시프트 연산을 사용한 그레이스케일 값 계산
    // Y = (R + 2*G + B) >> 2 (4로 나누는 것과 동일)
    wire [7:0] r_ext, g_ext, b_ext;  // 확장된 RGB 값들
    wire [8:0] gray_sum;             // 그레이스케일 합계
    
    assign r_ext = {rddata[11:8], 4'b0000};  // R을 8비트로 확장
    assign g_ext = {rddata[7:4], 4'b0000};   // G을 8비트로 확장
    assign b_ext = {rddata[3:0], 4'b0000};   // B를 8비트로 확장
    
    assign gray_sum = r_ext + g_ext + g_ext + b_ext;  // R + 2*G + B
    assign gray_value = activeArea ? gray_sum[8:2] : 8'h00;  // >> 2 (4로 나누기)
    
    // 소벨 엣지 검출 필터
    // 이는 단순화된 버전 - 완전한 구현을 위해서는 라인 버퍼가 필요
    reg [7:0] prev_gray = 8'h00;  // 이전 그레이스케일 값
    wire [7:0] edge_magnitude;    // 엣지 강도
    
    always @(posedge clk_25_vga) begin
        if (activeArea) begin
            prev_gray <= gray_value;  // 현재 그레이스케일 값을 이전 값으로 저장
        end
    end
    
    // 단순한 엣지 검출: |현재 - 이전|
    assign edge_magnitude = (gray_value > prev_gray) ? (gray_value - prev_gray) : (prev_gray - gray_value);
    assign sobel_value = activeArea ? edge_magnitude : 8'h00;
    
    // 색상 값들 - 4비트를 8비트로 확장
    assign red_value = activeArea ? {rddata[11:8], 4'b1111} : 8'h00;
    assign green_value = activeArea ? {rddata[7:4], 4'b1111} : 8'h00;
    assign blue_value = activeArea ? {rddata[3:0], 4'b1111} : 8'h00;
    
    // 스위치에 따른 출력 선택
    wire [7:0] final_r, final_g, final_b;
    assign final_r = sw_sobel ? sobel_value : (sw_grayscale ? gray_value : red_value);
    assign final_g = sw_sobel ? sobel_value : (sw_grayscale ? gray_value : green_value);
    assign final_b = sw_sobel ? sobel_value : (sw_grayscale ? gray_value : blue_value);
    
    // VGA 출력 연결
    assign vga_r = final_r;
    assign vga_g = final_g;
    assign vga_b = final_b;
    
    // PLL 인스턴스 - 클럭 생성 (IP 설정 필요)
    // 입력: 50MHz, 출력 c0: 50MHz, c1: 25MHz
    my_altpll pll_inst (
        .inclk0(clk_50),           // 50MHz 입력 클럭
        .c0(clk_50_camera),        // 카메라용 50MHz 클럭
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
        .clk(clk_50_camera),       // 50MHz 카메라 클럭
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