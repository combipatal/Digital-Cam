// ==============================================================================
// Canny 엣지 검출기 - 8비트 그레이스케일 스트림 처리용
// ==============================================================================
// 
// [개요]
// 이 모듈은 실시간 비디오 스트림에서 Canny 엣지 검출 알고리즘을 수행합니다.
// 라인 버퍼를 사용하여 3x3 윈도우를 형성하고, 4단계 파이프라인으로 처리합니다.
//
// [알고리즘 단계]
// 1. Sobel 필터로 그래디언트 크기 및 방향 계산
// 2. 비최대 억제(NMS): 그래디언트 방향에서 최대값만 유지
// 3. 이중 임계값: strong/weak 엣지 분류
// 4. 히스테리시스: strong 엣지 주변의 weak 엣지만 최종 엣지로 인정
//
// [타이밍]
// - 입력: 래스터 스캔 순서의 픽셀 스트림 (enable && active_area일 때 유효)
// - 출력: 입력 대비 약 7클럭 지연 (4단계 파이프라인 + 라인 버퍼 지연)
// - 출력 픽셀 위치: 입력 스트림의 (x-1, y-1) 픽셀에 해당
//
// [하드웨어 구조]
// - 2개의 라인 버퍼 (각 IMG_WIDTH 깊이) - 원본 픽셀용
// - 2개의 라인 버퍼 (각 IMG_WIDTH 깊이) - 그래디언트 크기/방향용
// - 총 4단계 파이프라인 레지스터
//
// ==============================================================================
module canny_3x3_gray8 # (
    parameter integer IMG_WIDTH = 320  // 영상 가로 폭 (라인 버퍼 크기)
)(
    input  wire        clk,              // 시스템 클럭 (일반적으로 25MHz VGA 클럭)
    input  wire        enable,           // 모듈 활성화 신호
    input  wire [7:0]  pixel_in,         // 입력 그레이스케일 픽셀 (0=검정, 255=흰색)
    input  wire [16:0] pixel_addr,       // 인터페이스 호환성을 위해 유지 (내부 사용 안 함)
    input  wire        vsync,            // 수직 동기 신호 (프레임 리셋용)
    input  wire        active_area,      // 유효 픽셀 영역 표시 (hsync, vsync 블랭킹 제외)
    input  wire [7:0]  threshold_low,    // 히스테리시스 하위 임계값 (weak 엣지 판단)
    input  wire [7:0]  threshold_high,   // 히스테리시스 상위 임계값 (strong 엣지 판단)
    output reg  [7:0]  pixel_out,        // 출력 픽셀 (0=엣지 아님, 255=엣지)
    output reg         canny_ready       // 출력 픽셀 유효 신호
);

    // 미사용 신호 경고 방지용 (pixel_addr는 호환성을 위해 포트에만 존재)
    wire _unused_addr = &{1'b0, pixel_addr};

    // ==================================================================
    // 타이밍 헬퍼: 프레임/라인 경계 감지
    // ==================================================================
    // VGA 타이밍 신호를 분석하여 중요한 이벤트를 감지합니다.
    // 이를 통해 라인 버퍼 인덱스 리셋, 행/열 카운터 관리 등이 가능합니다.
    
    reg vsync_prev  = 1'b1;   // vsync의 이전 클럭 값 (엣지 검출용)
    reg active_prev = 1'b0;   // active_area의 이전 클럭 값 (엣지 검출용)
    
    always @(posedge clk) begin
        vsync_prev  <= vsync;
        active_prev <= active_area;
    end

    // 프레임 시작 감지: VSYNC 하강 엣지 (1->0 전환)
    // 새 프레임이 시작되면 모든 카운터와 버퍼를 초기화해야 합니다.
    wire frame_reset = vsync_prev & ~vsync;
    
    // 라인 시작 감지: active_area 상승 엣지 (0->1 전환)
    // 새 라인이 시작되면 열(col) 카운터를 리셋합니다.
    wire line_start  =  active_area & ~active_prev;
    
    // 라인 종료 감지: active_area 하강 엣지 (1->0 전환)
    // 라인이 끝나면 행(row) 카운터를 증가시킵니다.
    wire line_end    = ~active_area &  active_prev;

    // 픽셀 유효 신호: enable과 active_area가 모두 활성화된 경우에만 픽셀 처리
    wire pixel_valid = enable && active_area;

    // ==================================================================
    // 파이프라인 단계 0: 3x3 픽셀 윈도우 생성
    // ==================================================================
    // [목적]
    // 스트림 형태로 들어오는 픽셀 데이터를 3x3 윈도우로 변환합니다.
    // Sobel 필터는 3x3 커널을 사용하므로, 현재 픽셀과 그 주변 8개 픽셀이 필요합니다.
    //
    // [구조]
    // - 2개의 라인 버퍼: 이전 라인(y-1)과 2라인 전(y-2) 데이터를 저장
    // - 3개의 수평 시프트 레지스터 체인: 각 라인마다 최근 3픽셀(x, x-1, x-2)을 유지
    //
    // [메모리 구조]
    // line2[col] ← line1[col] (이전 프레임의 line1이 line2로 이동)
    // line1[col] ← pixel_in   (현재 픽셀이 line1에 저장)
    //
    // [3x3 윈도우 배치] (중심은 l1_1, 즉 (x-1, y-1) 픽셀)
    //   l2_2  l2_1  l2_0    (y-2 라인)
    //   l1_2  l1_1  l1_0    (y-1 라인) ← 중심 픽셀
    //   cur_2 cur_1 cur_0   (y   라인, 현재 입력 스트림)
    
    // 영상 너비에 따라 열 인덱스 비트 수를 최적화
    localparam integer COL_BITS = (IMG_WIDTH <= 256) ? 8 :
                                   (IMG_WIDTH <= 512) ? 9 : 10;

    // 행/열 카운터 (래스터 스캔 위치 추적)
    reg [COL_BITS-1:0] col = {COL_BITS{1'b0}};   // 현재 열 위치: 0 ~ IMG_WIDTH-1
    reg [9:0] row = 10'd0;                        // 현재 행 위치: 0 ~ 1023 (최대)

    // 라인 버퍼: 이전 프레임 라인들을 저장 (각 IMG_WIDTH 픽셀)
    reg [7:0] line1 [0:IMG_WIDTH-1];  // 1라인 전 (y-1)
    reg [7:0] line2 [0:IMG_WIDTH-1];  // 2라인 전 (y-2)

    // 수평 시프트 레지스터: 각 라인의 최근 3픽셀 저장
    // cur_*: 현재 라인 (y)의 최근 3픽셀
    reg [7:0] cur_0 = 8'd0, cur_1 = 8'd0, cur_2 = 8'd0;
    // l1_*: 1라인 전 (y-1)의 최근 3픽셀
    reg [7:0] l1_0  = 8'd0, l1_1  = 8'd0, l1_2  = 8'd0;
    // l2_*: 2라인 전 (y-2)의 최근 3픽셀
    reg [7:0] l2_0  = 8'd0, l2_1  = 8'd0, l2_2  = 8'd0;

    // 라인 버퍼 읽기 탭: 현재 열 위치의 이전 라인 데이터
    wire [7:0] line1_tap = line1[col];  // y-1 라인의 현재 열 픽셀
    wire [7:0] line2_tap = line2[col];  // y-2 라인의 현재 열 픽셀

    // 라인 버퍼 및 윈도우 관리 로직
    always @(posedge clk) begin
        if (frame_reset) begin
            // 새 프레임 시작: 모든 카운터와 레지스터 초기화
            col <= {COL_BITS{1'b0}};
            row <= 10'd0;
            cur_0 <= 8'd0; cur_1 <= 8'd0; cur_2 <= 8'd0;
            l1_0  <= 8'd0; l1_1  <= 8'd0; l1_2  <= 8'd0;
            l2_0  <= 8'd0; l2_1  <= 8'd0; l2_2  <= 8'd0;
        end else begin
            // 라인 시작 시: 열 카운터와 시프트 레지스터만 리셋
            // (라인 버퍼 내용은 유지)
            if (line_start) begin
                col <= {COL_BITS{1'b0}};
                cur_0 <= 8'd0; cur_1 <= 8'd0; cur_2 <= 8'd0;
                l1_0  <= 8'd0; l1_1  <= 8'd0; l1_2  <= 8'd0;
                l2_0  <= 8'd0; l2_1  <= 8'd0; l2_2  <= 8'd0;
            end else if (pixel_valid && (col < IMG_WIDTH-1)) begin
                // 유효한 픽셀이 들어올 때마다 열 카운터 증가
                col <= col + 1'b1;
            end

            // 라인 종료 시: 행 카운터 증가
            if (line_end) begin
                if (row < 10'd1023)
                    row <= row + 1'b1;
            end

            // 유효 픽셀 처리: 시프트 레지스터 갱신 및 라인 버퍼 저장
            if (pixel_valid) begin
                // 수평 시프트 레지스터 체인 (왼쪽으로 이동)
                // 새 픽셀이 _0에 들어가고, 기존 픽셀들은 _1, _2로 밀림
                cur_2 <= cur_1; cur_1 <= cur_0; cur_0 <= pixel_in;      // 현재 라인
                l1_2  <= l1_1;  l1_1  <= l1_0;  l1_0  <= line1_tap;     // y-1 라인
                l2_2  <= l2_1;  l2_1  <= l2_0;  l2_0  <= line2_tap;     // y-2 라인

                // 라인 버퍼 업데이트 (쓰기)
                // line2 ← line1 (한 라인씩 아래로 이동)
                // line1 ← 현재 픽셀
                line2[col] <= line1_tap;
                line1[col] <= pixel_in;
            end
        end
    end

    // 윈도우 준비 완료 신호: 3x3 윈도우가 유효한 데이터로 채워졌는지 확인
    // - 조건: 최소 2행 이상, 최소 2열 이상 진행되어야 함
    wire window_ready = pixel_valid && (row >= 10'd2) && (col >= 2);
    
    // 경계 픽셀 플래그: 영상 가장자리로 3x3 윈도우를 구성할 수 없는 위치
    wire border_flag  = pixel_valid && ((row < 10'd2) || (col < 2));

    // ==================================================================
    // Sobel 연산: 그래디언트 크기 및 방향 계산 (조합 로직)
    // ==================================================================
    // 3x3 윈도우 픽셀 명명 (p11이 중심)
    //   p00  p01  p02
    //   p10  p11  p12
    //   p20  p21  p22
    wire [7:0] p00 = l2_2;
    wire [7:0] p01 = l2_1;
    wire [7:0] p02 = l2_0;
    wire [7:0] p10 = l1_2;
    wire [7:0] p11 = l1_1;   // 중심 픽셀 (출력 대상)
    wire [7:0] p12 = l1_0;
    wire [7:0] p20 = cur_2;
    wire [7:0] p21 = cur_1;
    wire [7:0] p22 = cur_0;

    // Sobel X 그래디언트 커널:       Sobel Y 그래디언트 커널:
    //   -1   0  +1                      -1  -2  -1
    //   -2   0  +2                       0   0   0
    //   -1   0  +1                      +1  +2  +1
    //
    // Gx = (p02 + 2*p12 + p22) - (p00 + 2*p10 + p20)
    // Gy = (p00 + 2*p01 + p02) - (p20 + 2*p21 + p22)
    
    // X 그래디언트 양/음 항 (뺄셈 전)
    wire [10:0] gx_pos = {3'b000,p02} + {2'b00,p12,1'b0} + {3'b000,p22};  // 오른쪽 열
    wire [10:0] gx_neg = {3'b000,p00} + {2'b00,p10,1'b0} + {3'b000,p20};  // 왼쪽 열
    
    // Y 그래디언트 양/음 항 (뺄셈 전)
    wire [10:0] gy_pos = {3'b000,p00} + {2'b00,p01,1'b0} + {3'b000,p02};  // 위쪽 행
    wire [10:0] gy_neg = {3'b000,p20} + {2'b00,p21,1'b0} + {3'b000,p22};  // 아래쪽 행

    // 부호 있는 그래디언트 값 계산
    wire signed [11:0] gx_signed_next = {1'b0,gx_pos} - {1'b0,gx_neg};
    wire signed [11:0] gy_signed_next = {1'b0,gy_pos} - {1'b0,gy_neg};

    // 그래디언트 절댓값 계산 (부호 없는 크기)
    wire [10:0] gx_abs_next = (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
    wire [10:0] gy_abs_next = (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);

    // 그래디언트 크기 근사: |Gx| + |Gy|
    // (sqrt(Gx^2 + Gy^2) 대신 맨해튼 거리 사용 - 하드웨어 효율성)
    wire [11:0] mag_sum_next = {1'b0,gx_abs_next} + {1'b0,gy_abs_next};

    // 그래디언트 방향 계산을 위한 절댓값 (비교용)
    wire [10:0] ax_next = gx_signed_next[11] ? (~gx_signed_next[10:0] + 11'd1) : gx_signed_next[10:0];
    wire [10:0] ay_next = gy_signed_next[11] ? (~gy_signed_next[10:0] + 11'd1) : gy_signed_next[10:0];

    // 그래디언트 방향 양자화 (4방향으로 근사)
    // 2'b00: 수평 (0° 또는 180°)   - ay <= ax/2
    // 2'b10: 수직 (90° 또는 270°)  - ax <= ay/2
    // 2'b01: 대각선 (45° 방향)      - Gx와 Gy가 반대 부호
    // 2'b11: 대각선 (135° 방향)     - Gx와 Gy가 같은 부호
    wire [1:0] dir_next = (ay_next <= (ax_next >> 1))        ? 2'b00 :
                          (ax_next <= (ay_next >> 1))        ? 2'b10 :
                          ((gx_signed_next[11] ^ gy_signed_next[11]) ? 2'b01 : 2'b11);

    // ==================================================================
    // 파이프라인 단계 1: Sobel 결과 등록 (레지스터 스테이지)
    // ==================================================================
    // [목적]
    // Sobel 연산의 조합 로직 결과를 레지스터에 저장하여 파이프라인 성능 향상
    // 동시에 좌표 및 유효성 플래그들도 함께 전달하여 동기화 유지
    
    // 좌표 추적 레지스터 (다음 단계에서 올바른 픽셀 위치 확인용)
    reg [COL_BITS-1:0] col_s1 = {COL_BITS{1'b0}};
    reg [9:0] row_s1 = 10'd0;
    
    // 제어 신호 레지스터 (파이프라인 유효성 추적)
    reg       active_s1 = 1'b0;         // 픽셀 처리 활성화 상태
    reg       window_valid_s1 = 1'b0;   // 3x3 윈도우 유효성
    reg       border_s1 = 1'b0;         // 영상 경계 여부

    // Sobel 연산 결과 레지스터
    reg [11:0] mag_sum_s1 = 12'd0;      // 그래디언트 크기 (|Gx| + |Gy|)
    reg [1:0]  dir_raw_s1 = 2'b00;      // 그래디언트 방향 (4방향 양자화)

    always @(posedge clk) begin
        if (frame_reset) begin
            // 프레임 리셋: 모든 단계 1 레지스터 초기화
            col_s1 <= {COL_BITS{1'b0}};
            row_s1 <= 10'd0;
            active_s1 <= 1'b0;
            window_valid_s1 <= 1'b0;
            border_s1 <= 1'b0;
            mag_sum_s1 <= 12'd0;
            dir_raw_s1 <= 2'b00;
        end else begin
            // 좌표 및 제어 신호 전달 (파이프라인 동기화)
            col_s1 <= col;
            row_s1 <= row;
            active_s1 <= pixel_valid;
            window_valid_s1 <= window_ready;
            border_s1 <= border_flag;

            // Sobel 연산 결과 저장 (유효한 윈도우일 때만)
            if (window_ready) begin
                mag_sum_s1 <= mag_sum_next;
                dir_raw_s1 <= dir_next;
            end else begin
                // 무효 영역은 0으로 채움
                mag_sum_s1 <= 12'd0;
                dir_raw_s1 <= 2'b00;
            end
        end
    end

    // ==================================================================
    // 파이프라인 단계 2: 크기 포화 처리 및 데이터 정규화
    // ==================================================================
    // [목적]
    // 1. 그래디언트 크기를 12비트에서 8비트로 변환 (포화 처리)
    // 2. 경계 픽셀 처리: 영상 가장자리는 강제로 0으로 설정
    // 3. 방향 정보는 그대로 전달
    
    // 좌표 및 제어 신호 레지스터
    reg [COL_BITS-1:0] col_s2 = {COL_BITS{1'b0}};
    reg [9:0] row_s2 = 10'd0;
    reg       active_s2 = 1'b0;
    reg       window_valid_s2 = 1'b0;
    reg       border_s2 = 1'b0;

    // 정규화된 그래디언트 데이터
    reg [7:0] mag_s2 = 8'd0;     // 8비트 그래디언트 크기 (포화 처리됨)
    reg [1:0] dir_s2 = 2'b00;    // 그래디언트 방향 (단계 1과 동일)

    always @(posedge clk) begin
        if (frame_reset) begin
            // 프레임 리셋: 모든 단계 2 레지스터 초기화
            col_s2 <= {COL_BITS{1'b0}};
            row_s2 <= 10'd0;
            active_s2 <= 1'b0;
            window_valid_s2 <= 1'b0;
            border_s2 <= 1'b0;
            mag_s2 <= 8'd0;
            dir_s2 <= 2'b00;
        end else begin
            // 좌표 및 제어 신호 전달 (파이프라인 동기화)
            col_s2 <= col_s1;
            row_s2 <= row_s1;
            active_s2 <= active_s1;
            window_valid_s2 <= window_valid_s1;
            border_s2 <= border_s1;

            // 유효 픽셀이고 경계가 아닌 경우에만 데이터 처리
            if (window_valid_s1 && !border_s1) begin
                // 크기 포화 처리: 12비트 값이 255를 초과하면 255로 제한
                // mag_sum_s1[11:8]이 0이 아니면 오버플로우 → 0xFF로 설정
                mag_s2 <= (mag_sum_s1[11:8] != 4'b0000) ? 8'hFF : mag_sum_s1[7:0];
                dir_s2 <= dir_raw_s1;
            end else begin
                // 무효 영역 또는 경계 픽셀은 0으로 설정
                mag_s2 <= 8'd0;
                dir_s2 <= 2'b00;
            end
        end
    end

    // ==================================================================
    // 파이프라인 단계 3: 그래디언트 데이터용 3x3 윈도우 생성
    // ==================================================================
    // [목적]
    // 비최대 억제(NMS)를 위해서는 현재 픽셀의 그래디언트 크기뿐만 아니라
    // 주변 8개 픽셀의 그래디언트 크기도 필요합니다. 이를 위해 단계 0과
    // 유사한 구조로 그래디언트 크기/방향용 라인 버퍼를 구성합니다.
    //
    // [구조]
    // - 단계 0: 원본 픽셀 3x3 윈도우 생성
    // - 단계 3: 그래디언트 크기/방향 3x3 윈도우 생성
    
    // 그래디언트 크기용 라인 버퍼 (2라인)
    reg [7:0] mag_line1 [0:IMG_WIDTH-1];  // 1라인 전의 그래디언트 크기
    reg [7:0] mag_line2 [0:IMG_WIDTH-1];  // 2라인 전의 그래디언트 크기
    
    // 그래디언트 방향용 라인 버퍼 (2라인)
    reg [1:0] dir_line1 [0:IMG_WIDTH-1];  // 1라인 전의 그래디언트 방향
    reg [1:0] dir_line2 [0:IMG_WIDTH-1];  // 2라인 전의 그래디언트 방향

    // 그래디언트 크기의 수평 시프트 레지스터 (3x3 윈도우용)
    reg [7:0] mag_cur0 = 8'd0, mag_cur1 = 8'd0, mag_cur2 = 8'd0;  // 현재 라인
    reg [7:0] mag_l1_0 = 8'd0, mag_l1_1 = 8'd0, mag_l1_2 = 8'd0;  // y-1 라인
    reg [7:0] mag_l2_0 = 8'd0, mag_l2_1 = 8'd0, mag_l2_2 = 8'd0;  // y-2 라인

    // 그래디언트 방향의 수평 시프트 레지스터 (중심 픽셀 방향만 필요)
    reg [1:0] dir_mid0 = 2'b00, dir_mid1 = 2'b00, dir_mid2 = 2'b00;

    // 좌표 및 제어 신호 레지스터
    reg [COL_BITS-1:0] col_s3 = {COL_BITS{1'b0}};
    reg [9:0] row_s3 = 10'd0;
    reg       active_s3 = 1'b0;
    reg       window_valid_s3 = 1'b0;
    reg       border_s3 = 1'b0;

    // 라인 버퍼 읽기 탭
    wire [7:0] mag_l1_tap = mag_line1[col_s2];
    wire [7:0] mag_l2_tap = mag_line2[col_s2];
    wire [1:0] dir_l1_tap = dir_line1[col_s2];

    // 라인 버퍼에 저장할 데이터 (유효 픽셀만 저장, 무효는 0)
    wire [7:0] mag_store = (window_valid_s2 && !border_s2) ? mag_s2 : 8'd0;
    wire [1:0] dir_store = (window_valid_s2 && !border_s2) ? dir_s2 : 2'b00;

    // 그래디언트 라인 버퍼 및 윈도우 관리 로직
    always @(posedge clk) begin
        if (frame_reset) begin
            // 프레임 리셋: 모든 단계 3 레지스터 초기화
            mag_cur0 <= 8'd0; mag_cur1 <= 8'd0; mag_cur2 <= 8'd0;
            mag_l1_0 <= 8'd0; mag_l1_1 <= 8'd0; mag_l1_2 <= 8'd0;
            mag_l2_0 <= 8'd0; mag_l2_1 <= 8'd0; mag_l2_2 <= 8'd0;
            dir_mid0 <= 2'b00; dir_mid1 <= 2'b00; dir_mid2 <= 2'b00;
            col_s3 <= {COL_BITS{1'b0}};
            row_s3 <= 10'd0;
            active_s3 <= 1'b0;
            window_valid_s3 <= 1'b0;
            border_s3 <= 1'b0;
        end else begin
            // 좌표 및 제어 신호 전달 (파이프라인 동기화)
            col_s3 <= col_s2;
            row_s3 <= row_s2;
            active_s3 <= active_s2;
            window_valid_s3 <= window_valid_s2;
            border_s3 <= border_s2;

            // 유효 픽셀일 때 라인 버퍼 및 시프트 레지스터 업데이트
            if (active_s2) begin
                // 라인 버퍼 업데이트 (크기/방향 데이터)
                mag_line2[col_s2] <= mag_l1_tap;   // line2 ← line1
                mag_line1[col_s2] <= mag_store;    // line1 ← 현재 크기
                dir_line2[col_s2] <= dir_line1[col_s2];  // line2 ← line1
                dir_line1[col_s2] <= dir_store;    // line1 ← 현재 방향

                // 라인 시작 시: 시프트 레지스터 초기화
                if (col_s2 == 0) begin
                    mag_cur2 <= 8'd0; mag_cur1 <= 8'd0; mag_cur0 <= mag_store;
                    mag_l1_2 <= 8'd0; mag_l1_1 <= 8'd0; mag_l1_0 <= mag_l1_tap;
                    mag_l2_2 <= 8'd0; mag_l2_1 <= 8'd0; mag_l2_0 <= mag_l2_tap;
                    dir_mid2 <= 2'b00; dir_mid1 <= 2'b00; dir_mid0 <= dir_l1_tap;
                end else begin
                    // 수평 시프트 레지스터 체인 (왼쪽으로 이동)
                    mag_cur2 <= mag_cur1;
                    mag_cur1 <= mag_cur0;
                    mag_cur0 <= mag_store;
                    mag_l1_2 <= mag_l1_1;
                    mag_l1_1 <= mag_l1_0;
                    mag_l1_0 <= mag_l1_tap;
                    mag_l2_2 <= mag_l2_1;
                    mag_l2_1 <= mag_l2_0;
                    mag_l2_0 <= mag_l2_tap;
                    dir_mid2 <= dir_mid1;
                    dir_mid1 <= dir_mid0;
                    dir_mid0 <= dir_l1_tap;
                end
            end
        end
    end

    // ==================================================================
    // 파이프라인 단계 4: 비최대 억제(NMS) 및 히스테리시스 임계값
    // ==================================================================
    // [목적]
    // 1. 비최대 억제(Non-Maximum Suppression): 엣지를 얇게 만들기
    //    - 그래디언트 방향에 수직인 방향의 인접 픽셀과 크기 비교
    //    - 현재 픽셀이 해당 방향에서 최대값이 아니면 억제(제거)
    //
    // 2. 히스테리시스 임계값(Hysteresis Thresholding): 노이즈 제거
    //    - Strong 엣지: threshold_high 이상 → 무조건 엣지로 인정
    //    - Weak 엣지: threshold_low ~ threshold_high → 주변에 strong이 있으면 엣지
    //    - 너무 약한 엣지: threshold_low 미만 → 무조건 제거
    
    // 그래디언트 크기 3x3 윈도우 (m11이 중심 픽셀)
    //   m00  m01  m02
    //   m10  m11  m12
    //   m20  m21  m22
    wire [7:0] m00 = mag_l2_2;
    wire [7:0] m01 = mag_l2_1;
    wire [7:0] m02 = mag_l2_0;
    wire [7:0] m10 = mag_l1_2;
    wire [7:0] m11 = mag_l1_1;  // 중심 픽셀 (현재 처리 대상)
    wire [7:0] m12 = mag_l1_0;
    wire [7:0] m20 = mag_cur2;
    wire [7:0] m21 = mag_cur1;
    wire [7:0] m22 = mag_cur0;

    // 중심 픽셀의 그래디언트 방향
    wire [1:0] dir_center = dir_mid1;

    // 비최대 억제: 그래디언트 방향에 수직인 두 이웃 픽셀 선택
    // - 2'b00 (수평): 좌우 이웃 (m10, m12)
    // - 2'b10 (수직): 상하 이웃 (m01, m21)
    // - 2'b01 (대각선 /): 좌하-우상 이웃 (m02, m20)
    // - 2'b11 (대각선 \): 좌상-우하 이웃 (m00, m22)
    wire [7:0] nb_a = (dir_center == 2'b00) ? m10 :
                      (dir_center == 2'b10) ? m01 :
                      (dir_center == 2'b01) ? m02 :
                                              m00;

    wire [7:0] nb_b = (dir_center == 2'b00) ? m12 :
                      (dir_center == 2'b10) ? m21 :
                      (dir_center == 2'b01) ? m20 :
                                              m22;

    // NMS 판정: 중심 픽셀이 두 이웃보다 모두 크거나 같으면 유지
    wire       nms_keep = (m11 >= nb_a) && (m11 >= nb_b);
    wire [7:0] nms_mag  = nms_keep ? m11 : 8'd0;

    // 히스테리시스 임계값 1단계: 중심 픽셀 분류
    wire is_strong_center = (nms_mag >= threshold_high);  // Strong 엣지
    wire is_weak_center   = (nms_mag >= threshold_low);   // Weak 엣지 (이상)

    // 히스테리시스 임계값 2단계: 주변 8개 픽셀 중 strong 엣지 존재 여부
    // (중심 픽셀이 weak일 때, 주변에 strong이 있으면 연결된 엣지로 판단)
    wire neigh_strong =
        (m00 >= threshold_high) | (m01 >= threshold_high) | (m02 >= threshold_high) |
        (m10 >= threshold_high) |                           (m12 >= threshold_high) |
        (m20 >= threshold_high) | (m21 >= threshold_high) | (m22 >= threshold_high);

    // 최종 출력 유효 신호: 유효한 윈도우이고, 경계가 아닌 경우만
    wire final_valid = window_valid_s3 && active_s3 && !border_s3;

    // 최종 출력 로직
    always @(posedge clk) begin
        if (frame_reset) begin
            pixel_out   <= 8'd0;
            canny_ready <= 1'b0;
        end else if (final_valid) begin
            // 엣지 판정 규칙:
            // 1. Strong 엣지이면 무조건 엣지 (0xFF)
            // 2. Weak 엣지이고 주변에 strong이 있으면 엣지 (0xFF)
            // 3. 그 외는 엣지 아님 (0x00)
            if (is_strong_center || (is_weak_center && neigh_strong))
                pixel_out <= 8'hFF;
            else
                pixel_out <= 8'h00;
            canny_ready <= 1'b1;
        end else begin
            // 무효 영역은 0 출력
            pixel_out   <= 8'h00;
            canny_ready <= 1'b0;
        end
    end

endmodule