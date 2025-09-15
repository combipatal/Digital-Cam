// RGB888용 간단한 노이즈 제거 필터 모듈
module simple_noise_filter_rgb888 (
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
    wire [8:0] x_pos = pixel_addr[8:0];   // X 좌표 (0-319)
    wire [8:0] y_pos = pixel_addr[16:9];  // Y 좌표 (0-239)
    
    // 주소 유효성 검사
    wire valid_addr = (x_pos < 320) && (y_pos < 240);
    
    // 1줄 라인 버퍼 (이전 픽셀 저장)
    reg [23:0] line_buffer [319:0];
    
    // 이전 픽셀
    wire [23:0] prev_pixel = (x_pos > 0) ? line_buffer[x_pos-1] : 24'h000000;
    
    // RGB888 분리
    wire [7:0] r_curr, g_curr, b_curr;
    wire [7:0] r_prev, g_prev, b_prev;
    
    assign {r_curr, g_curr, b_curr} = pixel_in;
    assign {r_prev, g_prev, b_prev} = prev_pixel;
    
    // 필터 처리 결과
    reg [7:0] filtered_r, filtered_g, filtered_b;
    
    // 간단한 노이즈 제거 필터 (현재 + 이전) / 2
    always @(posedge clk) begin
        if (enable && valid_addr && active_area) begin
            // 현재 픽셀과 이전 픽셀의 평균
            filtered_r <= (r_curr + r_prev) >> 1;
            filtered_g <= (g_curr + g_prev) >> 1;
            filtered_b <= (b_curr + b_prev) >> 1;
            
            pixel_out <= {filtered_r, filtered_g, filtered_b};
            filter_ready <= 1'b1;
        end else begin
            pixel_out <= pixel_in;
            filter_ready <= 1'b0;
        end
    end
    
    // 라인 버퍼 업데이트 및 리셋 (통합)
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
                line_buffer[reset_counter] <= 24'h000000;
                reset_counter <= reset_counter + 1'b1;
            end else begin
                reset_done <= 1'b1;
            end
        end else if (valid_addr && active_area) begin
            // 활성 영역에서만 라인 버퍼 업데이트
            line_buffer[x_pos] <= pixel_in;
        end
    end

endmodule
