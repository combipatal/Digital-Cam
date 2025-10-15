// 타이밍 여유를 확보하기 위해 내부 파이프라인을 적용한 적응형 배경 제거 모듈.
// 스트리밍 픽셀 주소에 맞춰 읽기-수정-쓰기 갱신을 수행한다.
module adaptive_background #(
    parameter integer ADDR_WIDTH    = 17,
    parameter integer PIXEL_WIDTH   = 16,
    parameter integer SHIFT_LG2     = 3, // 배경 업데이트 비율: 1/8
    parameter integer FG_SHIFT_LG2  = 7 // 전경 하나당 업데이트 비율: 1/128
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     enable,
    input  wire [ADDR_WIDTH-1:0]    addr_in,
    input  wire [PIXEL_WIDTH-1:0]   live_pixel_in,
    input  wire [PIXEL_WIDTH-1:0]   bg_pixel_in,
    input  wire                     active_in,
    input  wire                     load_frame,
    input  wire [8:0]               threshold_in, // 런타임 조정이 가능한 임계값
    output reg  [ADDR_WIDTH-1:0]    bg_wr_addr,
    output reg  [PIXEL_WIDTH-1:0]   bg_wr_data,
    output reg                      bg_wr_en,
    output reg  [PIXEL_WIDTH-1:0]   fg_pixel_out,
    output reg                      foreground_flag
);

    // 파이프라인 단계:
    // s1: 입력 래칭
    // s2: 채널별 차이 연산
    // s3: 델타(보정값) 계산
    // s4: 최종 배경 픽셀 계산

    // 단계별 파이프라인 레지스터
    reg [ADDR_WIDTH-1:0]   addr_s1, addr_s2, addr_s3, addr_s4;
    reg [PIXEL_WIDTH-1:0]  live_s1, live_s2, live_s3, live_s4;
    reg [PIXEL_WIDTH-1:0]  bg_s1, bg_s2, bg_s3;
    reg                    active_s1, active_s2, active_s3, active_s4;
    reg                    load_s1, load_s2, load_s3, load_s4;
    reg [8:0]              threshold_s1, threshold_s2;
    reg signed [8:0]       diff_r_s2, diff_g_s2, diff_b_s2;
    reg                    foreground_s3, foreground_s4;
    reg signed [8:0]       final_delta_r_s3, final_delta_g_s3, final_delta_b_s3;

    // 보조 함수 정의
    function [7:0] expand5; input [4:0] v; expand5 = {v, 3'b000}; endfunction
    function [7:0] expand6; input [5:0] v; expand6 = {v, 2'b00}; endfunction
    function [4:0] compress5; input [8:0] v; compress5 = (v[8] || v > 9'd255) ? (v[8] ? 5'd0 : 5'd31) : v[7:3]; endfunction
    function [5:0] compress6; input [8:0] v; compress6 = (v[8] || v > 9'd255) ? (v[8] ? 6'd0 : 6'd63) : v[7:2]; endfunction

    // 그레이스케일 변환 함수 (Y = 0.299R + 0.587G + 0.114B)
    // 근사식: (77*R + 150*G + 29*B) >> 8
    function [7:0] rgb_to_gray;
        input [PIXEL_WIDTH-1:0] rgb;
        reg [7:0] r, g, b;
        reg [15:0] luma;
        begin
            r = expand5(rgb[15:11]);
            g = expand6(rgb[10:5]);
            b = expand5(rgb[4:0]);
            luma = (r * 77) + (g * 150) + (b * 29);
            rgb_to_gray = luma[15:8];
        end
    endfunction

    // 파이프라인 단계별 조합 논리
    wire signed [8:0] live_r_ext = {1'b0, expand5(live_s1[15:11])};
    wire signed [8:0] live_g_ext = {1'b0, expand6(live_s1[10:5])};
    wire signed [8:0] live_b_ext = {1'b0, expand5(live_s1[4:0])};
    wire signed [8:0] bg_r_ext   = {1'b0, expand5(bg_s1[15:11])};
    wire signed [8:0] bg_g_ext   = {1'b0, expand6(bg_s1[10:5])};
    wire signed [8:0] bg_b_ext   = {1'b0, expand5(bg_s1[4:0])};

    wire signed [8:0] diff_r_s1 = live_r_ext - bg_r_ext;
    wire signed [8:0] diff_g_s1 = live_g_ext - bg_g_ext;
    wire signed [8:0] diff_b_s1 = live_b_ext - bg_b_ext;

    // 그레이스케일 차이 계산
    wire [7:0] live_gray_s2 = rgb_to_gray(live_s2);
    wire [7:0] bg_gray_s2   = rgb_to_gray(bg_s2);
    wire signed [8:0] gray_diff_s2 = $signed({1'b0, live_gray_s2}) - $signed({1'b0, bg_gray_s2});
    wire [8:0] abs_gray_diff_s2 = gray_diff_s2[8] ? (~gray_diff_s2 + 1) : gray_diff_s2;

    wire foreground_s2 = (abs_gray_diff_s2 > threshold_s2);

    wire signed [8:0] delta_r_s2 = diff_r_s2 >>> SHIFT_LG2;
    wire signed [8:0] delta_g_s2 = diff_g_s2 >>> SHIFT_LG2;
    wire signed [8:0] delta_b_s2 = diff_b_s2 >>> SHIFT_LG2;
    wire signed [8:0] fg_delta_r_s2 = diff_r_s2 >>> FG_SHIFT_LG2;
    wire signed [8:0] fg_delta_g_s2 = diff_g_s2 >>> FG_SHIFT_LG2;
    wire signed [8:0] fg_delta_b_s2 = diff_b_s2 >>> FG_SHIFT_LG2;

    // 파이프라인 레지스터 단계
    always @(posedge clk) begin
        if (rst) begin
            // 필요 시 별도의 리셋 로직을 여기에 추가한다
        end else if (enable) begin
            // Stage 1: 입력 신호 래칭
            addr_s1      <= addr_in;
            live_s1      <= live_pixel_in;
            bg_s1        <= bg_pixel_in;
            active_s1    <= active_in;
            load_s1      <= load_frame;
            threshold_s1 <= threshold_in;

            // Stage 2: 차이값 계산
            addr_s2      <= addr_s1;
            live_s2      <= live_s1;
            bg_s2        <= bg_s1;
            active_s2    <= active_s1;
            load_s2      <= load_s1;
            threshold_s2 <= threshold_s1;
            diff_r_s2    <= diff_r_s1;
            diff_g_s2    <= diff_g_s1;
            diff_b_s2    <= diff_b_s1;

            // Stage 3: 델타 보정값 선택
            addr_s3   <= addr_s2;
            live_s3   <= live_s2;
            bg_s3     <= bg_s2;
            active_s3 <= active_s2;
            load_s3   <= load_s2;
            foreground_s3 <= foreground_s2;
            final_delta_r_s3 <= foreground_s2 ? fg_delta_r_s2 : delta_r_s2;
            final_delta_g_s3 <= foreground_s2 ? fg_delta_g_s2 : delta_g_s2;
            final_delta_b_s3 <= foreground_s2 ? fg_delta_b_s2 : delta_b_s2;

            // Stage 4: 출력 및 쓰기 주소 정렬
            addr_s4   <= addr_s3;
            live_s4   <= live_s3;
            active_s4 <= active_s3;
            load_s4   <= load_s3;
            foreground_s4 <= foreground_s3;
        end
    end

    // 출력 측 조합 논리
    always @(*) begin
        // 기본값 할당
        bg_wr_en        = 1'b0;
        bg_wr_addr      = addr_s4;
        bg_wr_data      = live_s4; // 래치 방지를 위해 기본값을 명시
        fg_pixel_out    = foreground_s4 ? live_s4 : 16'h0000;
        foreground_flag = foreground_s4;

        if (active_s4 || load_s4) begin
            bg_wr_en = 1'b1;
            if (load_s4) begin
                bg_wr_data = live_s4; // 수동 프레임 로드 경로
            end else begin
                // 자동 업데이트 경로: 계산된 델타만큼 배경 보정
                bg_wr_data = {
                    compress5($signed({1'b0, expand5(bg_s3[15:11])}) + final_delta_r_s3),
                    compress6($signed({1'b0, expand6(bg_s3[10:5])}) + final_delta_g_s3),
                    compress5($signed({1'b0, expand5(bg_s3[4:0])}) + final_delta_b_s3)
                };
            end
        end
    end

endmodule
