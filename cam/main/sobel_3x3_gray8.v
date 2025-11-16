// ============================================================================
// 3x3 Sobel 엣지 검출 필터 (8비트 그레이스케일)
// ============================================================================
// - 2개의 라인 버퍼 + 수평 3-tap 시프트 레지스터로 진짜 3x3 윈도우 구성
// - 좌측/상단 경계의 픽셀은 가장자리 값으로 클램핑하여 첫 픽셀부터 유효한 출력 생성
// - 파이프라인 지연: 총 5 클럭 (Sobel 그래디언트 계산 + 임계값 처리)
// ============================================================================
module sobel_3x3_gray8 #(
    parameter integer IMG_WIDTH  = 320,  // 이미지 가로 크기 (픽셀)
    parameter integer IMG_HEIGHT = 240   // 이미지 세로 크기 (픽셀)
)(
    input  wire        clk,           // 시스템 클럭
    input  wire        enable,        // 필터 활성화 신호
    input  wire [7:0]  pixel_in,      // 입력 픽셀 (8비트 그레이스케일)
    input  wire [16:0] pixel_addr,    // 픽셀 주소 (레거시 호환성, 사용 안 함)
    input  wire        vsync,         // 수직 동기 신호 (프레임 시작)
    input  wire        active_area,   // 활성 영역 신호 (픽셀 데이터 유효)
    input  wire [7:0]  threshold,     // 엣지 임계값 (0~255)
    output reg  [7:0]  pixel_out,     // 출력 픽셀 (0: 배경, 255: 엣지)
    output reg         sobel_ready    // 출력 데이터 유효 신호
);

    localparam integer PIPE_LAT = 5;  // Sobel 내부 파이프라인 지연 (클럭 수)

    // ============================================================================
    // 좌표 계산을 위한 비트 폭 설정
    // ============================================================================
    // active_area 신호로부터 좌표를 추출 (pixel_addr과 독립적으로 동작)
    localparam integer COL_BITS = (IMG_WIDTH  <= 256) ? 8 :
                                  (IMG_WIDTH  <= 512) ? 9 : 10;
    localparam integer ROW_BITS = (IMG_HEIGHT <= 256) ? 8 :
                                  (IMG_HEIGHT <= 512) ? 9 : 10;

    // 현재 픽셀의 좌표 (내부적으로 계산)
    reg [COL_BITS-1:0] x_coord = {COL_BITS{1'b0}};  // 현재 X 좌표
    reg [ROW_BITS-1:0] y_coord = {ROW_BITS{1'b0}};  // 현재 Y 좌표

    // ============================================================================
    // 프레임/라인 경계 검출
    // ============================================================================
    reg vsync_prev  = 1'b0;  // 이전 클럭의 vsync 신호
    reg active_prev = 1'b0;  // 이전 클럭의 active_area 신호
    
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end
    
    // 엣지 검출 신호
    wire vsync_fall  = vsync_prev & ~vsync;      // vsync 하강 엣지 (프레임 종료)
    wire active_rise = active_area & ~active_prev; // active_area 상승 엣지 (라인 시작)
    wire active_fall = ~active_area & active_prev; // active_area 하강 엣지 (라인 종료)
    wire frame_start = vsync_fall;                // 프레임 시작 신호
    wire line_start  = active_rise;               // 라인 시작 신호

    // ============================================================================
    // 좌표 카운팅
    // ============================================================================
    always @(posedge clk) begin
        if (frame_start) begin
            // 프레임 시작 시 좌표 초기화
            x_coord <= {COL_BITS{1'b0}};
            y_coord <= {ROW_BITS{1'b0}};
        end else if (enable) begin
            if (active_rise) begin
                // 라인 시작 시 X 좌표 리셋
                x_coord <= {COL_BITS{1'b0}};
            end else if (active_area) begin
                // 활성 영역에서 X 좌표 증가
                if (x_coord < IMG_WIDTH-1)
                    x_coord <= x_coord + 1'b1;
            end
            if (active_fall) begin
                // 라인 종료 시 Y 좌표 증가
                if (y_coord < IMG_HEIGHT-1)
                    y_coord <= y_coord + 1'b1;
            end
        end
    end
    
    // 현재 처리 중인 픽셀의 좌표 (다음 클럭에 사용될 값)
    wire [COL_BITS-1:0] x_curr = line_start ? {COL_BITS{1'b0}} :
                                 (active_area ? ((x_coord == IMG_WIDTH-1) ? x_coord : (x_coord + 1'b1)) : x_coord);
    wire [COL_BITS-1:0] x = x_curr;  // 현재 X 좌표
    wire [ROW_BITS-1:0] y = y_coord; // 현재 Y 좌표

    // ============================================================================
    // 좌표 및 픽셀 데이터를 Sobel 파이프라인 지연에 맞춰 정렬
    // ============================================================================
    // 5단계 파이프라인 지연을 위한 레지스터
    reg [COL_BITS-1:0] x_d1 = {COL_BITS{1'b0}}, x_d2 = {COL_BITS{1'b0}},
                         x_d3 = {COL_BITS{1'b0}}, x_d4 = {COL_BITS{1'b0}}, x_d5 = {COL_BITS{1'b0}};
    reg [ROW_BITS-1:0] y_d1 = {ROW_BITS{1'b0}}, y_d2 = {ROW_BITS{1'b0}},
                         y_d3 = {ROW_BITS{1'b0}}, y_d4 = {ROW_BITS{1'b0}}, y_d5 = {ROW_BITS{1'b0}};
    reg [7:0] pix_d1 = 8'd0, pix_d2 = 8'd0, pix_d3 = 8'd0, pix_d4 = 8'd0, pix_d5 = 8'd0;
    
    always @(posedge clk) begin
        if (enable && active_area) begin
            // 파이프라인 시프트: 좌표와 픽셀 데이터를 5 클럭 지연
            x_d1 <= x;   x_d2 <= x_d1;   x_d3 <= x_d2;   x_d4 <= x_d3;   x_d5 <= x_d4;
            y_d1 <= y;   y_d2 <= y_d1;   y_d3 <= y_d2;   y_d4 <= y_d3;   y_d5 <= y_d4;
            pix_d1 <= pixel_in; pix_d2 <= pix_d1; pix_d3 <= pix_d2; pix_d4 <= pix_d3; pix_d5 <= pix_d4;
        end else begin
            // 비활성 상태에서 모든 지연 레지스터 초기화
            x_d1 <= {COL_BITS{1'b0}}; x_d2 <= {COL_BITS{1'b0}}; x_d3 <= {COL_BITS{1'b0}};
            x_d4 <= {COL_BITS{1'b0}}; x_d5 <= {COL_BITS{1'b0}};
            y_d1 <= {ROW_BITS{1'b0}}; y_d2 <= {ROW_BITS{1'b0}}; y_d3 <= {ROW_BITS{1'b0}};
            y_d4 <= {ROW_BITS{1'b0}}; y_d5 <= {ROW_BITS{1'b0}};
            pix_d1 <= 8'd0; pix_d2 <= 8'd0; pix_d3 <= 8'd0; pix_d4 <= 8'd0; pix_d5 <= 8'd0;
        end
    end

    // ============================================================================
    // 2개의 라인 버퍼 (핑퐁 방식) + 수평 3-tap 시프트 레지스터
    // ============================================================================
    // 라인 버퍼: 이전 2개 라인의 픽셀 데이터 저장
    reg [7:0] lb0 [0:IMG_WIDTH-1];  // 라인 버퍼 0
    reg [7:0] lb1 [0:IMG_WIDTH-1];  // 라인 버퍼 1
    reg       wr_sel = 1'b0;        // 쓰기 선택 신호 (라인 시작마다 토글)

    // 수평 3-tap 시프트 레지스터: 각 라인당 3개 픽셀 저장
    reg [7:0] top_sr0, top_sr1, top_sr2; // y-2 라인 (2 라인 전)
    reg [7:0] mid_sr0, mid_sr1, mid_sr2; // y-1 라인 (1 라인 전)
    reg [7:0] cur_sr0, cur_sr1, cur_sr2; // y 라인 (현재 라인)

    // 내부 유효 신호 (이미 지연된 active_area 사용)
    wire window_valid = enable && active_area;

    // 현재 X 위치에서 라인 버퍼 읽기 (쓰기 전에 읽음)
    wire [7:0] top_in = (wr_sel == 1'b0) ? lb0[x] : lb1[x]; // y-2 라인 데이터
    wire [7:0] mid_in = (wr_sel == 1'b0) ? lb1[x] : lb0[x]; // y-1 라인 데이터

    // ============================================================================
    // 시프트 레지스터 업데이트 및 라인 버퍼 쓰기
    // ============================================================================
    always @(posedge clk) begin
        if (frame_start) begin
            // 프레임 시작 시 모든 시프트 레지스터 초기화
            wr_sel <= 1'b0;
            top_sr0 <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
            mid_sr0 <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
            cur_sr0 <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
        end else begin
            if (line_start) begin
                // 라인 시작 시 wr_sel 토글 및 시프트 레지스터 초기화
                wr_sel  <= ~wr_sel;
                top_sr0 <= 8'd0; top_sr1 <= 8'd0; top_sr2 <= 8'd0;
                mid_sr0 <= 8'd0; mid_sr1 <= 8'd0; mid_sr2 <= 8'd0;
                cur_sr0 <= 8'd0; cur_sr1 <= 8'd0; cur_sr2 <= 8'd0;
            end
            if (enable && active_area) begin
                // 시프트 레지스터 업데이트 (왼쪽으로 시프트)
                top_sr2 <= top_sr1;  top_sr1 <= top_sr0;  top_sr0 <= top_in;
                mid_sr2 <= mid_sr1;  mid_sr1 <= mid_sr0;  mid_sr0 <= mid_in;
                cur_sr2 <= cur_sr1;  cur_sr1 <= cur_sr0;  cur_sr0 <= pixel_in;
                
                // 현재 픽셀을 라인 버퍼에 쓰기
                if (wr_sel == 1'b0) lb0[x] <= pixel_in; else lb1[x] <= pixel_in;
            end
        end
    end

    // ============================================================================
    // 다음 클럭 시프트 결과로 3x3 윈도우 구성 (현재 픽셀 포함)
    // ============================================================================
    // 다음 클럭에 시프트될 값들을 미리 계산
    wire [7:0] n_top_sr0 = top_in;      // y-2 라인, x 위치
    wire [7:0] n_top_sr1 = top_sr0;     // y-2 라인, x-1 위치
    wire [7:0] n_top_sr2 = top_sr1;     // y-2 라인, x-2 위치
    wire [7:0] n_mid_sr0 = mid_in;      // y-1 라인, x 위치
    wire [7:0] n_mid_sr1 = mid_sr0;     // y-1 라인, x-1 위치
    wire [7:0] n_mid_sr2 = mid_sr1;     // y-1 라인, x-2 위치
    wire [7:0] n_cur_sr0 = pixel_in;    // y 라인, x 위치 (현재 픽셀)
    wire [7:0] n_cur_sr1 = cur_sr0;     // y 라인, x-1 위치
    wire [7:0] n_cur_sr2 = cur_sr1;     // y 라인, x-2 위치

    // 상단/좌측 2 픽셀은 경계 픽셀로 처리하여 검은색 출력
    wire border_pixel = (x_d5 < 2) || (y_d5 < 2);

    // ============================================================================
    // 경계 클램핑: 이미지 경계에서 완전한 3x3 윈도우 구성
    // ============================================================================
    // X 좌표 경계 처리: 좌측 경계에서는 가장자리 값으로 클램핑
    wire [7:0] top_x0 = n_top_sr0;
    wire [7:0] top_x1 = (x == 0) ? n_top_sr0 : n_top_sr1;
    wire [7:0] top_x2 = (x == 0) ? n_top_sr0 : ((x == 1) ? n_top_sr1 : n_top_sr2);
    wire [7:0] mid_x0 = n_mid_sr0;
    wire [7:0] mid_x1 = (x == 0) ? n_mid_sr0 : n_mid_sr1;
    wire [7:0] mid_x2 = (x == 0) ? n_mid_sr0 : ((x == 1) ? n_mid_sr1 : n_mid_sr2);
    wire [7:0] cur_x0 = n_cur_sr0;
    wire [7:0] cur_x1 = (x == 0) ? n_cur_sr0 : n_cur_sr1;
    wire [7:0] cur_x2 = (x == 0) ? n_cur_sr0 : ((x == 1) ? n_cur_sr1 : n_cur_sr2);

    // Y 좌표 경계 처리: 상단 경계에서는 가장자리 값으로 클램핑
    wire [7:0] selT_x0 = (y == 0) ? cur_x0 : ((y == 1) ? mid_x0 : top_x0);
    wire [7:0] selT_x1 = (y == 0) ? cur_x1 : ((y == 1) ? mid_x1 : top_x1);
    wire [7:0] selT_x2 = (y == 0) ? cur_x2 : ((y == 1) ? mid_x2 : top_x2);
    wire [7:0] selM_x0 = (y == 0) ? cur_x0 : mid_x0;
    wire [7:0] selM_x1 = (y == 0) ? cur_x1 : mid_x1;
    wire [7:0] selM_x2 = (y == 0) ? cur_x2 : mid_x2;

    // ============================================================================
    // 최종 3x3 픽셀 윈도우
    // ============================================================================
    // 3x3 윈도우 구성:
    // g00  g01  g02
    // g10  g11  g12
    // g20  g21  g22
    wire [7:0] g00 = selT_x2; // (x-2, y-2) - 상단 좌측
    wire [7:0] g01 = selT_x1; // (x-1, y-2) - 상단 중앙
    wire [7:0] g02 = selT_x0; // (x  , y-2) - 상단 우측
    wire [7:0] g10 = selM_x2; // (x-2, y-1) - 중간 좌측
    wire [7:0] g11 = selM_x1; // (x-1, y-1) - 중간 중앙
    wire [7:0] g12 = selM_x0; // (x  , y-1) - 중간 우측
    wire [7:0] g20 = cur_x2;  // (x-2, y  ) - 하단 좌측
    wire [7:0] g21 = cur_x1;  // (x-1, y  ) - 하단 중앙
    wire [7:0] g22 = cur_x0;  // (x  , y  ) - 하단 우측 (현재 픽셀)

    // ============================================================================
    // Sobel 그래디언트 계산
    // ============================================================================
    // Sobel 커널:
    // Gx = [-1  0 +1]   Gy = [+1 +2 +1]
    //      [-2  0 +2]        [ 0  0  0]
    //      [-1  0 +1]        [-1 -2 -1]
    // ============================================================================
    // Stage 1: |Gx|, |Gy| 계산
    // Stage 2: magnitude + threshold 처리
    
    reg [10:0] gx_abs;  // Gx 절댓값
    reg [10:0] gy_abs;  // Gy 절댓값
    reg [11:0] mag;     // 그래디언트 크기 (magnitude)
    
    // Gx 양수 부분: 우측 열 (g02, g12, g22)
    wire [10:0] gx_pos = {3'b0,g02} + {2'b0,g12,1'b0} + {3'b0,g22};
    // Gx 음수 부분: 좌측 열 (g00, g10, g20)
    wire [10:0] gx_neg = {3'b0,g00} + {2'b0,g10,1'b0} + {3'b0,g20};
    // Gy 양수 부분: 상단 행 (g00, g01, g02)
    wire [10:0] gy_pos = {3'b0,g00} + {2'b0,g01,1'b0} + {3'b0,g02};
    // Gy 음수 부분: 하단 행 (g20, g21, g22)
    wire [10:0] gy_neg = {3'b0,g20} + {2'b0,g21,1'b0} + {3'b0,g22};

    // ============================================================================
    // 파이프라인 유효 신호 및 그래디언트 계산
    // ============================================================================
    reg [PIPE_LAT-1:0] vpipe = {PIPE_LAT{1'b0}};  // 유효 파이프라인
    
    always @(posedge clk) begin
        if (frame_start) begin
            // 프레임 시작 시 모든 레지스터 초기화
            gx_abs <= 11'd0;
            gy_abs <= 11'd0;
            mag    <= 12'd0;
            vpipe <= {PIPE_LAT{1'b0}};
            pixel_out <= 8'd0;
            sobel_ready <= 1'b0;
        end else begin
            // 유효 파이프라인 시프트
            vpipe <= {vpipe[PIPE_LAT-2:0], window_valid};
            
            // ====================================================================
            // Stage 1: |Gx|, |Gy| 계산
            // ====================================================================
            if (window_valid) begin
                // 절댓값 계산: |a - b| = (a >= b) ? (a - b) : (b - a)
                gx_abs <= (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
                gy_abs <= (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
            end else begin
                gx_abs <= 11'd0;
                gy_abs <= 11'd0;
            end
            
            // ====================================================================
            // Stage 2: magnitude + threshold 출력
            // ====================================================================
            // 그래디언트 크기 = |Gx| + |Gy|
            mag <= {1'b0,gx_abs} + {1'b0,gy_abs};
            
            if (vpipe[PIPE_LAT-1]) begin
                if (border_pixel) begin
                    // 상단/좌측 2 픽셀은 경계 아티팩트 방지를 위해 0 출력
                    pixel_out <= 8'h00;
                    sobel_ready <= 1'b0;
                end else begin
                    // 임계값 비교: magnitude가 threshold 이상이면 엣지 (255), 아니면 배경 (0)
                    if ((mag[11:8] != 4'b0000 ? 8'hFF : mag[7:0]) >= threshold)
                        pixel_out <= 8'hFF;  // 엣지
                    else
                        pixel_out <= 8'h00;  // 배경
                    sobel_ready <= 1'b1;     // 출력 유효
                end
            end else begin
                pixel_out <= 8'h00;
                sobel_ready <= 1'b0;
            end
        end
    end

endmodule
