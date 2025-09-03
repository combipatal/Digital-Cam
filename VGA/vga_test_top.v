module vga_test_top (
    input  wire       CLOCK_50,      // DE2-115 표준 50MHz 클럭 포트명
    input  wire       KEY0,          // DE2-115 KEY[0] 포트
    input  wire [1:0] SW,            // DE2-115 SW[1:0] 포트
    
    // VGA 출력 포트 (DE2-115 VGA 포트)
    output wire [7:0] VGA_R,         // DE2-115 표준 VGA 포트명
    output wire [7:0] VGA_G,         
    output wire [7:0] VGA_B,         
    output wire       VGA_CLK,       
    output wire       VGA_BLANK_N,   
    output wire       VGA_SYNC_N,    
    output wire       VGA_HS,        
    output wire       VGA_VS         
);

// 내부 신호
wire        clk_25M;        // 25MHz VGA 클럭
wire        locked;         // PLL 락 신호
wire [11:0] pixel_data;     // VGA 모듈로 전달할 픽셀 데이터
wire [9:0]  pixel_x;        // 현재 픽셀 X 좌표 (0-639)
wire [9:0]  pixel_y;        // 현재 픽셀 Y 좌표 (0-479)
wire        display_active_signal; // display_active 신호
wire [3:0]  vga_r, vga_g, vga_b;   // 4비트 RGB 신호
wire        reset_n;        // 내부 리셋 신호

// 리셋 신호 처리 (KEY는 눌렀을 때 0, 놓았을 때 1)
assign reset_n = KEY0;

// PLL 인스턴스화 (실제 생성된 PLL 모듈명 확인 필요)
// Quartus에서 생성한 PLL의 실제 모듈명을 사용해야 합니다
PLL_clk u_pll (
    .inclk0  (CLOCK_50),
    .c0      (clk_25M),
    .locked  (locked)
);

// VGA 컨트롤러 인스턴스화
VGA vga_ctrl (
    .i_clk       (clk_25M),
    .i_rstn      (reset_n & locked),  // PLL 락과 리셋 조합
    .i_pixel_data(pixel_data),
    .o_VGA_R     (vga_r),
    .o_VGA_G     (vga_g),
    .o_VGA_B     (vga_b),
    .o_VGA_HS    (VGA_HS),
    .o_VGA_VS    (VGA_VS),
    .o_pixel_x   (pixel_x),
    .o_pixel_y   (pixel_y),
    .o_display_active(display_active_signal)
);

// DE2-115 VGA 신호 변환 (4비트 → 8비트)
assign VGA_R = {vga_r, vga_r};
assign VGA_G = {vga_g, vga_g};
assign VGA_B = {vga_b, vga_b};

// VGA 제어 신호
assign VGA_CLK     = 1'b0;                    // 25MHz 클럭 출력
assign VGA_BLANK_N = display_active_signal;      // Active 구간에만 High
assign VGA_SYNC_N  = 1'b1;                      // Composite sync 비활성화

// 테스트 패턴 생성
reg [11:0] pattern_data;
always @(*) begin
    case(SW)
        2'b00: begin  // 컬러 바
            if (pixel_x < 160)       pattern_data = 12'hF00;      // 빨간색
            else if (pixel_x < 320)  pattern_data = 12'h0F0;      // 초록색
            else if (pixel_x < 480)  pattern_data = 12'h00F;      // 파란색
            else                     pattern_data = 12'hFFF;      // 흰색
        end
        
        2'b01: begin  // 체커보드 패턴
            pattern_data = ((pixel_x[5] ^ pixel_y[5]) ? 12'hFFF : 12'h000);
        end
        
        2'b10: begin  // 그라데이션
            pattern_data = {pixel_x[8:5], pixel_y[8:5], 4'hF};
        end
        
        2'b11: begin  // 움직이는 사각형
            if ((pixel_x >= square_x && pixel_x < square_x + 64) &&
                (pixel_y >= square_y && pixel_y < square_y + 64))
                pattern_data = 12'hF00;  // 빨간 사각형
            else
                pattern_data = 12'h111;  // 어두운 회색 배경
        end
        
        default: pattern_data = 12'h000;
    endcase
end

// 움직이는 사각형을 위한 위치 카운터
reg [9:0] square_x;
reg [9:0] square_y;
reg [19:0] move_counter;  // 카운터 크기 줄임

always @(posedge clk_25M or negedge reset_n) begin
    if (!reset_n) begin
        square_x <= 10'd0;
        square_y <= 10'd0;
        move_counter <= 20'd0;
    end else if (locked) begin
        move_counter <= move_counter + 1'b1;
        
        // 약 25fps로 이동 (25MHz / 1M ≈ 25Hz)
        if (move_counter == 20'hFFFFF) begin
            move_counter <= 20'd0;
            
            if (square_x >= 576)  // 640 - 64(사각형 크기)
                square_x <= 10'd0;
            else
                square_x <= square_x + 1'b1;
                
            if (square_y >= 416)  // 480 - 64(사각형 크기)
                square_y <= 10'd0;
            else if (square_x >= 576)
                square_y <= square_y + 1'b1;
        end
    end
end

// 픽셀 데이터 출력
assign pixel_data = pattern_data;

endmodule