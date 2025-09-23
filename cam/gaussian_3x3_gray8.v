// 3x3 Gaussian blur for 8-bit grayscale (streaming, true 3x3 with 2 line buffers)
module gaussian_3x3_gray8 (
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,   // {y[16:9], x[8:0]} with x:0..319, y:0..239
    input  wire        vsync,
    input  wire        active_area,
    output reg  [7:0]  pixel_out,
    output reg         filter_ready
);

    // parameters: total pipeline latency (register stages) = 4
    localparam integer PIPE_LAT = 4;

    // x/y from address
    wire [8:0] x = pixel_addr[8:0];
    wire [8:0] y = pixel_addr[16:9];

    // edge detection
    reg vsync_prev  = 1'b0;
    reg active_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end
    wire frame_start = (vsync && !vsync_prev);
    wire line_start  = (active_area && !active_prev);

    // two line buffers (ping-pong): store y-1 and y-2
    reg [7:0] lb0 [0:319];
    reg [7:0] lb1 [0:319];
    reg       wr_sel = 1'b0; // toggles each active line; selects buffer being written (holds y-2 before write)

    // horizontal 3-tap shift registers for each of the three rows (y-2, y-1, y)
    reg [7:0] top_sr0, top_sr1, top_sr2; // y-2: [x, x-1, x-2]
    reg [7:0] mid_sr0, mid_sr1, mid_sr2; // y-1
    reg [7:0] cur_sr0, cur_sr1, cur_sr2; // y

    // 입력 유효: 경계는 내부에서 복제(clamp) 처리하므로 전체 활성 영역에서 유효
    wire window_valid = enable && active_area;

    // tap inputs from line buffers (read-before-write for current x)
    wire [7:0] top_in = (wr_sel == 1'b0) ? lb0[x] : lb1[x]; // y-2
    wire [7:0] mid_in = (wr_sel == 1'b0) ? lb1[x] : lb0[x]; // y-1

    // shift/update per pixel
    // (디버그 잔여 변수 제거)
    always @(posedge clk) begin
        if (frame_start) begin
            wr_sel   <= 1'b0;
            top_sr0  <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
            mid_sr0  <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
            cur_sr0  <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
        end else begin
            if (line_start) begin
                // toggle write buffer and clear horizontal taps at the start of each active line
                wr_sel  <= ~wr_sel;
                top_sr0 <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
                mid_sr0 <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
                cur_sr0 <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
            end
            if (enable && active_area) begin
                // shift horizontal windows
                top_sr2 <= top_sr1;  top_sr1 <= top_sr0;  top_sr0 <= top_in;
                mid_sr2 <= mid_sr1;  mid_sr1 <= mid_sr0;  mid_sr0 <= mid_in;
                cur_sr2 <= cur_sr1;  cur_sr1 <= cur_sr0;  cur_sr0 <= pixel_in;
                // write current pixel to the 'older' buffer (which currently holds y-2)
                if (wr_sel == 1'b0) lb0[x] <= pixel_in; else lb1[x] <= pixel_in;
            end
        end
    end

    // 다음 사이클에 적용될 시프트 결과를 조합으로 계산하여 "현재 픽셀"도 포함한 탭 구성
    wire [7:0] n_top_sr0 = top_in;
    wire [7:0] n_top_sr1 = top_sr0;
    wire [7:0] n_top_sr2 = top_sr1;
    wire [7:0] n_mid_sr0 = mid_in;
    wire [7:0] n_mid_sr1 = mid_sr0;
    wire [7:0] n_mid_sr2 = mid_sr1;
    wire [7:0] n_cur_sr0 = pixel_in;
    wire [7:0] n_cur_sr1 = cur_sr0;
    wire [7:0] n_cur_sr2 = cur_sr1;

    // 수평 클램프 적용된 탭 (x 경계 처리)
    wire [7:0] top_x0 = n_top_sr0;
    wire [7:0] top_x1 = (x == 9'd0) ? n_top_sr0 : n_top_sr1;
    wire [7:0] top_x2 = (x == 9'd0) ? n_top_sr0 : ((x == 9'd1) ? n_top_sr1 : n_top_sr2);
    wire [7:0] mid_x0 = n_mid_sr0;
    wire [7:0] mid_x1 = (x == 9'd0) ? n_mid_sr0 : n_mid_sr1;
    wire [7:0] mid_x2 = (x == 9'd0) ? n_mid_sr0 : ((x == 9'd1) ? n_mid_sr1 : n_mid_sr2);
    wire [7:0] cur_x0 = n_cur_sr0;
    wire [7:0] cur_x1 = (x == 9'd0) ? n_cur_sr0 : n_cur_sr1;
    wire [7:0] cur_x2 = (x == 9'd0) ? n_cur_sr0 : ((x == 9'd1) ? n_cur_sr1 : n_cur_sr2);

    // 수직 클램프 적용된 행 선택 (y 경계 처리)
    wire [7:0] selT_x0 = (y == 9'd0) ? cur_x0 : ((y == 9'd1) ? mid_x0 : top_x0);
    wire [7:0] selT_x1 = (y == 9'd0) ? cur_x1 : ((y == 9'd1) ? mid_x1 : top_x1);
    wire [7:0] selT_x2 = (y == 9'd0) ? cur_x2 : ((y == 9'd1) ? mid_x2 : top_x2);
    wire [7:0] selM_x0 = (y == 9'd0) ? cur_x0 : mid_x0;
    wire [7:0] selM_x1 = (y == 9'd0) ? cur_x1 : mid_x1;
    wire [7:0] selM_x2 = (y == 9'd0) ? cur_x2 : mid_x2;

    // 최종 3x3 탭 매핑
    wire [7:0] g00 = selT_x2; // (x-2, y-2)
    wire [7:0] g01 = selT_x1; // (x-1, y-2)
    wire [7:0] g02 = selT_x0; // (x  , y-2)
    wire [7:0] g10 = selM_x2; // (x-2, y-1)
    wire [7:0] g11 = selM_x1; // (x-1, y-1)
    wire [7:0] g12 = selM_x0; // (x  , y-1)
    wire [7:0] g20 = cur_x2;  // (x-2, y  )
    wire [7:0] g21 = cur_x1;  // (x-1, y  )
    wire [7:0] g22 = cur_x0;  // (x  , y  )

    // 3x3 Gaussian kernel sum = (corners) + 2*(edges) + 4*(center)
    wire [11:0] sum_corners = {4'b0, g00} + {4'b0, g02}
                             + {4'b0, g20} + {4'b0, g22};
    wire [11:0] sum_edges   = ({4'b0, g01} + {4'b0, g10}
                             + {4'b0, g12} + {4'b0, g21}) << 1;
    wire [11:0] sum_center  = {4'b0, g11} << 2;

    // pipeline stages to match GAUSS_LAT=4 at top level
    reg [11:0] p_sum1 = 12'd0;
    reg [11:0] p_sum2 = 12'd0;
    reg [7:0]  p_out3 = 8'd0;
    reg [PIPE_LAT-1:0] vpipe = {PIPE_LAT{1'b0}};

    always @(posedge clk) begin
        if (frame_start) begin
            p_sum1   <= 12'd0;
            p_sum2   <= 12'd0;
            p_out3   <= 8'd0;
            vpipe    <= {PIPE_LAT{1'b0}};
            pixel_out <= 8'd0;
            filter_ready <= 1'b0;
        end else begin
            // valid pipeline
            vpipe <= {vpipe[PIPE_LAT-2:0], window_valid};

            // stage 1: weighted sum
            if (window_valid) begin
                p_sum1 <= sum_corners + sum_edges + sum_center;
            end else begin
                p_sum1 <= 12'd0;
            end
            // stage 2: register
            p_sum2 <= p_sum1;
            // stage 3: normalize (/16)
            p_out3 <= p_sum2[11:4];
            // stage 4: output + ready flag
            pixel_out   <= vpipe[PIPE_LAT-1] ? p_out3 : 8'h00;
            filter_ready <= vpipe[PIPE_LAT-1];
        end
    end

endmodule
