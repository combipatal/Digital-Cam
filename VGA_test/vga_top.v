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

// ============================================
// Clock Divider Module (50MHz → 25MHz)
// 단순히 클럭 토글을 반 주기로 바꿔서 나눔
// ============================================
module clk_divider (
    input wire clk_in,     // 50MHz 입력
    input wire reset_n,    // 리셋 (low일 때 초기화)
    output reg clk_out     // 25MHz 출력
);
    always @(posedge clk_in or negedge reset_n) begin
        if (!reset_n)
            clk_out <= 1'b0;     // 리셋 시 0으로 초기화
        else
            clk_out <= ~clk_out; // 클럭 토글
    end
endmodule

// ============================================
// VGA Controller Module
// VGA 640x480 @ 60Hz 신호 생성
// h_count: 현재 x 픽셀 위치 (0~799)
// v_count: 현재 y 픽셀 위치 (0~524)
// video_on: 화면 출력 가능 영역(640x480) 내에서 1
// ============================================
module vga_controller (
    input wire clk,            // 25MHz 픽셀 클럭
    input wire reset_n,
    output reg h_sync,         // 수평 동기
    output reg v_sync,         // 수직 동기
    output reg video_on,       // 표시 가능 여부
    output reg [9:0] h_count,  // X 좌표
    output reg [9:0] v_count   // Y 좌표
);

    // VGA 타이밍 파라미터 (640x480, 60Hz 기준)
    parameter H_DISPLAY = 640;  // 화면 표시 구간 (픽셀)
    parameter H_FRONT   = 16;   // front porch
    parameter H_SYNC    = 96;   // H_SYNC 펄스 길이
    parameter H_BACK    = 48;   // back porch
    parameter H_TOTAL   = 800;  // 총 주기 (640+16+96+48)

    parameter V_DISPLAY = 480;  // 화면 표시 구간 (라인)
    parameter V_FRONT   = 10;   // front porch
    parameter V_SYNC    = 2;    // V_SYNC 펄스 길이
    parameter V_BACK    = 33;   // back porch
    parameter V_TOTAL   = 525;  // 총 주기 (480+10+2+33)

    // ------------------
    // Horizontal 카운트
    // ------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            h_count <= 10'd0;
        else if (h_count == H_TOTAL - 1) // 한 스캔라인 끝
            h_count <= 10'd0;            // 다시 0으로
        else
            h_count <= h_count + 10'd1;  // 하나 증가
    end
    
    // ------------------
    // Vertical 카운트
    // ------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            v_count <= 10'd0;
        else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1)  // 한 프레임 끝
                v_count <= 10'd0;
            else
                v_count <= v_count + 10'd1;
        end
    end
    
    // ------------------
    // h_sync 신호 생성
    // ------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            h_sync <= 1'b1;  // 기본은 high
        else if (h_count >= (H_DISPLAY + H_FRONT) && 
                 h_count < (H_DISPLAY + H_FRONT + H_SYNC))
            h_sync <= 1'b0;  // 지정된 구간에선 low
        else
            h_sync <= 1'b1;
    end
    
    // ------------------
    // v_sync 신호 생성
    // ------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            v_sync <= 1'b1;  // 기본은 high
        else if (v_count >= (V_DISPLAY + V_FRONT) && 
                 v_count < (V_DISPLAY + V_FRONT + V_SYNC))
            v_sync <= 1'b0;  // 지정된 구간에선 low
        else
            v_sync <= 1'b1;
    end
    
    // ------------------
    // video_on 신호 생성
    // (표시 영역(0~639, 0~479) 내에서만 1)
    // ------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            video_on <= 1'b0;
        else if (h_count < H_DISPLAY && v_count < V_DISPLAY)
            video_on <= 1'b1;
        else
            video_on <= 1'b0;
    end
endmodule

