// OV7670 캡처 모듈 - 2x2 박스 필터(평균) 디시메이션 (RGB565 -> RGB565)
// 고정 설정:
// - HI_BYTE_FIRST = 1 (상위 바이트 먼저)
// - BGR_ORDER = 0 (RGB565 출력)
// - LINE_SKIP_PIXELS = 0 (라인 스킵 없음)
module ov7670_capture #(
    parameter integer SRC_H = 640,  // 소스 가로 크기
    parameter integer SRC_V = 480,  // 소스 세로 크기
    parameter integer DST_H = 320,  // 목적지 가로 크기
    parameter integer DST_V = 240   // 목적지 세로 크기
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
    reg [9:0]  src_h;      // 0..SRC_H-1  원본 이미지 가로 좌표 (horizontal)
    reg [8:0]  src_v;      // 0..SRC_V-1  원본 이미지 세로 좌표 (vertical)
    reg        line_parity;// 0: 짝수 라인, 1: 홀수 라인    
    reg [8:0]  decim_h;    // 0..DST_H-1  목적지 가로 좌표 (horizontal)
    reg [7:0]  decim_v;    // 0..DST_V-1  목적지 세로 좌표 (vertical)  

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
            byte_phase    <= 1'b0;  // 상위 바이트 먼저 (고정)
            pix_valid     <= 1'b0;
            src_h         <= 10'd0;
            src_v         <= 9'd0;
            line_parity   <= 1'b0;
            decim_h       <= 9'd0;
            decim_v       <= 8'd0;
            have_p0       <= 1'b0;
            we            <= 1'b0;
            wr_addr       <= 17'd0;
        end else begin
            we <= 1'b0; // 기본값

            // 라인 시작 처리
            if (href_rise) begin
                byte_phase    <= 1'b0;  // 상위 바이트 먼저 (고정)
                pix_valid     <= 1'b0;
                src_h         <= 10'd0;
                decim_h       <= 9'd0;
                have_p0       <= 1'b0;
                if (src_v < SRC_V-1)
                    src_v <= src_v + 9'd1;
            end

            // RGB565 픽셀 조립 (상위 바이트 먼저, 고정)
            if (href) begin
                if (!byte_phase) begin
                    first_byte <= d;      // 첫 번째 바이트 (상위 바이트)
                    byte_phase <= 1'b1;
                    pix_valid  <= 1'b0;
                end else begin
                    byte_phase <= 1'b0;
                    pix_valid  <= 1'b1;
                    pix16 <= {first_byte, d};  // {상위바이트, 하위바이트}
                end
            end else begin
                byte_phase <= 1'b0;
                pix_valid  <= 1'b0;
            end

            // 디시메이션 + 평균 처리
            if (pix_valid && (src_v < SRC_V) && (src_h < SRC_H)) begin // 640, 480 영역 내에서만 처리
                // RGB565 추출 (RAW는 항상 모두 처리)
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
                        hpair_sum_prev[decim_h] <= {r_sum2, g_sum2, b_sum2};
                    end else begin
                        // 홀수 라인: 이전 합과 더해 2x2 평균 -> RGB565
                        prev_pack = hpair_sum_prev[decim_h];
                        r_prev2   = prev_pack[18:13];
                        g_prev2   = prev_pack[12:6];
                        b_prev2   = prev_pack[5:0];

                        r_sum4 = r_prev2 + r_sum2; // 7b
                        g_sum4 = g_prev2 + g_sum2; // 8b
                        b_sum4 = b_prev2 + b_sum2; // 7b

                        r_avg5 = r_sum4[6:2];
                        g_avg6 = g_sum4[7:2];
                        b_avg5 = b_sum4[6:2];
                        // blocking로직 사용해야함 
                        // RGB565 출력 (고정)
                        out_pix <= {r_avg5, g_avg6, b_avg5};

                        // 출력 쓰기
                        if (decim_v < DST_V) begin
                            we      <= 1'b1;
                            wr_addr <= wr_addr + 17'd1;
                        end
                    end

                    // 수평 페어 하나 완료 -> 가로 인덱스 증가
                    if (decim_h < DST_H-1)
                        decim_h <= decim_h + 9'd1;
                end

                // 소스 가로 좌표 증가
                if (src_h < SRC_H-1)
                    src_h <= src_h + 10'd1;
            end

            // 라인 종료 처리
            if (href_fall) begin
                line_parity <= ~line_parity;
                // 홀수 라인 종료 시 세로 인덱스 증가 (2x2 블록 1행)
                if (line_parity == 1'b1 && decim_v < DST_V-1)
                    decim_v <= decim_v + 8'd1;
            end
        end
    end
endmodule
