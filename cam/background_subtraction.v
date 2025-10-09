
module background_subtraction (
    input wire clk,
    input wire active_area,
    input wire [15:0] live_pixel_in, // 실시간 영상 픽셀 (RGB565)
    input wire [15:0] bg_pixel_in,   // 배경 픽셀 (RGB565)
    output reg [15:0] pixel_out      // 결과 픽셀 (RGB565)
);

    // 차이 계산을 위한 임계값 (조정 가능)
    localparam integer THRESHOLD = 30;

    // RGB565 포맷에서 각 색상 채널 추출
    wire [4:0] r_live, r_bg;
    wire [5:0] g_live, g_bg;
    wire [4:0] b_live, b_bg;

    assign r_live = live_pixel_in[15:11];
    assign g_live = live_pixel_in[10:5];
    assign b_live = live_pixel_in[4:0];

    assign r_bg = bg_pixel_in[15:11];
    assign g_bg = bg_pixel_in[10:5];
    assign b_bg = bg_pixel_in[4:0];

    // 각 채널의 차이 절대값 계산
    wire [4:0] r_diff;
    wire [5:0] g_diff;
    wire [4:0] b_diff;

    assign r_diff = (r_live > r_bg) ? (r_live - r_bg) : (r_bg - r_live);
    assign g_diff = (g_live > g_bg) ? (g_live - g_bg) : (g_bg - g_live);
    assign b_diff = (b_live > b_bg) ? (b_live - b_bg) : (b_bg - b_live);

    // 모든 채널의 차이 합산
    wire [15:0] total_diff;
    assign total_diff = r_diff + g_diff + b_diff;

    always @(posedge clk) begin
        if (!active_area) begin
            pixel_out <= 16'h0000; // 비활성 영역은 검은색
        end else begin
            if (total_diff > THRESHOLD) begin
                pixel_out <= live_pixel_in; // 차이가 크면 실시간 픽셀 (전경)
            end else begin
                pixel_out <= 16'h0000; // 차이가 작으면 검은색 (배경)
            end
        end
    end

endmodule
