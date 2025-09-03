module vga_test_top (
    input  wire       i_clk_50M,    // 50MHz 보드 클럭 입력
    input  wire       i_rst_n,      // 리셋 입력 (active low, KEY[0])
    input  wire [1:0] i_pattern,    // 패턴 선택 스위치 (SW[1:0])
    
    // VGA 출력 포트 (DE2-115 VGA 포트)
    output wire [7:0] o_VGA_R,      // VGA Red 채널 (8비트)
    output wire [7:0] o_VGA_G,      // VGA Green 채널 (8비트)
    output wire [7:0] o_VGA_B,      // VGA Blue 채널 (8비트)
    output wire       o_VGA_CLK,    // VGA 픽셀 클럭
    output wire       o_VGA_BLANK_N,// VGA 블랭킹 신호
    output wire       o_VGA_SYNC_N, // VGA 동기화 신호
    output wire       o_VGA_HS,     // 수평 동기화
    output wire       o_VGA_VS      // 수직 동기화
);

// 내부 신호
wire        clk_25M;        // 25MHz VGA 클럭
wire        locked;         // PLL 락 신호
wire [11:0] pixel_data;    // VGA 모듈로 전달할 픽셀 데이터
wire [8:0]  pixel_x;       // 현재 픽셀 X 좌표
wire [8:0]  pixel_y;       // 현재 픽셀 Y 좌표

// DE2-115의 PLL 인스턴스화 (50MHz → 25MHz)
CLK_25Mhz_bb CLK_25Mhz (
    .inclk0  (i_clk_50M),  // 50MHz 입력
    .c0      (clk_25M),    // 25MHz 출력
    .locked  (locked)
);

// VGA 컨트롤러 인스턴스화
VGA vga_ctrl (
    .i_clk       (clk_25M),
    .i_rstn      (i_rst_n & locked),
    .i_pixel_data(pixel_data),
    .o_VGA_R     (vga_r),
    .o_VGA_G     (vga_g),
    .o_VGA_B     (vga_b),
    .o_VGA_HS    (o_VGA_HS),
    .o_VGA_VS    (o_VGA_VS)
);

// DE2-115 VGA 신호 변환
wire [3:0] vga_r, vga_g, vga_b;
assign o_VGA_R = {vga_r, vga_r};    // 4비트를 8비트로 확장
assign o_VGA_G = {vga_g, vga_g};    // 4비트를 8비트로 확장
assign o_VGA_B = {vga_b, vga_b};    // 4비트를 8비트로 확장
assign o_VGA_CLK = clk_25M;         // 픽셀 클럭
assign o_VGA_BLANK_N = 1'b1;        // 항상 활성
assign o_VGA_SYNC_N = 1'b0;         // 동기화 신호 활성

// 테스트 패턴 생성
reg [11:0] pattern_data;
always @(*) begin
    case(i_pattern)
        2'b00: begin  // 컬러 바
            if (pixel_x < 80)        pattern_data = 12'hF00;      // 빨간색
            else if (pixel_x < 160)  pattern_data = 12'h0F0;      // 초록색
            else if (pixel_x < 240)  pattern_data = 12'h00F;      // 파란색
            else                     pattern_data = 12'hFFF;      // 흰색
        end
        
        2'b01: begin  // 체커보드 패턴
            pattern_data = ((pixel_x[4] ^ pixel_y[4]) ? 12'hFFF : 12'h000);
        end
        
        2'b10: begin  // 그라데이션
            pattern_data = {pixel_x[7:4], pixel_y[7:4], 4'hF};
        end
        
        2'b11: begin  // 움직이는 사각형
            if ((pixel_x >= square_x && pixel_x < square_x + 32) &&
                (pixel_y >= square_y && pixel_y < square_y + 32))
                pattern_data = 12'hF00;  // 빨간 사각형
            else
                pattern_data = 12'h111;  // 어두운 회색 배경
        end
    endcase
end

// 움직이는 사각형을 위한 위치 카운터
reg [8:0] square_x = 9'd0;
reg [8:0] square_y = 9'd0;
reg [24:0] move_counter = 25'd0;

always @(posedge clk_25M or negedge i_rst_n) begin
    if (!i_rst_n) begin
        square_x <= 9'd0;
        square_y <= 9'd0;
        move_counter <= 25'd0;
    end else begin
        move_counter <= move_counter + 1'b1;
        
        if (move_counter == 25'd0) begin
            if (square_x >= 288)  // 320 - 32(사각형 크기)
                square_x <= 9'd0;
            else
                square_x <= square_x + 1'b1;
                
            if (square_y >= 208)  // 240 - 32(사각형 크기)
                square_y <= 9'd0;
            else if (square_x >= 288)
                square_y <= square_y + 1'b1;
        end
    end
end

// 픽셀 데이터 출력
assign pixel_data = pattern_data;

endmodule
