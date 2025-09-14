// 고급 디지털 필터 모듈 - 노이즈 제거 및 화질 개선
module advanced_filters (
    input  wire        clk,           // 25MHz VGA 클럭
    input  wire        enable,        // 필터 활성화 신호
    input  wire [11:0] pixel_in,      // 입력 픽셀 (RGB 4:4:4)
    input  wire [16:0] pixel_addr,    // 픽셀 주소
    input  wire        vsync,         // 수직 동기화
    input  wire [1:0]  filter_mode,   // 필터 모드 선택
    output reg  [11:0] pixel_out,     // 출력 픽셀 (필터 적용 후)
    output reg         filter_ready   // 필터 처리 완료 신호
);

    // 필터 모드 정의
    parameter MODE_NONE = 2'b00;           // 필터 없음
    parameter MODE_MEDIAN = 2'b01;         // 미디언 필터 (노이즈 제거)
    parameter MODE_BILATERAL = 2'b10;      // 바이래터럴 필터 (엣지 보존 블러)
    parameter MODE_UNSHARP_MASK = 2'b11;   // 언샤프 마스킹 (선명도 향상)

    // 3x3 윈도우를 위한 라인 버퍼들
    reg [11:0] line_buffer_0 [319:0];  // 이전 라인
    reg [11:0] line_buffer_1 [319:0];  // 현재 라인
    reg [11:0] line_buffer_2 [319:0];  // 다음 라인
    
    // 픽셀 위치 계산
    wire [8:0] x_pos = pixel_addr[8:0];   // X 좌표 (0-319)
    wire [8:0] y_pos = pixel_addr[16:9];  // Y 좌표 (0-239)
    
    // 주소 유효성 검사
    wire valid_addr = (x_pos < 320) && (y_pos < 240);
    
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
    reg [11:0] filtered_pixel;
    reg [3:0] filtered_r, filtered_g, filtered_b;
    
    // 미디언 필터 (노이즈 제거)
    function [3:0] median_3x3;
        input [3:0] val0, val1, val2, val3, val4, val5, val6, val7, val8;
        reg [3:0] temp [8:0];
        reg [3:0] sorted [8:0];
        integer i, j;
        begin
            // 입력값을 배열에 저장
            temp[0] = val0; temp[1] = val1; temp[2] = val2;
            temp[3] = val3; temp[4] = val4; temp[5] = val5;
            temp[6] = val6; temp[7] = val7; temp[8] = val8;
            
            // 간단한 버블 정렬 (중간값은 4번째)
            for (i = 0; i < 9; i = i + 1) begin
                for (j = 0; j < 8-i; j = j + 1) begin
                    if (temp[j] > temp[j+1]) begin
                        temp[j] = temp[j+1];
                        temp[j+1] = temp[j];
                    end
                end
            end
            
            median_3x3 = temp[4]; // 중간값 반환
        end
    endfunction
    
    // 바이래터럴 필터 (엣지 보존 블러)
    function [3:0] bilateral_filter;
        input [3:0] center_val;
        input [3:0] neighbor_val;
        input [3:0] weight;
        begin
            // 간단한 가중 평균 (실제로는 더 복잡한 계산 필요)
            bilateral_filter = (center_val + neighbor_val) >> 1;
        end
    endfunction
    
    // 언샤프 마스킹 (선명도 향상)
    function [3:0] unsharp_mask;
        input [3:0] original;
        input [3:0] blurred;
        input [3:0] amount; // 강도 조절
        reg [5:0] sharpened;
        begin
            // 언샤프 마스킹: 원본 + (원본 - 블러) * 강도
            sharpened = original + ((original - blurred) * amount) >> 2;
            unsharp_mask = (sharpened > 15) ? 4'hF : sharpened[3:0];
        end
    endfunction
    
    // 필터 처리
    always @(posedge clk) begin
        if (enable && valid_addr && y_pos >= 2) begin
            case (filter_mode)
                MODE_MEDIAN: begin
                    // 미디언 필터 적용 (노이즈 제거)
                    filtered_r <= median_3x3(r00, r01, r02, r10, r11, r12, r20, r21, r22);
                    filtered_g <= median_3x3(g00, g01, g02, g10, g11, g12, g20, g21, g22);
                    filtered_b <= median_3x3(b00, b01, b02, b10, b11, b12, b20, b21, b22);
                end
                
                MODE_BILATERAL: begin
                    // 바이래터럴 필터 적용 (엣지 보존 블러)
                    filtered_r <= bilateral_filter(r11, (r00+r01+r02+r10+r12+r20+r21+r22)>>3, 4'h8);
                    filtered_g <= bilateral_filter(g11, (g00+g01+g02+g10+g12+g20+g21+g22)>>3, 4'h8);
                    filtered_b <= bilateral_filter(b11, (b00+b01+b02+b10+b12+b20+b21+b22)>>3, 4'h8);
                end
                
                MODE_UNSHARP_MASK: begin
                    // 언샤프 마스킹 적용 (선명도 향상)
                    filtered_r <= unsharp_mask(r11, (r00+r01+r02+r10+r12+r20+r21+r22)>>3, 4'h4);
                    filtered_g <= unsharp_mask(g11, (g00+g01+g02+g10+g12+g20+g21+g22)>>3, 4'h4);
                    filtered_b <= unsharp_mask(b11, (b00+b01+b02+b10+b12+b20+b21+b22)>>3, 4'h4);
                end
                
                default: begin
                    // 필터 없음
                    filtered_r <= r11;
                    filtered_g <= g11;
                    filtered_b <= b11;
                end
            endcase
            
            filtered_pixel <= {filtered_r, filtered_g, filtered_b};
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
    
    // 출력 제어
    always @(posedge clk) begin
        if (enable && valid_addr && y_pos >= 2) begin
            pixel_out <= filtered_pixel;
            filter_ready <= 1'b1;
        end else begin
            pixel_out <= pixel_in;
            filter_ready <= 1'b0;
        end
    end
    

endmodule
