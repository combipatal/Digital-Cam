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
    
    // RGB888 그레이스케일 변환 함수 (개선된 정확도)
    function [7:0] rgb888_to_gray;
        input [23:0] rgb888;
        reg [10:0] temp_sum;  // 더 큰 비트폭으로 정확도 향상
        reg [7:0] r, g, b;
        begin
            // RGB888에서 RGB 추출
            r = rgb888[23:16];
            g = rgb888[15:8];
            b = rgb888[7:0];
            
            // Y = 0.299*R + 0.587*G + 0.114*B (ITU-R BT.709 표준)
            // 더 정확한 정수 연산: Y = (76*R + 150*G + 30*B) / 256
            // 76/256 ≈ 0.2969, 150/256 ≈ 0.5859, 30/256 ≈ 0.1172
            temp_sum = (r << 6) + (r << 3) + (r << 2);  // 76*R = 64*R + 8*R + 4*R
            temp_sum = temp_sum + (g << 7) + (g << 4) + (g << 2) + (g << 1);  // 150*G = 128*G + 16*G + 4*G + 2*G
            temp_sum = temp_sum + (b << 4) + (b << 3) + (b << 1);  // 30*B = 16*B + 8*B + 2*B
            
            rgb888_to_gray = temp_sum[10:3];  // >> 3 (8로 나누기, 256/8=32)
        end
    endfunction
    
    // 가우시안 필터는 별도 모듈에서 처리되므로 제거
    
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
    reg [2:0] init_counter;  // 초기화 카운터 (0-4)
    
    // VSYNC 상승 에지 감지
    always @(posedge clk) begin
        vsync_prev <= vsync;
    end
    
    // 캐시 시프트 및 초기화
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
    
    // 가우시안 필터링은 별도 모듈에서 처리되므로 제거
    
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
            
            // 더 엄격한 경계 조건 - 왼쪽 경계에서 노이즈 제거
            if (y_pos > 2 && x_pos > 2 && y_pos < 237 && x_pos < 317) begin
                // 정상 3x3 윈도우 영역 (원본 그레이스케일 값 사용)
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
                
            end else if (y_pos > 1 && x_pos > 1 && y_pos < 238 && x_pos < 318) begin
                // 경계 영역 - 원본 그레이스케일 값으로 단순한 차이 기반 엣지 검출
                simple_edge = (g11 > g10) ? (g11 - g10) : (g10 - g11);
                simple_edge = simple_edge + ((g11 > g01) ? (g11 - g01) : (g01 - g11));
                simple_edge = simple_edge + ((g11 > g12) ? (g11 - g12) : (g12 - g11));
                simple_edge = simple_edge + ((g11 > g21) ? (g11 - g21) : (g21 - g11));
                
                // 경계 영역에서는 더 높은 임계값 사용
                if (simple_edge > 8'd60) begin
                    sobel_value_temp <= 8'hFF;
                end else if (simple_edge > 8'd30) begin
                    sobel_value_temp <= simple_edge;
                end else begin
                    sobel_value_temp <= 8'h00;
                end
                sobel_ready <= 1'b1;
                
            end else begin
                // 가장자리 영역에서는 검은색 출력
                sobel_value_temp <= 8'h00;
                sobel_ready <= 1'b0;
            end
            
        end else begin
            sobel_ready <= 1'b0;
        end
    end
    
    // 출력 처리 - 초기화 중에는 검은색 출력
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area && sobel_ready) begin
            // 더 강한 엣지 강화 - 노이즈 제거
            if (sobel_value_temp == 8'hFF) begin
                sobel_value <= 8'hFF;
            end else if (sobel_value_temp > 8'd180) begin
                sobel_value <= 8'hFF;
            end else if (sobel_value_temp > 8'd120) begin
                sobel_value <= sobel_value_temp + 8'd30;  // 더 강한 강화
            end else if (sobel_value_temp > 8'd80) begin
                sobel_value <= sobel_value_temp + 8'd20;
            end else begin
                sobel_value <= 8'h00;  // 낮은 값은 완전히 제거
            end
        end else if (!reset_done || !valid_addr || !active_area) begin
            // 초기화 중이거나 유효하지 않은 영역에서는 검은색 출력
            sobel_value <= 8'h00;
        end else begin
            sobel_value <= 8'h00;
        end
    end

endmodule
