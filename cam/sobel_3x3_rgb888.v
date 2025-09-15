// RGB888용 3x3 소벨 엣지 검출 필터
module sobel_3x3_rgb888 (
    input  wire        clk,           // 25MHz VGA 클럭
    input  wire        enable,        // 필터 활성화 신호
    input  wire [23:0] pixel_in,      // 입력 픽셀 (RGB888)
    input  wire [16:0] pixel_addr,    // 픽셀 주소
    input  wire        vsync,         // 수직 동기화
    input  wire        active_area,   // 활성 영역 신호
    output reg  [7:0]  sobel_value,   // 소벨 필터 값 (0-255)
    output reg         sobel_ready    // 필터 처리 완료 신호
);

    // 픽셀 위치 계산
    wire [8:0] x_pos = pixel_addr[8:0];   // X 좌표 (0-319)
    wire [8:0] y_pos = pixel_addr[16:9];  // Y 좌표 (0-239)
    
    // 주소 유효성 검사
    wire valid_addr = (x_pos < 320) && (y_pos < 240);
    
    // 3x3 윈도우 캐시 (RGB888)
    reg [23:0] cache1 [2:0];  // 첫 번째 줄 캐시 (3픽셀)
    reg [23:0] cache2 [2:0];  // 두 번째 줄 캐시 (3픽셀)
    reg [23:0] cache3 [2:0];  // 세 번째 줄 캐시 (3픽셀)
    
    // 3x3 윈도우 출력
    wire [23:0] p00, p01, p02;  // 첫 번째 줄
    wire [23:0] p10, p11, p12;  // 두 번째 줄
    wire [23:0] p20, p21, p22;  // 세 번째 줄
    
    // RGB888 그레이스케일 변환 함수
    function [7:0] rgb888_to_gray;
        input [23:0] rgb888;
        reg [8:0] temp_sum;
        reg [7:0] r, g, b;
        begin
            // RGB888에서 RGB 추출
            r = rgb888[23:16];
            g = rgb888[15:8];
            b = rgb888[7:0];
            
            // Y = 0.299*R + 0.587*G + 0.114*B (근사값)
            // Y = (R + 2*G + B) / 4
            temp_sum = r + g + g + b;
            rgb888_to_gray = temp_sum[8:2];  // >> 2 (4로 나누기)
        end
    endfunction
    
    // 3x3 윈도우 출력 (세로줄 노이즈 제거)
    reg [23:0] p00_r, p01_r, p02_r, p10_r, p11_r, p12_r, p20_r, p21_r, p22_r;
    
    always @(*) begin
        if (y_pos == 0 && x_pos == 0) begin
            // 첫 번째 픽셀 (1,1)
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = 24'h000000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos == 0 && x_pos > 0 && x_pos < 319) begin
            // 첫 번째 줄 중간 (1,2~318)
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos == 0 && x_pos == 319) begin
            // 첫 번째 줄 마지막 (1,319)
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 24'h000000;
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = 24'h000000;
        end else if (y_pos > 0 && y_pos < 239 && x_pos == 0) begin
            // 중간 줄 첫 번째 (2~239,1)
            p00_r = 24'h000000; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = 24'h000000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos > 0 && y_pos < 239 && x_pos > 0 && x_pos < 319) begin
            // 중간 줄 중간 (2~239,2~318) - 정상 3x3 윈도우
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos > 0 && y_pos < 239 && x_pos == 319) begin
            // 중간 줄 마지막 (2~239,319)
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 24'h000000;
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = 24'h000000;
        end else if (y_pos == 239 && x_pos == 0) begin
            // 마지막 줄 첫 번째 (240,1)
            p00_r = 24'h000000; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = 24'h000000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end else if (y_pos == 239 && x_pos > 0 && x_pos < 319) begin
            // 마지막 줄 중간 (240,2~318)
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end else if (y_pos == 239 && x_pos == 319) begin
            // 마지막 줄 마지막 (240,319)
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = 24'h000000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 24'h000000;
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end else begin
            // 기본값
            p00_r = 24'h000000; p01_r = 24'h000000; p02_r = 24'h000000;
            p10_r = 24'h000000; p11_r = 24'h000000; p12_r = 24'h000000;
            p20_r = 24'h000000; p21_r = 24'h000000; p22_r = 24'h000000;
        end
    end
    
    assign p00 = p00_r; assign p01 = p01_r; assign p02 = p02_r;
    assign p10 = p10_r; assign p11 = p11_r; assign p12 = p12_r;
    assign p20 = p20_r; assign p21 = p21_r; assign p22 = p22_r;
    
    // 3x3 윈도우의 그레이스케일 값들
    reg [7:0] g00, g01, g02;  // 첫 번째 줄
    reg [7:0] g10, g11, g12;  // 두 번째 줄
    reg [7:0] g20, g21, g22;  // 세 번째 줄
    
    // VSYNC 리셋 제어
    reg vsync_prev;
    reg reset_done;
    
    // VSYNC 상승 에지 감지
    always @(posedge clk) begin
        vsync_prev <= vsync;
    end
    
    // 캐시 시프트
    reg [1:0] init_state;
    
    always @(posedge clk) begin
        if (vsync && !vsync_prev) begin
            // VSYNC 상승 에지에서 리셋
            reset_done <= 1'b0;
            init_state <= 2'b00;
            cache1[0] <= 24'h000000; cache1[1] <= 24'h000000; cache1[2] <= 24'h000000;
            cache2[0] <= 24'h000000; cache2[1] <= 24'h000000; cache2[2] <= 24'h000000;
            cache3[0] <= 24'h000000; cache3[1] <= 24'h000000; cache3[2] <= 24'h000000;
        end else if (valid_addr && active_area) begin
            if (!reset_done) begin
                // 초기화 단계별 처리
                case (init_state)
                    2'b00: begin
                        // 첫 번째 줄 초기화
                        cache1[0] <= 24'h000000; cache1[1] <= 24'h000000; cache1[2] <= 24'h000000;
                        cache2[0] <= 24'h000000; cache2[1] <= pixel_in; cache2[2] <= 24'h000000;
                        cache3[0] <= 24'h000000; cache3[1] <= 24'h000000; cache3[2] <= 24'h000000;
                        init_state <= 2'b01;
                    end
                    2'b01: begin
                        // 두 번째 줄 초기화
                        cache1[0] <= 24'h000000; cache1[1] <= 24'h000000; cache1[2] <= 24'h000000;
                        cache2[0] <= cache2[1]; cache2[1] <= cache2[2]; cache2[2] <= pixel_in;
                        cache3[0] <= 24'h000000; cache3[1] <= 24'h000000; cache3[2] <= 24'h000000;
                        init_state <= 2'b10;
                    end
                    2'b10: begin
                        // 세 번째 줄 초기화 완료
                        cache1[0] <= 24'h000000; cache1[1] <= 24'h000000; cache1[2] <= 24'h000000;
                        cache2[0] <= cache2[1]; cache2[1] <= cache2[2]; cache2[2] <= cache3[1];
                        cache3[0] <= 24'h000000; cache3[1] <= 24'h000000; cache3[2] <= pixel_in;
                        reset_done <= 1'b1;
                        init_state <= 2'b11;
                    end
                    default: begin
                        reset_done <= 1'b1;
                    end
                endcase
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
    
    // 그레이스케일 변환
    always @(posedge clk) begin
        if (reset_done && valid_addr && active_area) begin
            g00 <= rgb888_to_gray(p00);
            g01 <= rgb888_to_gray(p01);
            g02 <= rgb888_to_gray(p02);
            g10 <= rgb888_to_gray(p10);
            g11 <= rgb888_to_gray(p11);
            g12 <= rgb888_to_gray(p12);
            g20 <= rgb888_to_gray(p20);
            g21 <= rgb888_to_gray(p21);
            g22 <= rgb888_to_gray(p22);
        end else begin
            g00 <= 8'h00; g01 <= 8'h00; g02 <= 8'h00;
            g10 <= 8'h00; g11 <= 8'h00; g12 <= 8'h00;
            g20 <= 8'h00; g21 <= 8'h00; g22 <= 8'h00;
        end
    end
    
    // 소벨 계산
    reg [9:0] gx_sum, gy_sum;
    reg [9:0] gx_abs, gy_abs;
    reg [10:0] sobel_magnitude;
    reg [7:0] sobel_value_temp;
    reg [10:0] edge_threshold;
    reg [7:0] simple_edge;
    reg [10:0] noise_threshold;
    
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            // 임계값 설정
            edge_threshold <= 11'd25;
            noise_threshold <= 11'd12;
            
            if (y_pos > 1 && x_pos > 1 && y_pos < 238 && x_pos < 318) begin
                // 정상 3x3 윈도우 영역
                gx_sum <= g02 + (g12 << 1) + g22 - g00 - (g10 << 1) - g20;
                gy_sum <= g20 + (g21 << 1) + g22 - g00 - (g01 << 1) - g02;
                
                // 절댓값 계산
                gx_abs <= gx_sum[9] ? (~gx_sum + 1) : gx_sum;
                gy_abs <= gy_sum[9] ? (~gy_sum + 1) : gy_sum;
                
                // 소벨 강도 계산
                sobel_magnitude <= gx_abs + gy_abs;
                
                // 이진화
                if (sobel_magnitude > edge_threshold) begin
                    sobel_value_temp <= 8'hFF;
                end else if (sobel_magnitude > noise_threshold) begin
                    sobel_value_temp <= (sobel_magnitude > 10'd255) ? 8'd255 : sobel_magnitude[7:0];
                end else begin
                    sobel_value_temp <= 8'h00;
                end
                sobel_ready <= 1'b1;
                
            end else if (y_pos > 0 && x_pos > 0 && y_pos < 239 && x_pos < 319) begin
                // 경계 영역
                simple_edge = (g11 > g10) ? (g11 - g10) : (g10 - g11);
                simple_edge = simple_edge + ((g11 > g01) ? (g11 - g01) : (g01 - g11));
                simple_edge = simple_edge + ((g11 > g12) ? (g11 - g12) : (g12 - g11));
                simple_edge = simple_edge + ((g11 > g21) ? (g11 - g21) : (g21 - g11));
                
                if (simple_edge > 8'd40) begin
                    sobel_value_temp <= 8'hFF;
                end else if (simple_edge > 8'd20) begin
                    sobel_value_temp <= simple_edge;
                end else begin
                    sobel_value_temp <= 8'h00;
                end
                sobel_ready <= 1'b1;
                
            end else begin
                sobel_value_temp <= 8'h00;
                sobel_ready <= 1'b0;
            end
            
        end else begin
            sobel_ready <= 1'b0;
        end
    end
    
    // 출력 처리
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area && sobel_ready) begin
            if (sobel_value_temp == 8'hFF) begin
                sobel_value <= 8'hFF;
            end else if (sobel_value_temp > 8'd200) begin
                sobel_value <= 8'hFF;
            end else if (sobel_value_temp > 8'd100) begin
                sobel_value <= sobel_value_temp;
            end else if (sobel_value_temp > 8'd50) begin
                sobel_value <= sobel_value_temp + 8'd20;
            end else begin
                sobel_value <= 8'h00;
            end
        end else begin
            sobel_value <= 8'h00;
        end
    end

endmodule
