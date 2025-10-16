// =================================================================================
// 적응형 배경 모델링 (adaptive_background)
// =================================================================================
// 이 모듈은 실시간 영상 스트림과 배경 모델을 비교하여 움직이는 전경(foreground)을
// 검출합니다. 검출된 전경/배경 정보에 따라 배경 모델을 점진적으로 업데이트하여
// 조명 변화나 작은 움직임에 적응하는 기능을 수행합니다.
//
// 주요 기능:
// 1. 파이프라인 구조: 총 4클럭의 지연을 가지는 파이프라인으로 구성되어 타이밍 마진을 확보합니다.
// 2. 동적 임계값 적용: 그레이스케일 값의 차이를 기반으로 전경을 판단하며,
//    이때 사용되는 임계값은 외부에서 실시간으로 조절할 수 있습니다.
// 3. 이중 학습률(Dual-Rate Learning):
//    - 배경 영역: 상대적으로 빠르게 배경 모델을 업데이트하여 조명 변화에 대응합니다.
//    - 전경 영역: 매우 느리게 업데이트하여, 움직이다 멈춘 물체를 서서히 배경으로 흡수합니다.
// 4. 배경 강제 업데이트: 'load_frame' 신호를 통해 현재 프레임을 배경으로 즉시 저장할 수 있습니다.
// =================================================================================
module adaptive_background #(
    parameter integer ADDR_WIDTH    = 17,   // 주소 버스 폭
    parameter integer PIXEL_WIDTH   = 16,   // 픽셀 데이터 폭 (RGB565)
    parameter integer SHIFT_LG2     = 3,    // 배경 학습률 (1/2^3 = 1/8)
    parameter integer FG_SHIFT_LG2  = 7     // 전경 학습률 (1/2^7 = 1/128)
) (
    // --- 시스템 신호 ---
    input  wire                     clk,            // 시스템 클럭
    input  wire                     rst,            // 리셋
    input  wire                     enable,         // 모듈 활성화

    // --- 입력 데이터 스트림 ---
    input  wire [ADDR_WIDTH-1:0]    addr_in,        // 현재 처리 중인 픽셀 주소
    input  wire [PIXEL_WIDTH-1:0]   live_pixel_in,  // 실시간 카메라 픽셀 (RGB565)
    input  wire [PIXEL_WIDTH-1:0]   bg_pixel_in,    // 현재 배경 모델의 픽셀 (RGB565)
    input  wire                     active_in,      // 유효 영상 구간 신호
    input  wire                     load_frame,     // 현재 프레임을 배경으로 강제 저장
    input  wire [8:0]               threshold_in,   // 전경/배경 판단 임계값

    // --- 배경 메모리 쓰기 인터페이스 ---
    output reg  [ADDR_WIDTH-1:0]    bg_wr_addr,     // 배경 RAM에 쓸 주소
    output reg  [PIXEL_WIDTH-1:0]   bg_wr_data,     // 배경 RAM에 쓸 데이터
    output reg                      bg_wr_en,       // 배경 RAM 쓰기 활성화

    // --- 출력 ---
    output reg  [PIXEL_WIDTH-1:0]   fg_pixel_out,   // 전경 픽셀 출력 (전경 아니면 0)
    output reg                      foreground_flag // 전경 판단 플래그
);

    // ============================================================================
    // 파이프라인 레지스터 선언 (4-Stage Pipeline)
    // ============================================================================
    // p1: 입력 래칭, 그레이스케일 변환, 전경 판단
    // p2: 델타(보정값) 선택
    // p3: 새로운 배경 픽셀 계산
    // p4: 출력 정렬 및 RAM 쓰기 신호 생성

    // --- p1: 입력 래칭 ---
    reg [ADDR_WIDTH-1:0]   addr_p1;
    reg [PIXEL_WIDTH-1:0]  live_pixel_p1;
    reg [PIXEL_WIDTH-1:0]  bg_pixel_p1;
    reg                    active_p1;
    reg                    load_frame_p1;
    reg [8:0]              threshold_p1;

    // --- p2: 델타 선택 ---
    reg [ADDR_WIDTH-1:0]   addr_p2;
    reg [PIXEL_WIDTH-1:0]  live_pixel_p2;
    reg [PIXEL_WIDTH-1:0]  bg_pixel_p2;
    reg                    active_p2;
    reg                    load_frame_p2;
    reg                    foreground_p2;
    reg signed [8:0]       diff_r_p2, diff_g_p2, diff_b_p2;

    // --- p3: 새 배경 계산 ---
    reg [ADDR_WIDTH-1:0]   addr_p3;
    reg [PIXEL_WIDTH-1:0]  live_pixel_p3;
    reg [PIXEL_WIDTH-1:0]  bg_pixel_p3;
    reg                    active_p3;
    reg                    load_frame_p3;
    reg                    foreground_p3;
    reg signed [8:0]       final_delta_r_p3, final_delta_g_p3, final_delta_b_p3;

    // --- p4: 출력 ---
    reg [ADDR_WIDTH-1:0]   addr_p4;
    reg [PIXEL_WIDTH-1:0]  live_pixel_p4;
    reg                    active_p4;
    reg                    load_frame_p4;
    reg                    foreground_p4;
    reg [PIXEL_WIDTH-1:0]  new_bg_pixel_p4;

    // ============================================================================
    // 조합 논리
    // ============================================================================

    // --- p1 로직: 그레이스케일 변환 및 전경 판단 ---
    wire [7:0] live_r_p1_888 = {live_pixel_p1[15:11], 3'b000};
    wire [7:0] live_g_p1_888 = {live_pixel_p1[10:5],  2'b00};
    wire [7:0] live_b_p1_888 = {live_pixel_p1[4:0],   3'b000};
    wire [7:0] bg_r_p1_888   = {bg_pixel_p1[15:11],   3'b000};
    wire [7:0] bg_g_p1_888   = {bg_pixel_p1[10:5],    2'b00};
    wire [7:0] bg_b_p1_888   = {bg_pixel_p1[4:0],     3'b000};

    wire signed [8:0] diff_r_p1 = {1'b0, live_r_p1_888} - {1'b0, bg_r_p1_888};
    wire signed [8:0] diff_g_p1 = {1'b0, live_g_p1_888} - {1'b0, bg_g_p1_888};
    wire signed [8:0] diff_b_p1 = {1'b0, live_b_p1_888} - {1'b0, bg_b_p1_888};

    wire [16:0] live_gray_sum = (live_r_p1_888 << 6) + (live_r_p1_888 << 3) + (live_r_p1_888 << 2) +
                                (live_g_p1_888 << 7) + (live_g_p1_888 << 4) + (live_g_p1_888 << 2) + (live_g_p1_888 << 1) +
                                (live_b_p1_888 << 4) + (live_b_p1_888 << 3) + (live_b_p1_888 << 1);
    wire [7:0] live_gray_p1 = live_gray_sum[16:8];

    wire [16:0] bg_gray_sum = (bg_r_p1_888 << 6) + (bg_r_p1_888 << 3) + (bg_r_p1_888 << 2) +
                              (bg_g_p1_888 << 7) + (bg_g_p1_888 << 4) + (bg_g_p1_888 << 2) + (bg_g_p1_888 << 1) +
                              (bg_b_p1_888 << 4) + (bg_b_p1_888 << 3) + (bg_b_p1_888 << 1);
    wire [7:0] bg_gray_p1 = bg_gray_sum[16:8];

    wire signed [8:0] gray_diff_p1 = {1'b0, live_gray_p1} - {1'b0, bg_gray_p1};
    wire [8:0] abs_gray_diff_p1 = gray_diff_p1[8] ? -gray_diff_p1 : gray_diff_p1;
    wire foreground_p1 = (abs_gray_diff_p1 > threshold_p1);

    // --- p2 로직: 학습률에 따른 델타(보정값) 계산 ---
    wire signed [8:0] bg_delta_r_p2 = diff_r_p2 >>> SHIFT_LG2;
    wire signed [8:0] bg_delta_g_p2 = diff_g_p2 >>> SHIFT_LG2;
    wire signed [8:0] bg_delta_b_p2 = diff_b_p2 >>> SHIFT_LG2;
    wire signed [8:0] fg_delta_r_p2 = diff_r_p2 >>> FG_SHIFT_LG2;
    wire signed [8:0] fg_delta_g_p2 = diff_g_p2 >>> FG_SHIFT_LG2;
    wire signed [8:0] fg_delta_b_p2 = diff_b_p2 >>> FG_SHIFT_LG2;

    // --- p3 로직: 새로운 배경 픽셀 값 계산 ---
    wire [7:0] bg_r_p3_888 = {bg_pixel_p3[15:11], 3'b000};
    wire [7:0] bg_g_p3_888 = {bg_pixel_p3[10:5],  2'b00};
    wire [7:0] bg_b_p3_888 = {bg_pixel_p3[4:0],   3'b000};

    wire signed [8:0] new_bg_r_ext = {1'b0, bg_r_p3_888} + final_delta_r_p3;
    wire signed [8:0] new_bg_g_ext = {1'b0, bg_g_p3_888} + final_delta_g_p3;
    wire signed [8:0] new_bg_b_ext = {1'b0, bg_b_p3_888} + final_delta_b_p3;

    wire [4:0] new_bg_r_565 = (new_bg_r_ext[8] || new_bg_r_ext > 9'd255) ? (new_bg_r_ext[8] ? 5'd0 : 5'd31) : new_bg_r_ext[7:3];
    wire [5:0] new_bg_g_565 = (new_bg_g_ext[8] || new_bg_g_ext > 9'd255) ? (new_bg_g_ext[8] ? 6'd0 : 6'd63) : new_bg_g_ext[7:2];
    wire [4:0] new_bg_b_565 = (new_bg_b_ext[8] || new_bg_b_ext > 9'd255) ? (new_bg_b_ext[8] ? 5'd0 : 5'd31) : new_bg_b_ext[7:3];

    wire [PIXEL_WIDTH-1:0] new_bg_pixel_p3 = {new_bg_r_565, new_bg_g_565, new_bg_b_565};

    // ============================================================================
    // 파이프라인 레지스터 단계
    // ============================================================================
    always @(posedge clk) begin
        if (rst) begin
            // 리셋 로직 (필요 시 추가)
        end else if (enable) begin
            // --- Stage 1: 입력 래칭 ---
            addr_p1       <= addr_in;
            live_pixel_p1 <= live_pixel_in;
            bg_pixel_p1   <= bg_pixel_in;
            active_p1     <= active_in;
            load_frame_p1 <= load_frame;
            threshold_p1  <= threshold_in;

            // --- Stage 2: 델타 선택 ---
            addr_p2       <= addr_p1;
            live_pixel_p2 <= live_pixel_p1;
            bg_pixel_p2   <= bg_pixel_p1;
            active_p2     <= active_p1;
            load_frame_p2 <= load_frame_p1;
            foreground_p2 <= foreground_p1;
            diff_r_p2     <= diff_r_p1;
            diff_g_p2     <= diff_g_p1;
            diff_b_p2     <= diff_b_p1;

            // --- Stage 3: 새 배경 계산 ---
            addr_p3          <= addr_p2;
            live_pixel_p3    <= live_pixel_p2;
            bg_pixel_p3      <= bg_pixel_p2;
            active_p3        <= active_p2;
            load_frame_p3    <= load_frame_p2;
            foreground_p3    <= foreground_p2;
            final_delta_r_p3 <= foreground_p2 ? fg_delta_r_p2 : bg_delta_r_p2;
            final_delta_g_p3 <= foreground_p2 ? fg_delta_g_p2 : bg_delta_g_p2;
            final_delta_b_p3 <= foreground_p2 ? fg_delta_b_p2 : bg_delta_b_p2;

            // --- Stage 4: 출력 정렬 ---
            addr_p4         <= addr_p3;
            live_pixel_p4   <= live_pixel_p3;
            active_p4       <= active_p3;
            load_frame_p4   <= load_frame_p3;
            foreground_p4   <= foreground_p3;
            new_bg_pixel_p4 <= new_bg_pixel_p3;
        end
    end

    // ============================================================================
    // 출력 로직
    // ============================================================================
    always @(*) begin
        // --- 기본값 할당 ---
        bg_wr_en        = 1'b0;
        bg_wr_addr      = addr_p4;
        bg_wr_data      = live_pixel_p4; // 래치 방지를 위해 기본값 명시
        fg_pixel_out    = foreground_p4 ? live_pixel_p4 : 16'h0000;
        foreground_flag = foreground_p4;

        // --- 배경 업데이트 조건 ---
        if (active_p4 || load_frame_p4) begin
            bg_wr_en = 1'b1;
            if (load_frame_p4) begin
                // 수동 배경 캡처: 현재 라이브 픽셀을 그대로 배경으로 저장
                bg_wr_data = live_pixel_p4;
            end else begin
                // 자동 배경 업데이트: 계산된 새로운 배경 픽셀 값으로 저장
                bg_wr_data = new_bg_pixel_p4;
            end
        end
    end

endmodule
