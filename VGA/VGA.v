module  VGA (
   // Clock and Reset
   input  wire        i_clk,       // 클럭 입력 (25MHz 필요)
   input  wire        i_rstn,      // 리셋 입력 (active low)
   
   // Pixel Data Input
   input  wire [11:0] i_pixel_data, // 픽셀 데이터 입력 (12비트 RGB444)
   
   // VGA Outputs
   output wire [3:0]  o_VGA_R,     // VGA 빨간색 출력
   output wire [3:0]  o_VGA_G,     // VGA 초록색 출력
   output wire [3:0]  o_VGA_B,     // VGA 파란색 출력
   output wire        o_VGA_HS,    // 수평 동기화 신호
   output wire        o_VGA_VS,    // 수직 동기화 신호
   
   // 픽셀 위치 출력
   output wire [9:0]  o_pixel_x,   // 현재 픽셀 X 좌표 (0-639)
   output wire [9:0]  o_pixel_y,    // 현재 픽셀 Y 좌표 (0-479)
	output wire        o_display_active
);

// VGA 타이밍 파라미터 수정 (640x480 @ 60Hz)
localparam H_DISPLAY = 640;  // 수평 디스플레이 영역
localparam H_FRONT   = 16;   // 수평 Front porch
localparam H_SYNC    = 96;   // 수평 동기화 펄스 폭
localparam H_BACK    = 48;   // 수평 Back porch
localparam H_TOTAL   = 800;  // 전체 수평 픽셀 수

localparam V_DISPLAY = 480;  // 수직 디스플레이 영역
localparam V_FRONT   = 11;   // 수직 Front porch
localparam V_SYNC    = 2;    // 수직 동기화 펄스 폭
localparam V_BACK    = 31;   // 수직 Back porch
localparam V_TOTAL   = 524;  // 전체 수직 라인 수

// 내부 신호 및 레지스터 정의
reg [9:0] h_count;  // 수평 카운터 (640 해상도는 10비트 필요)
reg [9:0] v_count;  // 수직 카운터 (480 해상도는 10비트 필요)
reg [3:0] r_VGA_R;  // 빨간색 레지스터
reg [3:0] r_VGA_G;  // 초록색 레지스터
reg [3:0] r_VGA_B;  // 파란색 레지스터

// 수평/수직 동기화 신호 생성
wire h_active = (h_count < H_DISPLAY);                    // 수평 활성화 영역
wire v_active = (v_count < V_DISPLAY);                    // 수직 활성화 영역
wire display_active = h_active && v_active;               // 디스플레이 활성화 영역
assign o_display_active = h_active && v_active;

assign o_VGA_HS = ~((h_count >= (H_DISPLAY + H_FRONT)) && 
                    (h_count < (H_DISPLAY + H_FRONT + H_SYNC)));
assign o_VGA_VS = ~((v_count >= (V_DISPLAY + V_FRONT)) && 
                    (v_count < (V_DISPLAY + V_FRONT + V_SYNC)));

// 수평 카운터
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn)
        h_count <= 10'd0;
    else if (h_count == H_TOTAL-1)
        h_count <= 10'd0;
    else
        h_count <= h_count + 1'b1;
end

// 수직 카운터
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn)
        v_count <= 10'd0;
    else if (h_count == H_TOTAL-1) begin
        if (v_count == V_TOTAL-1)
            v_count <= 10'd0;
        else
            v_count <= v_count + 1'b1;
    end
end

// 픽셀 데이터 처리
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        r_VGA_R <= 4'b0;
        r_VGA_G <= 4'b0;
        r_VGA_B <= 4'b0;
    end else begin
        if (display_active) begin
            r_VGA_R <= i_pixel_data[11:8];  // 상위 4비트 (빨간색)
            r_VGA_G <= i_pixel_data[7:4];   // 중간 4비트 (초록색)
            r_VGA_B <= i_pixel_data[3:0];   // 하위 4비트 (파란색)
        end else begin
            r_VGA_R <= 4'b0;  // 비활성 영역은 검은색
            r_VGA_G <= 4'b0;
            r_VGA_B <= 4'b0;
        end
    end
end

// 출력 할당
assign o_VGA_R = r_VGA_R;
assign o_VGA_G = r_VGA_G;
assign o_VGA_B = r_VGA_B;   

// 픽셀 위치 출력
assign o_pixel_x = (display_active) ? h_count : 10'd0;
assign o_pixel_y = (display_active) ? v_count : 10'd0;

endmodule