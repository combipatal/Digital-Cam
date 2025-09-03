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
