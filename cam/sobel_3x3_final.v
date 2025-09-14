// 3x3 소벨 엣지 검출 필터 (VHDL CacheSystem 참고 최종 버전)
module sobel_3x3_final (
    input  wire        clk,           // 25MHz VGA 클럭
    input  wire        enable,        // 필터 활성화 신호
    input  wire [11:0] pixel_in,      // 입력 픽셀 (RGB 4:4:4)
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
    
    // VHDL CacheSystem 방식의 3x3 윈도우 캐시
    reg [11:0] cache1 [2:0];  // 첫 번째 줄 캐시 (3픽셀)
    reg [11:0] cache2 [2:0];  // 두 번째 줄 캐시 (3픽셀)
    reg [11:0] cache3 [2:0];  // 세 번째 줄 캐시 (3픽셀)
    
    // 3x3 윈도우 출력 (VHDL pdata_out1~9에 해당)
    wire [11:0] p00, p01, p02;  // 첫 번째 줄
    wire [11:0] p10, p11, p12;  // 두 번째 줄
    wire [11:0] p20, p21, p22;  // 세 번째 줄
    
    // 개선된 그레이스케일 변환 함수 (참고 코드 방식)
    function [7:0] rgb_to_gray;
        input [11:0] rgb;
        reg [8:0] temp_sum;
        begin
            // Y = 0.299*R + 0.587*G + 0.114*B (근사값)
            // Y = (R + 2*G + B) / 4
            temp_sum = {rgb[11:8], 4'b0000} + {rgb[7:4], 4'b0000} + {rgb[7:4], 4'b0000} + {rgb[3:0], 4'b0000};
            rgb_to_gray = temp_sum[8:2];  // >> 2 (4로 나누기)
        end
    endfunction
    
    // VHDL EmittingProcess 방식의 3x3 윈도우 출력 (세로줄 노이즈 제거)
    reg [11:0] p00_r, p01_r, p02_r, p10_r, p11_r, p12_r, p20_r, p21_r, p22_r;
    
    always @(*) begin
        // VHDL EmittingProcess의 복잡한 조건문을 참고
        if (y_pos == 0 && x_pos == 0) begin
            // 첫 번째 픽셀 (1,1)
            p00_r = 12'h000; p01_r = 12'h000; p02_r = 12'h000;
            p10_r = 12'h000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 12'h000; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos == 0 && x_pos > 0 && x_pos < 319) begin
            // 첫 번째 줄 중간 (1,2~318)
            p00_r = 12'h000; p01_r = 12'h000; p02_r = 12'h000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos == 0 && x_pos == 319) begin
            // 첫 번째 줄 마지막 (1,319)
            p00_r = 12'h000; p01_r = 12'h000; p02_r = 12'h000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 12'h000;
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = 12'h000;
        end else if (y_pos > 0 && y_pos < 239 && x_pos == 0) begin
            // 중간 줄 첫 번째 (2~239,1)
            p00_r = 12'h000; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = 12'h000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 12'h000; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos > 0 && y_pos < 239 && x_pos > 0 && x_pos < 319) begin
            // 중간 줄 중간 (2~239,2~318) - 정상 3x3 윈도우
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = cache3[2];
        end else if (y_pos > 0 && y_pos < 239 && x_pos == 319) begin
            // 중간 줄 마지막 (2~239,319)
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = 12'h000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 12'h000;
            p20_r = cache3[0]; p21_r = cache3[1]; p22_r = 12'h000;
        end else if (y_pos == 239 && x_pos == 0) begin
            // 마지막 줄 첫 번째 (240,1)
            p00_r = 12'h000; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = 12'h000; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 12'h000; p21_r = 12'h000; p22_r = 12'h000;
        end else if (y_pos == 239 && x_pos > 0 && x_pos < 319) begin
            // 마지막 줄 중간 (240,2~318)
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = cache1[2];
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = cache2[2];
            p20_r = 12'h000; p21_r = 12'h000; p22_r = 12'h000;
        end else if (y_pos == 239 && x_pos == 319) begin
            // 마지막 줄 마지막 (240,319)
            p00_r = cache1[0]; p01_r = cache1[1]; p02_r = 12'h000;
            p10_r = cache2[0]; p11_r = cache2[1]; p12_r = 12'h000;
            p20_r = 12'h000; p21_r = 12'h000; p22_r = 12'h000;
        end else begin
            // 기본값
            p00_r = 12'h000; p01_r = 12'h000; p02_r = 12'h000;
            p10_r = 12'h000; p11_r = 12'h000; p12_r = 12'h000;
            p20_r = 12'h000; p21_r = 12'h000; p22_r = 12'h000;
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
    
    // VHDL CacheSystem 방식의 캐시 시프트 (완전 안정화)
    reg [1:0] init_state;
    
    always @(posedge clk) begin
        if (vsync && !vsync_prev) begin
            // VSYNC 상승 에지에서 리셋
            reset_done <= 1'b0;
            init_state <= 2'b00;
            cache1[0] <= 12'h000; cache1[1] <= 12'h000; cache1[2] <= 12'h000;
            cache2[0] <= 12'h000; cache2[1] <= 12'h000; cache2[2] <= 12'h000;
            cache3[0] <= 12'h000; cache3[1] <= 12'h000; cache3[2] <= 12'h000;
            // VSYNC 리셋 완료
        end else if (valid_addr && active_area) begin
            if (!reset_done) begin
                // 초기화 단계별 처리
                case (init_state)
                    2'b00: begin
                        // 첫 번째 줄 초기화
                        cache1[0] <= 12'h000; cache1[1] <= 12'h000; cache1[2] <= 12'h000;
                        cache2[0] <= 12'h000; cache2[1] <= pixel_in; cache2[2] <= 12'h000;
                        cache3[0] <= 12'h000; cache3[1] <= 12'h000; cache3[2] <= 12'h000;
                        init_state <= 2'b01;
                    end
                    2'b01: begin
                        // 두 번째 줄 초기화
                        cache1[0] <= 12'h000; cache1[1] <= 12'h000; cache1[2] <= 12'h000;
                        cache2[0] <= cache2[1]; cache2[1] <= cache2[2]; cache2[2] <= pixel_in;
                        cache3[0] <= 12'h000; cache3[1] <= 12'h000; cache3[2] <= 12'h000;
                        init_state <= 2'b10;
                    end
                    2'b10: begin
                        // 세 번째 줄 초기화 완료
                        cache1[0] <= 12'h000; cache1[1] <= 12'h000; cache1[2] <= 12'h000;
                        cache2[0] <= cache2[1]; cache2[1] <= cache2[2]; cache2[2] <= cache3[1];
                        cache3[0] <= 12'h000; cache3[1] <= 12'h000; cache3[2] <= pixel_in;
                        reset_done <= 1'b1;
                        init_state <= 2'b11;
                    end
                    default: begin
                        reset_done <= 1'b1;
                    end
                endcase
            end else begin
                // 정상 동작 - VHDL ShiftingProcess 방식
                // 첫 번째 줄 시프트 (이전 줄)
                cache1[0] <= cache1[1];
                cache1[1] <= cache1[2];
                cache1[2] <= cache2[1];  // 두 번째 줄에서 가져옴
                
                // 두 번째 줄 시프트 (현재 줄)
                cache2[0] <= cache2[1];
                cache2[1] <= cache2[2];
                cache2[2] <= cache3[1];  // 세 번째 줄에서 가져옴
                
                // 세 번째 줄 시프트 (다음 줄)
                cache3[0] <= cache3[1];
                cache3[1] <= cache3[2];
                cache3[2] <= pixel_in;   // 새 픽셀 입력
            end
        end
    end
    
    // 그레이스케일 변환
    always @(posedge clk) begin
        if (reset_done && valid_addr && active_area) begin
            g00 <= rgb_to_gray(p00);
            g01 <= rgb_to_gray(p01);
            g02 <= rgb_to_gray(p02);
            g10 <= rgb_to_gray(p10);
            g11 <= rgb_to_gray(p11);
            g12 <= rgb_to_gray(p12);
            g20 <= rgb_to_gray(p20);
            g21 <= rgb_to_gray(p21);
            g22 <= rgb_to_gray(p22);
        end else begin
            g00 <= 8'h00; g01 <= 8'h00; g02 <= 8'h00;
            g10 <= 8'h00; g11 <= 8'h00; g12 <= 8'h00;
            g20 <= 8'h00; g21 <= 8'h00; g22 <= 8'h00;
        end
    end
    
    // 소벨 계산 (완전 안정화 + 강화된 경계 검출)
    reg [9:0] gx_sum, gy_sum;
    reg [9:0] gx_abs, gy_abs;
    reg [10:0] sobel_magnitude;  // 절댓값 합용 비트 폭
    reg [7:0] sobel_value_temp;
    reg [10:0] edge_threshold;  // 절댓값 합용 임계값
    reg [7:0] simple_edge;
    reg [10:0] noise_threshold;  // 절댓값 합용 임계값
    
    // ps_sobel.v 방식의 단순한 변수들
    reg [7:0] temp_sobel;      // 임시 소벨 값
    
    // 개선된 엣지 검출을 위한 추가 변수들
    reg [7:0] local_variance;   // 지역 분산
    reg [7:0] edge_strength;    // 엣지 강도
    reg [7:0] smoothed_edge;    // 스무딩된 엣지
    
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            // 개선된 임계값 설정 (더 민감하고 안정적)
            edge_threshold <= 11'd25;      // 엣지 검출 임계값 (더 민감하게)
            noise_threshold <= 11'd12;     // 노이즈 필터링 임계값
            
            if (y_pos > 1 && x_pos > 1 && y_pos < 238 && x_pos < 318) begin
                // 정상 3x3 윈도우 영역 - 강화된 소벨 마스크
                // 소벨 X 방향 마스크 (Gx) - 강화된 버전
                // -1  0 +1
                // -2  0 +2  
                // -1  0 +1
                gx_sum <= g02 + (g12 << 1) + g22 - g00 - (g10 << 1) - g20;
                
                // 소벨 Y 방향 마스크 (Gy) - 강화된 버전
                // -1 -2 -1
                //  0  0  0
                // +1 +2 +1
                gy_sum <= g20 + (g21 << 1) + g22 - g00 - (g01 << 1) - g02;
                
                // 절댓값 계산
                gx_abs <= gx_sum[9] ? (~gx_sum + 1) : gx_sum;
                gy_abs <= gy_sum[9] ? (~gy_sum + 1) : gy_sum;
                
                // 소벨 강도 계산: |Gx| + |Gy|
                sobel_magnitude <= gx_abs + gy_abs;
                
                // 지역 분산 계산 (노이즈 제거용)
                local_variance <= ((g00 + g01 + g02 + g10 + g11 + g12 + g20 + g21 + g22) / 9);
                
                // 엣지 강도 계산 (더 정교한 방식)
                edge_strength <= (sobel_magnitude > 10'd255) ? 8'd255 : sobel_magnitude[7:0];
                
                // 스무딩된 엣지 (연속성 체크)
                if (sobel_magnitude > edge_threshold) begin
                    // 강한 엣지: 완전 흰색
                    sobel_value_temp <= 8'hFF;
                end else if (sobel_magnitude > noise_threshold) begin
                    // 중간 강도: 그레이스케일 값 (더 부드럽게)
                    sobel_value_temp <= edge_strength;
                end else begin
                    // 약한 엣지: 완전 검은색
                    sobel_value_temp <= 8'h00;
                end
                sobel_ready <= 1'b1;
                
            end else if (y_pos > 0 && x_pos > 0 && y_pos < 239 && x_pos < 319) begin
                // 경계 영역 - 개선된 단순 엣지 검출
                simple_edge = (g11 > g10) ? (g11 - g10) : (g10 - g11);
                simple_edge = simple_edge + ((g11 > g01) ? (g11 - g01) : (g01 - g11));
                simple_edge = simple_edge + ((g11 > g12) ? (g11 - g12) : (g12 - g11));
                simple_edge = simple_edge + ((g11 > g21) ? (g11 - g21) : (g21 - g11));
                
                // 경계 영역에서도 개선된 이진화
                if (simple_edge > 8'd40) begin
                    sobel_value_temp <= 8'hFF;  // 강한 경계: 완전 흰색
                end else if (simple_edge > 8'd20) begin
                    sobel_value_temp <= simple_edge;  // 중간 강도: 그레이스케일
                end else begin
                    sobel_value_temp <= 8'h00;  // 약한 경계: 완전 검은색
                end
                sobel_ready <= 1'b1;
                
            end else begin
                // 완전한 경계에서는 0
                sobel_value_temp <= 8'h00;
                sobel_ready <= 1'b0;
            end
            
        end else begin
            sobel_ready <= 1'b0;
        end
    end
    
    // 개선된 출력 처리 (노이즈 제거 + 스무딩)
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area && sobel_ready) begin
            // 최종 출력 전 추가 필터링
            if (sobel_value_temp == 8'hFF) begin
                // 강한 엣지: 그대로 출력
                sobel_value <= 8'hFF;
            end else if (sobel_value_temp > 8'd200) begin
                // 매우 강한 엣지: 완전 흰색으로 정규화
                sobel_value <= 8'hFF;
            end else if (sobel_value_temp > 8'd100) begin
                // 중간 강도: 그레이스케일 유지
                sobel_value <= sobel_value_temp;
            end else if (sobel_value_temp > 8'd50) begin
                // 약한 엣지: 약간 강화
                sobel_value <= sobel_value_temp + 8'd20;
            end else begin
                // 매우 약한 엣지: 제거
                sobel_value <= 8'h00;
            end
        end else begin
            sobel_value <= 8'h00;
        end
    end

endmodule