// OV7670 캡처 모듈 - 2×2 평균 데시메이션 (RGB565 -> RGB565)
// - OV7670에서 들어오는 RGB565 바이트를 조립
// - 센서 도메인에서 2x2 박스 필터(평균) 수행 (640x480 -> 320x240)
// - 데시메이션된 픽셀을 선형 BRAM에 직접 기록 (주소 자동 증가)
// 기존 설계와 I/O 호환성 유지
module ov7670_capture #(
    parameter integer SRC_H           = 640,
    parameter integer SRC_V           = 480,
    parameter integer DST_H           = 320,
    parameter integer DST_V           = 240,
    parameter         HI_BYTE_FIRST   = 1,  // 1: [15:8] 먼저, 그 다음 [7:0]
    parameter         BGR_ORDER       = 0   // 0: RGB565, 1: BGR565 출력 스왑
)(
    input  wire        pclk,    // 카메라의 픽셀 클럭
    input  wire        vsync,   // 액티브 하이 프레임 동기 (상승 엣지에서 리셋)
    input  wire        href,    // 액티브 하이 라인 유효 신호
    input  wire [7:0]  d,       // 픽셀 버스
    output wire [16:0] addr,    // 선형 쓰기 주소 (0..(DST_H*DST_V-1))
    output wire [15:0] dout,    // RGB565 쓰기 데이터
    output reg         we       // 쓰기 스트로브 (각 출력 픽셀당 1 pclk)
);

    // -------- 동기 신호 엣지 검출 --------
    reg vsync_d, href_d;
    always @(posedge pclk) begin
        vsync_d <= vsync;
        href_d  <= href;
    end
    wire vsync_rise = (vsync && !vsync_d);
    wire href_rise  = (href  && !href_d);
    wire href_fall  = (!href &&  href_d);

    // -------- 바이트 조립 (RGB565) --------
    reg        byte_phase;        // 0: 첫 번째 바이트, 1: 두 번째 바이트
    reg [7:0]  first_byte;
    reg [15:0] pix16;
    reg        pix_valid;

    // -------- 픽셀 좌표 추적 (소스) --------
    reg [9:0]  src_x;             // 현재 소스 라인 내 0..639
    reg        line_parity;       // 0: 2x2의 짝수 라인, 1: 2x2의 홀수 라인
    reg [8:0]  decim_x;           // 0..319 데시메이션된 x 인덱스

    // -------- 색상별 수평 2-픽셀 합 (현재 및 이전 라인) --------
    // 패킹 = {R_sum2[5:0], G_sum2[6:0], B_sum2[5:0]} = 19비트
    reg [18:0] hpair_sum_prev [0:DST_H-1];

    // 작업용 레지스터
    reg [4:0] r5, r5_p0, b5, b5_p0, r_avg5, b_avg5;
    reg [5:0] g6, g6_p0, g_avg6;
    reg [5:0] r_sum2, b_sum2, r_prev2, b_prev2;   // 0..62
    reg [6:0] g_sum2, g_prev2;                    // 0..126
    reg [6:0] r_sum4, b_sum4;                     // 0..124
    reg [7:0] g_sum4;                             // 0..252
    reg [18:0] prev_pack;
    reg [15:0] out_pix;

    // -------- 주소 생성기 (선형, 자동 증가) --------
    reg [16:0] wr_addr;
    assign addr = wr_addr;
    assign dout = out_pix;

    // -------- 리셋/프레임 시작 --------
    always @(posedge pclk) begin
        if (vsync_rise) begin
            // 프레임 상태 리셋
            byte_phase  <= 1'b0;
            pix_valid   <= 1'b0;
            src_x       <= 10'd0;
            line_parity <= 1'b0;
            decim_x     <= 9'd0;
            we          <= 1'b0;
            wr_addr     <= 17'd0;
        end else begin
            we <= 1'b0; // 기본값

            // HREF 게이팅
            if (href_rise) begin
                byte_phase  <= 1'b0;
                pix_valid   <= 1'b0;
                src_x       <= 10'd0;
                decim_x     <= 9'd0;
            end

            // 바이트를 RGB565 픽셀로 조립
            if (href) begin
                if (!byte_phase) begin
                    first_byte <= d;
                    byte_phase <= 1'b1;
                    pix_valid  <= 1'b0;
                end else begin
                    // 두 번째 바이트 -> 이번 사이클에 픽셀 완성
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

            // 각 소스 픽셀이 완성될 때마다 src_x를 증가시키고 2x2 누적 수행
            if (pix_valid) begin
                // RGB565를 컴포넌트로 언팩
                // pix16[15:11]=R5, [10:5]=G6, [4:0]=B5 (RGB 순서)
                r5 = pix16[15:11];
                g6 = pix16[10:5];
                b5 = pix16[4:0];

                // 수평 쌍 로직: 2x 블록당 두 픽셀 결합
                if (src_x[0] == 1'b0) begin
                    // 짝수 열: 현재 값을 P0로 기억
                    r5_p0 <= r5;
                    g6_p0 <= g6;
                    b5_p0 <= b5;
                end else begin
                    // 홀수 열: 현재 값과 P0를 누적 => 2-픽셀 합
                    r_sum2 = r5_p0 + r5;  // 6-bit
                    g_sum2 = g6_p0 + g6;  // 7-bit
                    b_sum2 = b5_p0 + b5;  // 6-bit

                    // 라인 패리티에 따라 저장 또는 출력
                    if (line_parity == 1'b0) begin
                        // 짝수 소스 라인: 수평 합 저장, 출력 없음
                        hpair_sum_prev[decim_x] <= {r_sum2, g_sum2, b_sum2};
                    end else begin
                        // 홀수 소스 라인: 이전 합을 가져와서 평균 픽셀 생성
                        prev_pack = hpair_sum_prev[decim_x];
                        r_prev2   = prev_pack[18:13];
                        g_prev2   = prev_pack[12:6];
                        b_prev2   = prev_pack[5:0];

                        r_sum4 = r_prev2 + r_sum2; // 7b
                        g_sum4 = g_prev2 + g_sum2; // 8b
                        b_sum4 = b_prev2 + b_sum2; // 7b

                        // 4로 나누기 (>>2)로 평균 계산, RGB565 너비 유지
                        r_avg5 = r_sum4[6:2];
                        g_avg6 = g_sum4[7:2];
                        b_avg5 = b_sum4[6:2];

                        // 재패킹 (선택적으로 RB 스왑)
                        if (!BGR_ORDER)
                            out_pix <= {r_avg5, g_avg6, b_avg5};
                        else
                            out_pix <= {b_avg5, g_avg6, r_avg5};

                        // 평균된 픽셀 하나 출력
                        we      <= 1'b1;
                        wr_addr <= wr_addr + 17'd1;
                    end

                    // 각 홀수 열마다 2-픽셀 열 인덱스 증가
                    if (decim_x != DST_H-1)
                        decim_x <= decim_x + 9'd1;
                end

                // 각 완성된 픽셀마다 소스 x 증가
                if (src_x != SRC_H-1)
                    src_x <= src_x + 10'd1;
            end

            // 라인 끝에서 패리티 토글
            if (href_fall) begin
                line_parity <= ~line_parity;
            end
        end
    end
endmodule
