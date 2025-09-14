// 디지털 필터 처리 모듈 - 화질 개선을 위한 다양한 필터 적용
module digital_filter (
    input  wire        clk,           // 25MHz VGA 클럭
    input  wire        enable,        // 필터 활성화 신호
    input  wire [11:0] pixel_in,      // 입력 픽셀 (RGB 4:4:4)
    input  wire [16:0] pixel_addr,    // 픽셀 주소
    input  wire        vsync,         // 수직 동기화
    input  wire        active_area,   // 활성 영역 신호
    output reg  [11:0] pixel_out,     // 출력 픽셀 (필터 적용 후)
    output reg         filter_ready   // 필터 처리 완료 신호
);

    // 필터 타입 정의
    parameter FILTER_NONE = 2'b00;      // 필터 없음
    parameter FILTER_GAUSSIAN = 2'b01;  // 가우시안 블러
    parameter FILTER_SHARPEN = 2'b10;   // 샤프닝 필터
    parameter FILTER_EDGE_ENHANCE = 2'b11; // 엣지 강화
    
    // 필터 상태 관리
    reg [1:0] filter_state = FILTER_NONE;
    reg [2:0] delay_counter = 3'b000;  // 필터 지연 카운터

    // 라인 버퍼들 (1줄 버퍼링 - 간단한 필터용)
    reg [11:0] line_buffer [319:0];  // 이전 라인
    
    // 픽셀 위치 계산
    wire [8:0] x_pos = pixel_addr[8:0];   // X 좌표 (0-319)
    wire [8:0] y_pos = pixel_addr[16:9];  // Y 좌표 (0-239)
    
    // 주소 유효성 검사
    wire valid_addr = (x_pos < 320) && (y_pos < 240);
    
    // 1x3 윈도우 픽셀들 (현재, 이전, 다음)
    wire [11:0] p_prev, p_curr, p_next;
    
    // 1x3 윈도우 픽셀 할당
    assign p_prev = (x_pos > 0) ? line_buffer[x_pos-1] : 12'h000;
    assign p_curr = pixel_in;
    assign p_next = (x_pos < 319) ? line_buffer[x_pos+1] : 12'h000;
    
    // RGB 분리
    wire [3:0] r_prev, g_prev, b_prev;
    wire [3:0] r_curr, g_curr, b_curr;
    wire [3:0] r_next, g_next, b_next;
    
    // RGB 분리 (4:4:4 포맷)
    assign {r_prev, g_prev, b_prev} = p_prev;
    assign {r_curr, g_curr, b_curr} = p_curr;
    assign {r_next, g_next, b_next} = p_next;
    
    // 필터 처리
    reg [11:0] filtered_pixel;
    reg [7:0] filter_r, filter_g, filter_b;
    
    always @(posedge clk) begin
        if (enable && valid_addr && active_area) begin
            // 매우 간단한 노이즈 제거 필터
            // 현재 픽셀과 이전 픽셀의 평균 (50% + 50%)
            filter_r <= (r_curr + r_prev) >> 1;
            filter_g <= (g_curr + g_prev) >> 1;
            filter_b <= (b_curr + b_prev) >> 1;
            
            // 간단한 필터 적용
            filtered_pixel <= {filter_r[3:0], filter_g[3:0], filter_b[3:0]};
        end else begin
            filtered_pixel <= pixel_in;
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
                line_buffer[reset_counter] <= 12'h000;
                reset_counter <= reset_counter + 1'b1;
            end else begin
                reset_done <= 1'b1;
            end
        end else if (valid_addr && active_area) begin
            // 활성 영역에서만 라인 버퍼 업데이트 - 1줄만 사용
            line_buffer[x_pos] <= pixel_in;
        end
    end
    
    // 필터 상태 관리 (간단한 노이즈 제거만 사용)
    always @(posedge clk) begin
        if (enable) begin
            filter_state <= FILTER_GAUSSIAN;  // 간단한 노이즈 제거 필터
        end else begin
            filter_state <= FILTER_NONE;
        end
    end
    
    // 출력 제어
    always @(posedge clk) begin
        if (enable && valid_addr && active_area) begin
            // 활성 영역에서만 필터 적용된 픽셀 출력
            pixel_out <= filtered_pixel;
            filter_ready <= 1'b1;
        end else begin
            // 비활성 영역에서는 원본 픽셀 출력
            pixel_out <= pixel_in;
            filter_ready <= 1'b0;
        end
    end
    

endmodule

// 샤프닝 필터 모듈 (선택적 사용)
module sharpen_filter (
    input  wire        clk,
    input  wire        enable,
    input  wire [11:0] pixel_in,
    input  wire [16:0] pixel_addr,
    output reg  [11:0] pixel_out
);

    // 샤프닝 커널
    //  0 -1  0
    // -1  5 -1
    //  0 -1  0
    
    // 구현은 가우시안 필터와 유사하지만 다른 계수 사용
    // 실제 구현에서는 라인 버퍼와 3x3 윈도우가 필요
    
    always @(posedge clk) begin
        if (enable) begin
            // 샤프닝 필터 적용
            pixel_out <= pixel_in; // 임시로 원본 반환
        end else begin
            pixel_out <= pixel_in;
        end
    end

endmodule
