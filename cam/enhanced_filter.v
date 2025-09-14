// 향상된 디지털 필터 모듈 - 실시간 화질 개선 및 노이즈 제거
module enhanced_filter (
    input  wire        clk,           // 25MHz VGA 클럭
    input  wire        enable,        // 필터 활성화 신호
    input  wire [11:0] pixel_in,      // 입력 픽셀 (RGB 4:4:4)
    input  wire [16:0] pixel_addr,    // 픽셀 주소
    input  wire        vsync,         // 수직 동기화
    output reg  [11:0] pixel_out,     // 출력 픽셀 (필터 적용 후)
    output reg         filter_ready   // 필터 처리 완료 신호
);

    // 픽셀 위치 계산
    wire [8:0] x_pos = pixel_addr[8:0];   // X 좌표 (0-319)
    wire [8:0] y_pos = pixel_addr[16:9];  // Y 좌표 (0-239)
    
    // 주소 유효성 검사
    wire valid_addr = (x_pos < 320) && (y_pos < 240);
    
    // 3줄 지연을 위한 라인 버퍼들
    reg [11:0] line_buffer_0 [319:0];  // 이전 라인
    reg [11:0] line_buffer_1 [319:0];  // 현재 라인
    reg [11:0] line_buffer_2 [319:0];  // 다음 라인
    
    // 3x3 윈도우 픽셀들
    wire [11:0] p00, p01, p02;  // 상단 라인
    wire [11:0] p10, p11, p12;  // 중간 라인
    wire [11:0] p20, p21, p22;  // 하단 라인
    
    // 3x3 윈도우 픽셀 할당
    assign p00 = (y_pos > 0 && x_pos > 0) ? line_buffer_0[x_pos-1] : 12'h000;
    assign p01 = (y_pos > 0) ? line_buffer_0[x_pos] : 12'h000;
    assign p02 = (y_pos > 0 && x_pos < 319) ? line_buffer_0[x_pos+1] : 12'h000;
    
    assign p10 = (x_pos > 0) ? line_buffer_1[x_pos-1] : 12'h000;
    assign p11 = line_buffer_1[x_pos];
    assign p12 = (x_pos < 319) ? line_buffer_1[x_pos+1] : 12'h000;
    
    assign p20 = (y_pos < 239 && x_pos > 0) ? line_buffer_2[x_pos-1] : 12'h000;
    assign p21 = (y_pos < 239) ? line_buffer_2[x_pos] : 12'h000;
    assign p22 = (y_pos < 239 && x_pos < 319) ? line_buffer_2[x_pos+1] : 12'h000;
    
    // RGB 분리
    wire [3:0] r00, g00, b00, r01, g01, b01, r02, g02, b02;
    wire [3:0] r10, g10, b10, r11, g11, b11, r12, g12, b12;
    wire [3:0] r20, g20, b20, r21, g21, b21, r22, g22, b22;
    
    // RGB 분리 (4:4:4 포맷)
    assign {r00, g00, b00} = p00;
    assign {r01, g01, b01} = p01;
    assign {r02, g02, b02} = p02;
    assign {r10, g10, b10} = p10;
    assign {r11, g11, b11} = p11;
    assign {r12, g12, b12} = p12;
    assign {r20, g20, b20} = p20;
    assign {r21, g21, b21} = p21;
    assign {r22, g22, b22} = p22;
    
    // 필터 처리 결과
    reg [3:0] filtered_r, filtered_g, filtered_b;
    reg [5:0] temp_r, temp_g, temp_b;
    reg [4:0] sharp_r, sharp_g, sharp_b;
    
    // 가우시안 블러 + 샤프닝 조합 필터
    always @(posedge clk) begin
        if (enable && valid_addr && y_pos >= 2) begin
            // 가우시안 블러 (3x3 커널)
            // 1 2 1
            // 2 4 2  / 16
            // 1 2 1
            temp_r <= (r00 + 2*r01 + r02 + 2*r10 + 4*r11 + 2*r12 + r20 + 2*r21 + r22) >> 4;
            temp_g <= (g00 + 2*g01 + g02 + 2*g10 + 4*g11 + 2*g12 + g20 + 2*g21 + g22) >> 4;
            temp_b <= (b00 + 2*b01 + b02 + 2*b10 + 4*b11 + 2*b12 + b20 + 2*b21 + b22) >> 4;
            
            // 샤프닝 효과 추가 (원본과 블러의 차이를 일부 추가)
            sharp_r <= temp_r[3:0] + ((r11 - temp_r[3:0]) >> 2);
            sharp_g <= temp_g[3:0] + ((g11 - temp_g[3:0]) >> 2);
            sharp_b <= temp_b[3:0] + ((b11 - temp_b[3:0]) >> 2);
            
            // 클램핑 (0-15 범위)
            filtered_r <= (sharp_r > 15) ? 4'hF : sharp_r[3:0];
            filtered_g <= (sharp_g > 15) ? 4'hF : sharp_g[3:0];
            filtered_b <= (sharp_b > 15) ? 4'hF : sharp_b[3:0];
            
            pixel_out <= {filtered_r, filtered_g, filtered_b};
            filter_ready <= 1'b1;
        end else begin
            pixel_out <= pixel_in;
            filter_ready <= 1'b0;
        end
    end
    
    // 라인 버퍼 업데이트 및 리셋
    reg [8:0] reset_counter;
    reg reset_done;
    reg vsync_prev;
    
    always @(posedge clk) begin
        // VSYNC 상승 에지 감지
        vsync_prev <= vsync;
        
        if (vsync && !vsync_prev) begin
            // VSYNC 상승 에지에서 리셋 시작
            reset_counter <= 9'd0;
            reset_done <= 1'b0;
        end else if (!reset_done) begin
            // VSYNC 리셋 중
            if (reset_counter < 320) begin
                line_buffer_0[reset_counter] <= 12'h000;
                line_buffer_1[reset_counter] <= 12'h000;
                line_buffer_2[reset_counter] <= 12'h000;
                reset_counter <= reset_counter + 1'b1;
            end else begin
                reset_done <= 1'b1;
            end
        end else if (valid_addr) begin
            // 정상 라인 버퍼 업데이트
            if (y_pos == 0) begin
                line_buffer_0[x_pos] <= 12'h000;
                line_buffer_1[x_pos] <= pixel_in;
                line_buffer_2[x_pos] <= 12'h000;
            end else if (y_pos == 1) begin
                line_buffer_0[x_pos] <= 12'h000;
                line_buffer_1[x_pos] <= line_buffer_1[x_pos];
                line_buffer_2[x_pos] <= pixel_in;
            end else begin
                line_buffer_0[x_pos] <= line_buffer_1[x_pos];
                line_buffer_1[x_pos] <= line_buffer_2[x_pos];
                line_buffer_2[x_pos] <= pixel_in;
            end
        end
    end

endmodule
