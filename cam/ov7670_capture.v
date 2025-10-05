// OV7670 캡처 모듈 - 2x2 박스 필터(평균) 디시메이션 (RGB565 -> RGB565)
module ov7670_capture #(
    parameter integer SRC_H           = 640,
    parameter integer SRC_V           = 480,
    parameter integer DST_H           = 320,
    parameter integer DST_V           = 240,
    parameter         HI_BYTE_FIRST   = 1,  // 1: [15:8] 먼저, 그 다음 [7:0]
    parameter         BGR_ORDER       = 0,  // 0: RGB565, 1: BGR565 출력 스왑
    // 라인 시작 후 무시할 입력 픽셀 수 (RGB565 단위)
    parameter integer LINE_SKIP_PIXELS = 3
)(
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,
    output wire [16:0] addr,
    output wire [15:0] dout,
    output reg         we
);

    // 엣지 검출
    reg vsync_d, href_d;
    always @(posedge pclk) begin
        vsync_d <= vsync;
        href_d  <= href;
    end
    wire vsync_rise = (vsync && !vsync_d);
    wire href_rise  = (href  && !href_d);
    wire href_fall  = (!href &&  href_d);

    // 바이트 조립 (RGB565)
    reg       byte_phase;  // 0: 첫 바이트, 1: 둘째 바이트
    reg [7:0] first_byte;
    reg [15:0] pix16;
    reg        pix_valid;

    // 소스 좌표 및 라인 상태
    reg [9:0]  src_x;      // 0..SRC_H-1
    reg [8:0]  src_y;      // 0..SRC_V-1
    reg        line_parity;// 0: 짝수 라인, 1: 홀수 라인
    reg [8:0]  decim_x;    // 0..DST_H-1
    reg [7:0]  decim_y;    // 0..DST_V-1

    // 라인 시작 스킵: RAW 픽셀은 버리지 않고, 초기 decimated 출력만 마스킹
    // 출력 마스킹 개수 = ceil(LINE_SKIP_PIXELS/2)
    localparam integer OUT_SKIP = (LINE_SKIP_PIXELS + 1) >> 1;
    localparam [16:0] DST_H_17 = DST_H;
    reg [9:0]  out_skip_cnt;  // 남은 출력 마스킹(디시메이션 결과) 개수
    reg [9:0]  wcount;        // 이번 라인에서 소비한 출력 주소 수(0..DST_H)
    reg        have_p0;       // 수평 페어의 첫 픽셀 보유 여부

    // 이전 라인의 수평 2-픽셀 합 저장 (R6+R6, G7+G7, B6+B6 -> 총 19비트)
    reg [18:0] hpair_sum_prev [0:DST_H-1];

    // 작업 레지스터들
    reg [4:0] r5, r5_p0, b5, b5_p0, r_avg5, b_avg5;
    reg [5:0] g6, g6_p0, g_avg6;
    reg [5:0] r_sum2, b_sum2, r_prev2, b_prev2;   // 0..62
    reg [6:0] g_sum2, g_prev2;                    // 0..126
    reg [6:0] r_sum4, b_sum4;                     // 0..124
    reg [7:0] g_sum4;                             // 0..252
    reg [18:0] prev_pack;
    reg [15:0] out_pix;

    // 주소 생성기
    reg [16:0] wr_addr;
    assign addr = wr_addr;
    assign dout = out_pix;

    // 메인 시퀀스
    always @(posedge pclk) begin
        if (vsync_rise) begin
            // 프레임 시작 리셋
            byte_phase    <= (HI_BYTE_FIRST) ? 1'b0 : 1'b1;
            pix_valid     <= 1'b0;
            src_x         <= 10'd0;
            src_y         <= 9'd0;
            line_parity   <= 1'b0;
            decim_x       <= 9'd0;
            decim_y       <= 8'd0;
            out_skip_cnt  <= 10'd0;
            wcount        <= 10'd0;
            have_p0       <= 1'b0;
            we            <= 1'b0;
            wr_addr       <= 17'd0;
        end else begin
            we <= 1'b0; // 기본값

            // 라인 시작 처리
            if (href_rise) begin
                byte_phase    <= (HI_BYTE_FIRST) ? 1'b0 : 1'b1;
                pix_valid     <= 1'b0;
                src_x         <= 10'd0;
                decim_x       <= 9'd0;
                out_skip_cnt  <= OUT_SKIP[9:0];
                wcount        <= 10'd0;
                have_p0       <= 1'b0;
                if (src_y < SRC_V-1)
                    src_y <= src_y + 9'd1;
            end

            // RGB565 픽셀 조립
            if (href) begin
                if (!byte_phase) begin
                    first_byte <= d;
                    byte_phase <= 1'b1;
                    pix_valid  <= 1'b0;
                end else begin
                    byte_phase <= 1'b0;
                    pix_valid  <= 1'b1;
                    if (HI_BYTE_FIRST)
                        pix16 <= {first_byte, d};
                    else
                        pix16 <= {d, first_byte};
                end
            end else begin
                byte_phase <= 1'b0;
                pix_valid  <= 1'b0;
            end

            // 디시메이션 + 평균 처리
            if (pix_valid && (src_y < SRC_V) && (src_x < SRC_H)) begin
                // RGB565 컴포넌트 추출 (RAW는 항상 모두 처리)
                r5 = pix16[15:11];
                g6 = pix16[10:5];
                b5 = pix16[4:0];

                if (!have_p0) begin
                    // 첫 픽셀(P0)
                    r5_p0  <= r5;
                    g6_p0  <= g6;
                    b5_p0  <= b5;
                    have_p0 <= 1'b1;
                end else begin
                    // 둘째 픽셀(P1) -> 수평 합
                    have_p0 <= 1'b0;
                    r_sum2 = r5_p0 + r5;  // 6-bit
                    g_sum2 = g6_p0 + g6;  // 7-bit
                    b_sum2 = b5_p0 + b5;  // 6-bit

                    if (line_parity == 1'b0) begin
                        // 짝수 라인: 수평 합 저장
                        hpair_sum_prev[decim_x] <= {r_sum2, g_sum2, b_sum2};
                    end else begin
                        // 홀수 라인: 이전 합과 더해 2x2 평균 -> RGB565
                        prev_pack = hpair_sum_prev[decim_x];
                        r_prev2   = prev_pack[18:13];
                        g_prev2   = prev_pack[12:6];
                        b_prev2   = prev_pack[5:0];

                        r_sum4 = r_prev2 + r_sum2; // 7b
                        g_sum4 = g_prev2 + g_sum2; // 8b
                        b_sum4 = b_prev2 + b_sum2; // 7b

                        r_avg5 = r_sum4[6:2];
                        g_avg6 = g_sum4[7:2];
                        b_avg5 = b_sum4[6:2];

                        if (!BGR_ORDER)
                            out_pix <= {r_avg5, g_avg6, b_avg5};
                        else
                            out_pix <= {b_avg5, g_avg6, r_avg5};

                        // 초기 OUT_SKIP개 출력은 마스킹: 주소는 전진, we는 내림
                        if (decim_y < DST_V) begin
                            if (out_skip_cnt != 10'd0) begin
                                // 초기 몇 개 출력은 주소 소비 없이 스킵 -> 좌측으로 시프트
                                out_skip_cnt <= out_skip_cnt - 10'd1;
                                we           <= 1'b0;
                                // wr_addr, wcount 변화 없음
                            end else begin
                                we      <= 1'b1;
                                wr_addr <= wr_addr + 17'd1;
                                wcount  <= wcount + 10'd1;
                            end
                        end
                    end

                    // 수평 페어 하나 완료 -> x 인덱스 증가
                    if (decim_x != DST_H-1)
                        decim_x <= decim_x + 9'd1;
                end

                // 소스 x 증가
                if (src_x != SRC_H-1)
                    src_x <= src_x + 10'd1;
            end

            // 라인 종료 처리
            if (href_fall) begin
                line_parity <= ~line_parity;
                // 홀수 라인 종료 시 y 인덱스 증가 (2x2 블록 1행)
                if (line_parity == 1'b1 && decim_y < DST_V-1)
                    decim_y <= decim_y + 8'd1;
                // 홀수 라인 종료 시, 스킵으로 인해 적게 쓴 만큼 주소를 한 번에 보정
                if (line_parity == 1'b1) begin
                    wr_addr <= wr_addr + (DST_H_17 - {7'd0, wcount});
                    wcount  <= 10'd0;
                end
            end
        end
    end
endmodule
