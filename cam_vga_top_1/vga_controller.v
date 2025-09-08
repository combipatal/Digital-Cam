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