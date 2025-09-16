// RGB888용 3x3 가우시안 블러 (커널 1 2 1 / 2 4 2 / 1 2 1, 정규화 16)
module gaussian_3x3_rgb888 (
    input  wire        clk,           // 25MHz VGA 클럭
    input  wire        enable,        // 필터 활성화 신호
    input  wire [23:0] pixel_in,      // 입력 픽셀 (RGB888)
    input  wire [16:0] pixel_addr,    // 픽셀 주소
    input  wire        vsync,         // 수직 동기화
    input  wire        active_area,   // 활성 영역 신호
    output reg  [23:0] pixel_out,     // 출력 픽셀 (필터 적용 후, RGB888)
    output reg         filter_ready   // 필터 처리 완료 신호
);

    // 픽셀 위치 계산
    wire [8:0] x_pos = pixel_addr[8:0];
    wire [8:0] y_pos = pixel_addr[16:9];

    // 주소 유효성 검사
    wire valid_addr = (x_pos < 320) && (y_pos < 240);

    // 3x3 윈도우 캐시 (RGB888)
    reg [23:0] cache1 [2:0];  // 위 라인
    reg [23:0] cache2 [2:0];  // 중간 라인
    reg [23:0] cache3 [2:0];  // 아래 라인

    // 3x3 윈도우 출력
    wire [23:0] p00, p01, p02;
    wire [23:0] p10, p11, p12;
    wire [23:0] p20, p21, p22;

    // 3x3 윈도우 선택 로직 (경계는 0 패딩)
    reg [23:0] p00_r, p01_r, p02_r, p10_r, p11_r, p12_r, p20_r, p21_r, p22_r;

    // VSYNC 리셋 제어
    reg vsync_prev;
    reg reset_done;
    reg [2:0] init_counter;  // 초기화 카운터 (0-4)

    always @(posedge clk) begin
        vsync_prev <= vsync;
    end

    always @(*) begin
        if (y_pos == 0 && x_pos == 0) begin
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = 24'h000000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos == 0 && x_pos > 0 && x_pos < 319) begin
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos == 0 && x_pos == 319) begin
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 24'h000000;
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = 24'h000000;
        end else if (y_pos > 0 && y_pos < 239 && x_pos == 0) begin
            p00_r = 24'h000000; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = 24'h000000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos > 0 && y_pos < 239 && x_pos > 0 && x_pos < 319) begin
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos > 0 && y_pos < 239 && x_pos == 319) begin
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 24'h000000;
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = 24'h000000;
        end else if (y_pos == 239 && x_pos == 0) begin
            p00_r = 24'h000000; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = 24'h000000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end else if (y_pos == 239 && x_pos > 0 && x_pos < 319) begin
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end else if (y_pos == 239 && x_pos == 319) begin
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 24'h000000;
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end else begin
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = 24'h000000; p11_r = 24'h000000; p12_r = 24'h000000;
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end
    end

    assign p00 = p00_r; assign p01 = p01_r; assign p02 = p02_r;
    assign p10 = p10_r; assign p11 = p11_r; assign p12 = p12_r;
    assign p20 = p20_r; assign p21 = p21_r; assign p22 = p22_r;

    // 캐시 시프트 및 초기화 (소벨 필터와 동일한 방식)
    always @(posedge clk) begin
        if (vsync && !vsync_prev) begin
            // VSYNC 상승 에지에서 리셋
            reset_done <= 1'b0;
            init_counter <= 3'd0;
            cache1[0] <= 24'h000000; cache1[1] <= 24'h000000; cache1[2] <= 24'h000000;
            cache2[0] <= 24'h000000; cache2[1] <= 24'h000000; cache2[2] <= 24'h000000;
            cache3[0] <= 24'h000000; cache3[1] <= 24'h000000; cache3[2] <= 24'h000000;
        end else if (valid_addr && active_area) begin
            if (!reset_done) begin
                // 초기화 단계별 처리 - 6클럭에 걸쳐 안정적으로 초기화
                if (init_counter < 3'd5) begin
                    init_counter <= init_counter + 1'b1;
                    // 초기화 중에는 캐시를 0으로 유지
                    cache1[0] <= 24'h000000; cache1[1] <= 24'h000000; cache1[2] <= 24'h000000;
                    cache2[0] <= 24'h000000; cache2[1] <= 24'h000000; cache2[2] <= 24'h000000;
                    cache3[0] <= 24'h000000; cache3[1] <= 24'h000000; cache3[2] <= 24'h000000;
                end else begin
                    // 초기화 완료 - 7클럭째부터 정상 동작 (3x3 윈도우 완성)
                    reset_done <= 1'b1;
                    // 정상 시프트
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
                // 정상 동작 - 시프트
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

    // 가우시안 연산
    wire [7:0] r00 = p00[23:16], r01 = p01[23:16], r02 = p02[23:16];
    wire [7:0] r10 = p10[23:16], r11 = p11[23:16], r12 = p12[23:16];
    wire [7:0] r20 = p20[23:16], r21 = p21[23:16], r22 = p22[23:16];

    wire [7:0] g00 = p00[15:8],  g01 = p01[15:8],  g02 = p02[15:8];
    wire [7:0] g10 = p10[15:8],  g11 = p11[15:8],  g12 = p12[15:8];
    wire [7:0] g20 = p20[15:8],  g21 = p21[15:8],  g22 = p22[15:8];

    wire [7:0] b00 = p00[7:0],   b01 = p01[7:0],   b02 = p02[7:0];
    wire [7:0] b10 = p10[7:0],   b11 = p11[7:0],   b12 = p12[7:0];
    wire [7:0] b20 = p20[7:0],   b21 = p21[7:0],   b22 = p22[7:0];

    reg [11:0] r_sum, g_sum, b_sum; // 최대 16*255=4080 < 4096
    reg [7:0]  r_blur, g_blur, b_blur;

    // 가우시안 연산 (1클럭)
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            // (1 2 1; 2 4 2; 1 2 1) 합산
            r_sum <= (r00 + r02 + r20 + r22) + ((r01 + r10 + r12 + r21) << 1) + (r11 << 2);
            g_sum <= (g00 + g02 + g20 + g22) + ((g01 + g10 + g12 + g21) << 1) + (g11 << 2);
            b_sum <= (b00 + b02 + b20 + b22) + ((b01 + b10 + b12 + b21) << 1) + (b11 << 2);
        end else begin
            r_sum <= 12'h000;
            g_sum <= 12'h000;
            b_sum <= 12'h000;
        end
    end
    
    // 정규화 및 출력 (1클럭)
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            // 정규화 (/16)
            r_blur <= r_sum[11:4];
            g_blur <= g_sum[11:4];
            b_blur <= b_sum[11:4];

            pixel_out <= {r_blur, g_blur, b_blur};
            filter_ready <= 1'b1;
        end else begin
            pixel_out <= 24'h000000;
            filter_ready <= 1'b0;
        end
    end

endmodule


