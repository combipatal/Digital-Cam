// 3x3 Sobel 필터 (8비트 그레이) - 2라인 버퍼 + 경계 복제
// - 진짜 3x3 윈도우를 형성 (y-1, y-2 라인 보관 + 수평 3탭)
// - 좌/상/우/하 경계에서 픽셀을 가장자리로 복제(clamp)하여 첫 픽셀부터 유효 출력
// - 파이프라인 지연: 2클럭 (상위 GAUSS_LAT=4 이후 추가 2클럭)
module sobel_3x3_gray8 (
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,   // {y[16:9], x[8:0]}
    input  wire        vsync,
    input  wire        active_area,
    input  wire [7:0]  threshold,    // threshold for binary edge output
    output reg  [7:0]  pixel_out,
    output reg         sobel_ready
);

    localparam integer PIPE_LAT = 2; // sobel 내부 고정 지연

    // x/y 좌표 추출
    wire [8:0] x = pixel_addr[8:0];
    wire [8:0] y = pixel_addr[16:9];

    // align coords and pixel_in to stage-2 latency (2 clocks)
    reg [8:0] x_d1 = 9'd0, x_d2 = 9'd0;
    reg [8:0] y_d1 = 9'd0, y_d2 = 9'd0;
    reg [7:0] pix_d1 = 8'd0, pix_d2 = 8'd0;
    always @(posedge clk) begin
        if (enable && active_area) begin
            x_d1 <= x;   x_d2 <= x_d1;
            y_d1 <= y;   y_d2 <= y_d1;
            pix_d1 <= pixel_in; pix_d2 <= pix_d1;
        end else begin
            x_d1 <= 9'd0; x_d2 <= 9'd0;
            y_d1 <= 9'd0; y_d2 <= 9'd0;
            pix_d1 <= 8'd0; pix_d2 <= 8'd0;
        end
    end

    // 프레임/라인 시작 검출
    reg vsync_prev  = 1'b0;
    reg active_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end
    wire frame_start = (vsync && !vsync_prev);
    wire line_start  = (active_area && !active_prev);

    // 2개 라인 버퍼 (핑퐁)와 수평 3탭 시프트레지스터
    reg [7:0] lb0 [0:319];
    reg [7:0] lb1 [0:319];
    reg       wr_sel = 1'b0; // 각 라인 시작마다 토글

    reg [7:0] top_sr0, top_sr1, top_sr2; // y-2
    reg [7:0] mid_sr0, mid_sr1, mid_sr2; // y-1
    reg [7:0] cur_sr0, cur_sr1, cur_sr2; // y

    // 내부 유효 신호 (상위 필터에서 이미 유효한 데이터만 받음)
    wire window_valid = enable && active_area;

    // 현재 x에서 라인버퍼 읽기 (쓰기 전에 읽음)
    wire [7:0] top_in = (wr_sel == 1'b0) ? lb0[x] : lb1[x]; // y-2
    wire [7:0] mid_in = (wr_sel == 1'b0) ? lb1[x] : lb0[x]; // y-1

    // 시프트/쓰기
    always @(posedge clk) begin
        if (frame_start) begin
            wr_sel <= 1'b0;
            top_sr0 <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
            mid_sr0 <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
            cur_sr0 <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
        end else begin
            if (line_start) begin
                wr_sel  <= ~wr_sel;
                top_sr0 <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
                mid_sr0 <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
                cur_sr0 <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
            end
            if (enable && active_area) begin
                top_sr2 <= top_sr1;  top_sr1 <= top_sr0;  top_sr0 <= top_in;
                mid_sr2 <= mid_sr1;  mid_sr1 <= mid_sr0;  mid_sr0 <= mid_in;
                cur_sr2 <= cur_sr1;  cur_sr1 <= cur_sr0;  cur_sr0 <= pixel_in;
                if (wr_sel == 1'b0) lb0[x] <= pixel_in; else lb1[x] <= pixel_in;
            end
        end
    end

    // 다음 사이클 시프트 결과(현재 픽셀 포함)를 조합해 탭 구성
    wire [7:0] n_top_sr0 = top_in;
    wire [7:0] n_top_sr1 = top_sr0;
    wire [7:0] n_top_sr2 = top_sr1;
    wire [7:0] n_mid_sr0 = mid_in;
    wire [7:0] n_mid_sr1 = mid_sr0;
    wire [7:0] n_mid_sr2 = mid_sr1;
    wire [7:0] n_cur_sr0 = pixel_in;
    wire [7:0] n_cur_sr1 = cur_sr0;
    wire [7:0] n_cur_sr2 = cur_sr1;

    // 수평/수직 경계 복제(clamp) - 0으로 패딩하여 인위적 경계 방지
    wire [7:0] top_x0 = n_top_sr0;
    wire [7:0] top_x1 = (x == 9'd0) ? 8'd0 : n_top_sr1;
    wire [7:0] top_x2 = (x == 9'd0) ? 8'd0 : ((x == 9'd1) ? 8'd0 : n_top_sr2);
    wire [7:0] mid_x0 = n_mid_sr0;
    wire [7:0] mid_x1 = (x == 9'd0) ? 8'd0 : n_mid_sr1;
    wire [7:0] mid_x2 = (x == 9'd0) ? 8'd0 : ((x == 9'd1) ? 8'd0 : n_mid_sr2);
    wire [7:0] cur_x0 = n_cur_sr0;
    wire [7:0] cur_x1 = (x == 9'd0) ? 8'd0 : n_cur_sr1;
    wire [7:0] cur_x2 = (x == 9'd0) ? 8'd0 : ((x == 9'd1) ? 8'd0 : n_cur_sr2);

    wire [7:0] selT_x0 = (y == 9'd0) ? 8'd0 : ((y == 9'd1) ? 8'd0 : top_x0);
    wire [7:0] selT_x1 = (y == 9'd0) ? 8'd0 : ((y == 9'd1) ? 8'd0 : top_x1);
    wire [7:0] selT_x2 = (y == 9'd0) ? 8'd0 : ((y == 9'd1) ? 8'd0 : top_x2);
    wire [7:0] selM_x0 = (y == 9'd0) ? 8'd0 : mid_x0;
    wire [7:0] selM_x1 = (y == 9'd0) ? 8'd0 : mid_x1;
    wire [7:0] selM_x2 = (y == 9'd0) ? 8'd0 : mid_x2;

    // 최종 3x3 탭
    wire [7:0] g00 = selT_x2; // (x-2, y-2)
    wire [7:0] g01 = selT_x1; // (x-1, y-2)
    wire [7:0] g02 = selT_x0; // (x  , y-2)
    wire [7:0] g10 = selM_x2; // (x-2, y-1)
    wire [7:0] g11 = selM_x1; // (x-1, y-1)
    wire [7:0] g12 = selM_x0; // (x  , y-1)
    wire [7:0] g20 = cur_x2;  // (x-2, y  )
    wire [7:0] g21 = cur_x1;  // (x-1, y  )
    wire [7:0] g22 = cur_x0;  // (x  , y  )

    // Sobel 계산 (1단: 그래디언트, 2단: 크기/포화)
    // Gx = [-1 0 +1; -2 0 +2; -1 0 +1]
    // Gy = [+1 +2 +1;  0 0  0; -1 -2 -1]
    reg [10:0] gx_abs;
    reg [10:0] gy_abs;
    reg [11:0] mag;
    wire [10:0] gx_pos = {3'b0,g02} + {2'b0,g12,1'b0} + {3'b0,g22};
    wire [10:0] gx_neg = {3'b0,g00} + {2'b0,g10,1'b0} + {3'b0,g20};
    wire [10:0] gy_pos = {3'b0,g00} + {2'b0,g01,1'b0} + {3'b0,g02};
    wire [10:0] gy_neg = {3'b0,g20} + {2'b0,g21,1'b0} + {3'b0,g22};

    reg [PIPE_LAT-1:0] vpipe = {PIPE_LAT{1'b0}};
    always @(posedge clk) begin
        if (frame_start) begin
            gx_abs <= 11'd0;
            gy_abs <= 11'd0;
            mag    <= 12'd0;
            vpipe  <= {PIPE_LAT{1'b0}};
            pixel_out <= 8'd0;
            sobel_ready <= 1'b0;
        end else begin
            vpipe <= {vpipe[PIPE_LAT-2:0], window_valid};
            // stage 1: |gx|, |gy|
            if (window_valid) begin
                gx_abs <= (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
                gy_abs <= (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
            end else begin
                gx_abs <= 11'd0;
                gy_abs <= 11'd0;
            end
            // stage 2: magnitude + clamp -> output
            mag <= {1'b0,gx_abs} + {1'b0,gy_abs};
            if (vpipe[PIPE_LAT-1]) begin
                // 상위 가우시안 필터에서 이미 유효한 데이터만 받으므로 경계 처리 불필요
                // saturate to 8-bit then apply threshold -> binary edge map
                if ((mag[11:8] != 4'b0000 ? 8'hFF : mag[7:0]) >= threshold)
                    pixel_out <= 8'hFF;
                else
                    pixel_out <= 8'h00;
            end else begin
                pixel_out <= 8'h00;
            end
            // 상위 가우시안 필터에서 이미 유효한 데이터만 받으므로 sobel_ready는 파이프라인 지연만 고려
            sobel_ready <= vpipe[PIPE_LAT-1];
        end
    end

endmodule


