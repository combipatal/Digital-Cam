// 파이프라인 기반 소벨 필터 (ps_sobel.v 참고)
// 4단계 파이프라인으로 고속 처리
module sobel_pipeline (
    input  wire        clk,           // 25MHz VGA 클럭
    input  wire        rst_n,         // 리셋 (액티브 로우)
    input  wire        enable,        // 필터 활성화 신호
    input  wire [11:0] pixel_in,      // 입력 픽셀 (RGB 4:4:4)
    input  wire [16:0] pixel_addr,    // 픽셀 주소
    input  wire        vsync,         // 수직 동기화
    input  wire        active_area,   // 활성 영역 신호
    input  wire [10:0] threshold,     // 임계값 (외부에서 조정 가능)
    output reg  [7:0]  sobel_value,   // 소벨 필터 값 (0-255)
    output reg         sobel_ready    // 필터 처리 완료 신호
);

    // 픽셀 위치 계산
    wire [8:0] x_pos = pixel_addr[8:0];   // X 좌표 (0-319)
    wire [8:0] y_pos = pixel_addr[16:9];  // Y 좌표 (0-239)
    
    // 주소 유효성 검사
    wire valid_addr = (x_pos < 320) && (y_pos < 240);
    
    // 3x3 윈도우 메모리 (ps_sobel.v 방식)
    reg [7:0] window_mem [8:0];  // 3x3 윈도우 저장
    reg [7:0] window_data [8:0]; // 현재 윈도우 데이터
    
    // 그레이스케일 변환 (ps_sobel.v 방식)
    wire [7:0] gray_pixel;
    assign gray_pixel = (pixel_in[11:8] + pixel_in[7:4] + pixel_in[3:0]) / 3;
    
    // 소벨 커널 정의 (ps_sobel.v와 동일)
    reg [7:0] kernelX [8:0];
    reg [7:0] kernelY [8:0];
    
    // 커널 초기화
    initial begin
        // X 방향 커널
        kernelX[0] =  1; kernelX[1] =  0; kernelX[2] = -1;
        kernelX[3] =  2; kernelX[4] =  0; kernelX[5] = -2;
        kernelX[6] =  1; kernelX[7] =  0; kernelX[8] = -1;
        
        // Y 방향 커널
        kernelY[0] =  1; kernelY[1] =  2; kernelY[2] =  1;
        kernelY[3] =  0; kernelY[4] =  0; kernelY[5] =  0;
        kernelY[6] = -1; kernelY[7] = -2; kernelY[8] = -1;
    end
    
    // 파이프라인 스테이지 1: 3x3 윈도우 구성
    reg [2:0] stage1_valid;
    reg [7:0] stage1_window [8:0];
    
    // 파이프라인 스테이지 2: 커널 곱셈
    reg [2:0] stage2_valid;
    reg [15:0] stage2_multX [8:0];
    reg [15:0] stage2_multY [8:0];
    
    // 파이프라인 스테이지 3: 합계 계산
    reg [2:0] stage3_valid;
    reg [15:0] stage3_sumX, stage3_sumY;
    
    // 파이프라인 스테이지 4: 최종 계산
    reg [2:0] stage4_valid;
    reg [15:0] stage4_gx, stage4_gy;
    reg [15:0] stage4_magnitude;
    
    // VSYNC 리셋 제어
    reg vsync_prev;
    reg reset_done;
    
    // VSYNC 상승 에지 감지
    always @(posedge clk) begin
        vsync_prev <= vsync;
    end
    
    // 리셋 처리 (별도 블록)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_done <= 1'b0;
        end else if (vsync && !vsync_prev) begin
            reset_done <= 1'b0;
        end else if (valid_addr && active_area) begin
            reset_done <= 1'b1;
        end
    end
    
    // 스테이지 1: 3x3 윈도우 구성 (별도 블록)
    always @(posedge clk) begin
        if (enable && reset_done && valid_addr && active_area) begin
            // 윈도우 시프트
            stage1_window[0] <= stage1_window[1];
            stage1_window[1] <= stage1_window[2];
            stage1_window[2] <= stage1_window[3];
            stage1_window[3] <= stage1_window[4];
            stage1_window[4] <= stage1_window[5];
            stage1_window[5] <= stage1_window[6];
            stage1_window[6] <= stage1_window[7];
            stage1_window[7] <= stage1_window[8];
            stage1_window[8] <= gray_pixel;
            
            stage1_valid <= {stage1_valid[1:0], 1'b1};
        end else begin
            stage1_valid <= {stage1_valid[1:0], 1'b0};
        end
    end
    
    // 스테이지 2: 커널 곱셈 (별도 블록)
    integer i;
    always @(posedge clk) begin
        if (stage1_valid[2]) begin
            for (i = 0; i < 9; i = i + 1) begin
                stage2_multX[i] <= $signed(kernelX[i]) * $signed({1'b0, stage1_window[i]});
                stage2_multY[i] <= $signed(kernelY[i]) * $signed({1'b0, stage1_window[i]});
            end
            stage2_valid <= {stage2_valid[1:0], 1'b1};
        end else begin
            stage2_valid <= {stage2_valid[1:0], 1'b0};
        end
    end
    
    // 스테이지 3: 합계 계산 (별도 블록)
    always @(posedge clk) begin
        if (stage2_valid[2]) begin
            stage3_sumX <= 0;
            stage3_sumY <= 0;
            
            for (i = 0; i < 9; i = i + 1) begin
                stage3_sumX <= stage3_sumX + $signed(stage2_multX[i]);
                stage3_sumY <= stage3_sumY + $signed(stage2_multY[i]);
            end
            
            stage3_valid <= {stage3_valid[1:0], 1'b1};
        end else begin
            stage3_valid <= {stage3_valid[1:0], 1'b0};
        end
    end
    
    // 스테이지 4: 최종 계산 (별도 블록)
    always @(posedge clk) begin
        if (stage3_valid[2]) begin
            // 절댓값 계산
            stage4_gx <= stage3_sumX[15] ? (~stage3_sumX + 1) : stage3_sumX;
            stage4_gy <= stage3_sumY[15] ? (~stage3_sumY + 1) : stage3_sumY;
            
            // 소벨 강도 계산: |Gx| + |Gy|
            stage4_magnitude <= stage4_gx + stage4_gy;
            
            stage4_valid <= {stage4_valid[1:0], 1'b1};
        end else begin
            stage4_valid <= {stage4_valid[1:0], 1'b0};
        end
    end
    
    // 최종 출력 (별도 블록)
    always @(posedge clk) begin
        if (stage4_valid[2]) begin
            // 임계값 기반 이진화 (ps_sobel.v 방식)
            if (stage4_magnitude > threshold) begin
                sobel_value <= 8'hFF;  // 강한 엣지: 완전 흰색
            end else begin
                sobel_value <= 8'h00;  // 약한 엣지: 완전 검은색
            end
            sobel_ready <= 1'b1;
        end else begin
            sobel_value <= 8'h00;
            sobel_ready <= 1'b0;
        end
    end

endmodule