// ============================================
// 패턴 생성기
// h_count,v_count 값에 따라 빨강/초록/파랑 패널 채움
// SW 스위치를 이용해서 다양한 테스트 패턴을 표시 가능
// ============================================
module pattern_generator (
    input wire clk,
    input wire reset_n,
    input wire [9:0] h_count,   // 현재 X 좌표
    input wire [9:0] v_count,   // 현재 Y 좌표
    input wire video_on,        // 화면 표시 가능 여부
    input wire [17:0] sw,       // 스위치 입력
    output reg [7:0] red,
    output reg [7:0] green,
    output reg [7:0] blue
);

    wire [2:0] pattern_sel;
    assign pattern_sel = sw[2:0];  // 하위 3비트로 패턴 종류 선택

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            red   <= 8'd0;
            green <= 8'd0;
            blue  <= 8'd0;
        end
        else if (video_on) begin
            case (pattern_sel)
                3'b000: begin  // 컬러 바 패턴
                    if (h_count < 80)       begin red<=255; green<=255; blue<=255; end // White
                    else if (h_count < 160) begin red<=255; green<=255; blue<=0;   end // Yellow
                    else if (h_count < 240) begin red<=0;   green<=255; blue<=255; end // Cyan
                    else if (h_count < 320) begin red<=0;   green<=255; blue<=0;   end // Green
                    else if (h_count < 400) begin red<=255; green<=0;   blue<=255; end // Magenta
                    else if (h_count < 480) begin red<=255; green<=0;   blue<=0;   end // Red
                    else if (h_count < 560) begin red<=0;   green<=0;   blue<=255; end // Blue
                    else                    begin red<=0;   green<=0;   blue<=0;   end // Black
                end
                
                3'b001: begin  // X 방향 그라데이션
                    red   <= h_count[9:2]; // 상위 비트 → 큰 변화
                    green <= h_count[8:1];
                    blue  <= h_count[7:0]; // 하위 비트 → 미세 변화
                end
                
                3'b010: begin  // Y 방향 그라데이션
                    red   <= v_count[8:1];
                    green <= v_count[9:2];
                    blue  <= v_count[7:0];
                end
                
                3'b011: begin  // 체커보드 패턴
                    if (h_count[5] ^ v_count[5]) begin
                        red<=255; green<=255; blue<=255; // 하얀 블록
                    end else begin
                        red<=0; green<=0; blue<=0;       // 검은 블록
                    end
                end
                
                3'b100: begin  // RGB 스위치 직접 제어
                    red   <= {8{sw[17]}}; // SW[17] = 전체 빨강 on/off
                    green <= {8{sw[16]}};
                    blue  <= {8{sw[15]}};
                end
                
                3'b101: begin  // 십자 패턴
                    if ((h_count >= 310 && h_count <= 330) || 
                        (v_count >= 230 && v_count <= 250)) begin
                        red<=255; green<=0; blue<=0;     // 빨간 십자
                    end else begin
                        red<=0; green<=0; blue<=255;     // 파란 배경
                    end
                end
                
                3'b110: begin  // 테두리 패턴
                    if (h_count < 10 || h_count >= 630 || 
                        v_count < 10 || v_count >= 470) begin
                        red<=255; green<=255; blue<=0;   // 노란색 테두리
                    end else begin
                        red<=0; green<=64; blue<=128;    // 진한 청록색 내부
                    end
                end
                
                default: begin  // 기본 단색 (파란색 느낌)
                    red<=64; green<=128; blue<=255;
                end
            endcase
        end
        else begin
            // 표시 구간 아닐 때는 화면 off
            red<=0; green<=0; blue<=0;
        end
    end
endmodule

// ============================================
// Testbench
// VGA_TOP 모듈을 시뮬레이션으로 실행
// 클럭 발생기 + reset 제어 + 스위치 변화
// 실제 동작 순서를 검증하기 위한 코드
// ============================================
module vga_top_tb;
    reg CLOCK_50;
    reg [3:0] KEY;
    reg [17:0] SW;
    
    wire VGA_CLK;
    wire VGA_HS;
    wire VGA_VS;
    wire VGA_BLANK_N;
    wire VGA_SYNC_N;
    wire [7:0] VGA_R;
    wire [7:0] VGA_G;
    wire [7:0] VGA_B;
    
    // DUT (Device Under Test) 인스턴스화
    vga_top uut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .VGA_CLK(VGA_CLK),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B)
    );
    
    // 50MHz 클럭 생성기
    initial begin
        CLOCK_50 = 0;
        forever #10 CLOCK_50 = ~CLOCK_50;  // 20ns 주기 = 50MHz
    end
    
    // 입력 시나리오
    initial begin
        KEY = 4'b1111;  // 버튼 전체 release
        SW = 18'b0;     // 초기 스위치값
        
        // reset 수행
        #100 KEY[0] = 1'b0;  // reset 누름
        #100 KEY[0] = 1'b1;  // reset 해제
        
        // 패턴 전환 테스트
        #1000000 SW[2:0] = 3'b000; // 컬러바
        #1000000 SW[2:0] = 3'b001; // X 그라데이션
        #1000000 SW[2:0] = 3'b010; // Y 그라데이션
        #1000000 SW[2:0] = 3'b011; // 체커보드
        
        // RGB 직접 테스트
        #1000000 SW[2:0] = 3'b100; SW[17:15] = 3'b001;  // Blue only
        #1000000 SW[17:15] = 3'b010;                   // Green only
        #1000000 SW[17:15] = 3'b100;                   // Red only
        #1000000 SW[17:15] = 3'b111;                   // White
        
        #1000000 $finish;
    end
    
    // VGA sync 정보 모니터링
    initial begin
        $monitor("Time=%0t, H_SYNC=%b, V_SYNC=%b, BLANK=%b", 
                 $time, VGA_HS, VGA_VS, VGA_BLANK_N);
    end
endmodule
