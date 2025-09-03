// ============================================
// Top Module - DE2-115 VGA Test
// ============================================
module vga_top (
    input wire CLOCK_50,           // FPGA 보드 내부 50MHz 메인 클럭
    input wire [3:0] KEY,          // 보드의 푸시 버튼 입력 (KEY[0]은 리셋으로 사용)
    input wire [17:0] SW,          // 슬라이드 스위치 입력 (패턴/색상 제어용)
    
    // VGA 출력 신호
    output wire VGA_CLK,           // VGA 픽셀 클럭 (25MHz 필요)
    output wire VGA_HS,            // VGA 수평 동기 신호 (H_SYNC)
    output wire VGA_VS,            // VGA 수직 동기 신호 (V_SYNC)
    output wire VGA_BLANK_N,       // VGA 표시 가능 여부 (high=활성)
    output wire VGA_SYNC_N,        // VGA 동기 신호 (보통 사용안함)
    output wire [7:0] VGA_R,       // VGA RGB Red 채널 (8bit)
    output wire [7:0] VGA_G,       // VGA RGB Green 채널 (8bit)
    output wire [7:0] VGA_B        // VGA RGB Blue 채널 (8bit)
);

    // 내부 연결 신호 선언
    wire clk_25MHz;                // VGA용 25MHz 클럭
    wire reset_n;                  // 동기화 리셋 (active low)
    wire [9:0] h_count;            // 현재 픽셀의 X 좌표 (0~799)
    wire [9:0] v_count;            // 현재 픽셀의 Y 좌표 (0~524)
    wire h_sync;                   // 수평 동기 신호
    wire v_sync;                   // 수직 동기 신호
    wire video_on;                 // 실제 화면 출력 구간인지 여부
    wire [7:0] red, green, blue;   // 픽셀 RGB 값 (패턴 or 나중에 카메라 데이터)

    // KEY[0]을 reset_n에 연결 (누르면 0, 놓으면 1)
    assign reset_n = KEY[0];
    
    // VGA 출력 연결
    assign VGA_CLK     = clk_25MHz;    // VGA에 25MHz 픽셀 클럭 공급
    assign VGA_BLANK_N = video_on;     // 표시할 구간에서만 on
    assign VGA_SYNC_N  = 1'b0;         // composite sync는 사용하지 않음
    
    // =============================
    // 50MHz 입력 클럭을 25MHz로 divide
    // VGA 640x480 @ 60Hz 모드에 맞는 픽셀 클럭 생성
    // =============================
    clk_divider clk_div (
        .clk_in(CLOCK_50),
        .reset_n(reset_n),
        .clk_out(clk_25MHz)
    );
    
    // =============================
    // VGA 컨트롤러 : VGA 타이밍 생성
    // h_count, v_count = 현재 픽셀 좌표
    // h_sync, v_sync   = VGA 동기 신호
    // video_on         = 표시 영역(640x480)인지 여부
    // =============================
    vga_controller vga_ctrl (
        .clk(clk_25MHz),
        .reset_n(reset_n),
        .h_sync(h_sync),
        .v_sync(v_sync),
        .video_on(video_on),
        .h_count(h_count),
        .v_count(v_count)
    );
    
    // =============================
    // 간단한 패턴 생성기
    // h_count, v_count 값에 따라 색상을 선택
    // SW 스위치로 여러 가지 패턴 모드 실험 가능
    // =============================
    pattern_generator pattern_gen (
        .clk(clk_25MHz),
        .reset_n(reset_n),
        .h_count(h_count),
        .v_count(v_count),
        .video_on(video_on),
        .sw(SW),
        .red(red),
        .green(green),
        .blue(blue)
    );
    
    // 출력 연결 : 패턴 출력 → VGA 신호
    assign VGA_HS = h_sync;
    assign VGA_VS = v_sync;
    assign VGA_R  = red;
    assign VGA_G  = green;
    assign VGA_B  = blue;

endmodule