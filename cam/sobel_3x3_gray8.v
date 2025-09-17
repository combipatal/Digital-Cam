// 3x3 Sobel filter for 8-bit grayscale
module sobel_3x3_gray8 (
    input  wire        clk,
    input  wire        enable,
    input  wire [7:0]  pixel_in,
    input  wire [16:0] pixel_addr,
    input  wire        vsync,
    input  wire        active_area,
    output reg  [7:0]  pixel_out,
    output reg         sobel_ready
);

    // init and vsync edge
    reg vsync_prev = 1'b0;
    always @(posedge clk) begin
        vsync_prev <= vsync;
    end

    reg        reset_done = 1'b0;
    reg [2:0]  init_counter = 3'd0; // 6 clocks to prime 3x3

    // 3x3 caches
    reg [7:0] cache1 [0:2];
    reg [7:0] cache2 [0:2];
    reg [7:0] cache3 [0:2];

    wire valid_addr = 1'b1;

    wire [7:0] p00 = cache1[0];
    wire [7:0] p01 = cache1[1];
    wire [7:0] p02 = cache1[2];
    wire [7:0] p10 = cache2[0];
    wire [7:0] p11 = cache2[1];
    wire [7:0] p12 = cache2[2];
    wire [7:0] p20 = cache3[0];
    wire [7:0] p21 = cache3[1];
    wire [7:0] p22 = cache3[2];

    // line/window maintenance
    always @(posedge clk) begin
        if (vsync && !vsync_prev) begin
            reset_done   <= 1'b0;
            init_counter <= 3'd0;
            cache1[0] <= 8'h00; cache1[1] <= 8'h00; cache1[2] <= 8'h00;
            cache2[0] <= 8'h00; cache2[1] <= 8'h00; cache2[2] <= 8'h00;
            cache3[0] <= 8'h00; cache3[1] <= 8'h00; cache3[2] <= 8'h00;
        end else if (enable && valid_addr && active_area) begin
            if (!reset_done) begin
                if (init_counter < 3'd5) begin
                    init_counter <= init_counter + 1'b1;
                    cache1[0] <= 8'h00; cache1[1] <= 8'h00; cache1[2] <= 8'h00;
                    cache2[0] <= 8'h00; cache2[1] <= 8'h00; cache2[2] <= 8'h00;
                    cache3[0] <= 8'h00; cache3[1] <= 8'h00; cache3[2] <= 8'h00;
                end else begin
                    reset_done <= 1'b1;
                    cache1[0] <= cache1[1];
                    cache1[1] <= cache1[2];
                    cache1[2] <= cache2[1];

                    cache2[0] <= cache2[1];
                    cache2[1] <= cache2[2];
                    cache2[2] <= cache3[1];

                    cache3[0] <= cache3[1];
                    cache3[1] <= cache3[2];
                    cache3[2] <= pixel_in;
                end
            end else begin
                cache1[0] <= cache1[1];
                cache1[1] <= cache1[2];
                cache1[2] <= cache2[1];

                cache2[0] <= cache2[1];
                cache2[1] <= cache2[2];
                cache2[2] <= cache3[1];

                cache3[0] <= cache3[1];
                cache3[1] <= cache3[2];
                cache3[2] <= pixel_in;
            end
        end
    end

    // sobel compute (1 clock)
    // Gx = [-1 0 +1; -2 0 +2; -1 0 +1]
    // Gy = [+1 +2 +1;  0 0  0; -1 -2 -1]
    reg [10:0] gx_abs;
    reg [10:0] gy_abs;
    reg [10:0] mag;
    // Precompute partial sums as wires to avoid block-local reg declarations
    wire [10:0] gx_pos = {3'b000,p02} + {2'b00,p12,1'b0} + {3'b000,p22};
    wire [10:0] gx_neg = {3'b000,p00} + {2'b00,p10,1'b0} + {3'b000,p20};
    wire [10:0] gy_pos = {3'b000,p00} + {2'b00,p01,1'b0} + {3'b000,p02};
    wire [10:0] gy_neg = {3'b000,p20} + {2'b00,p21,1'b0} + {3'b000,p22};
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            // compute |gx| and |gy| using precomputed wires
            gx_abs <= (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
            gy_abs <= (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
            // magnitude approx = min(255, gx_abs + gy_abs)
            mag <= gx_abs + gy_abs;
        end else begin
            gx_abs <= 11'd0;
            gy_abs <= 11'd0;
            mag    <= 11'd0;
        end
    end

    // clamp & output (임계값 하향/완화)
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            // 이전: 포화 조건이 낮아 암부가 쉽게 0에 가까워졌음
            // 변경: 소프트 임계 + 약한 감마 보정
            // 1) 소프트 컷: 4를 빼고 하한 0 고정
            // 2) 약한 확장: 상위 비트 손실 줄이기 위해 (mag - 4) << 0 (동일) 유지
            // 3) 상위 포화는 동일
            if (mag[10:8] != 3'b000) begin
                pixel_out <= 8'hFF;
            end else begin
                pixel_out <= (mag[7:0] > 8'd2) ? (mag[7:0] - 8'd2) : 8'd0;
            end
            sobel_ready <= 1'b1;
        end else begin
            pixel_out   <= 8'h00;  // 초기화 중 또는 비활성 영역에서 검은색
            sobel_ready <= 1'b0;
        end
    end

endmodule


