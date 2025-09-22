// 3x3 가우시안 블러 필터 (8비트 그레이스케일 입력)
// 이미지의 노이즈를 감소시키고 부드럽게 만드는 효과
module gaussian_3x3_gray8 (
    input  wire        clk,
    input  wire        enable,          // 모듈 동작 활성화 신호
    input  wire [7:0]  pixel_in,      // 입력 픽셀 데이터
    input  wire [16:0] pixel_addr,    // 현재 픽셀의 주소 (디버깅/라인 감지용)
    input  wire        vsync,           // 수직 동기화 신호 (프레임 시작 감지)
    input  wire        active_area,     // 유효 영상 영역 신호
    output reg  [7:0]  pixel_out,     // 필터링된 출력 픽셀 데이터
    output reg         filter_ready     // 필터 출력 유효 신호
);

    // 이미지 해상도 정의 (QVGA: 320x240)
    localparam H_ACTIVE = 320;
    localparam V_ACTIVE = 240;

    // 라인 버퍼 2개 (이전 2개 라인을 저장하기 위함)
    // 각 라인 버퍼는 320개의 8비트 픽셀을 저장
    reg [7:0] line_buffer1 [0:H_ACTIVE-1];
    reg [7:0] line_buffer2 [0:H_ACTIVE-1];

    // 현재 픽셀을 저장하기 위한 3개의 시프트 레지스터 (3x3 윈도우의 세로축 구성)
    reg [7:0] p_reg1, p_reg2, p_reg3;

    // 3x3 윈도우를 구성하는 9개의 픽셀 값
    wire [7:0] w00, w01, w02; // 윗 줄
    wire [7:0] w10, w11, w12; // 중간 줄
    wire [7:0] w20, w21, w22; // 아랫 줄

    // 윈도우 유효성 및 경계 감지
    reg  [8:0] h_count = 9'd0; // 수평 카운터 (0-319)
    reg  [8:0] v_count = 9'd0; // 수직 카운터 (0-239)
    wire is_first_col, is_last_col;
    wire is_first_row, is_last_row;

    // vsync, active_area의 이전 상태 저장 (엣지 감지용)
    reg vsync_prev = 1'b0;
    reg active_prev = 1'b0;

    // 파이프라인 지연 레지스터
    reg [11:0] sum_blur_pipe1; // 1단계: 가중치 합산 결과
    reg window_valid_pipe1;   // 1단계: 윈도우 유효 신호

    // 수평/수직 카운터 및 엣지 감지 로직
    always @(posedge clk) begin
        vsync_prev <= vsync;
        active_prev <= active_area;

        if (enable && active_area) begin
            // 프레임 시작 (active_area 상승 엣지)
            if (!active_prev) begin
                h_count <= 9'd0;
                v_count <= 9'd0;
            end else begin
                if (is_last_col) begin
                    h_count <= 9'd0;
                    if (v_count == V_ACTIVE - 1) begin
                        v_count <= 9'd0; // 프레임 마지막에서 리셋 (vsync로도 처리 가능)
                    end else begin
                        v_count <= v_count + 1;
                    end
                end else begin
                    h_count <= h_count + 1;
                end
            end
        end else begin
            // 비활성 구간에서는 카운터 리셋
            h_count <= 9'd0;
            v_count <= 9'd0;
        end
    end

    assign is_first_col = (h_count == 0);
    assign is_last_col  = (h_count == H_ACTIVE - 1);
    assign is_first_row = (v_count == 0);
    assign is_last_row  = (v_count == V_ACTIVE - 1);

    // 라인 버퍼 및 픽셀 시프트 레지스터 로직
    always @(posedge clk) begin
        if (enable && active_area) begin
            // 라인 버퍼 쓰기
            line_buffer2[h_count] <= pixel_in;
            if (!is_last_col) begin // 마지막 픽셀에서는 다음 라인 버퍼로 복사 방지
                line_buffer1[h_count + 1] <= line_buffer2[h_count];
            end
            
            // 픽셀 시프트 레지스터 (현재 라인)
            p_reg3 <= pixel_in;
            p_reg2 <= p_reg3;
            p_reg1 <= p_reg2;
        end
    end

    // 3x3 윈도우 구성 (경계 패딩 처리 포함)
    // w0x: line_buffer1, w1x: line_buffer2, w2x: 현재 라인
    assign w01 = line_buffer1[h_count];
    assign w00 = is_first_col ? w01 : line_buffer1[h_count-1];
    assign w02 = is_last_col  ? w01 : line_buffer1[h_count+1];

    assign w11 = line_buffer2[h_count];
    assign w10 = is_first_col ? w11 : line_buffer2[h_count-1];
    assign w12 = is_last_col  ? w11 : line_buffer2[h_count+1];
    
    assign w21 = p_reg3; // 현재 들어온 픽셀
    assign w20 = p_reg2; // 1 클럭 전 픽셀
    assign w22 = p_reg1; // 2 클럭 전 픽셀

    // 윈도우가 유효한 시점 (최소 2라인, 2픽셀이 들어온 후)
    wire window_valid = (v_count > 1) && (h_count > 1);

    // 1단계 파이프라인: 가우시안 커널 가중치 합산
    // 커널: [1 2 1; 2 4 2; 1 2 1] / 16
    always @(posedge clk) begin
        window_valid_pipe1 <= window_valid && enable && active_area;
        if (window_valid && enable && active_area) begin
            sum_blur_pipe1 <= (w00 + w02 + w20 + w22)                 // 1*
                            + ((w01 + w10 + w12 + w21) << 1)          // 2*
                            + (w11 << 2);                            // 4*
        end else begin
            sum_blur_pipe1 <= 12'd0;
        end
    end
    
    // 2단계 파이프라인: 정규화(나누기) 및 출력
    always @(posedge clk) begin
        if (window_valid_pipe1) begin
            pixel_out   <= sum_blur_pipe1[11:4]; // 16으로 나누기 (>> 4)
            filter_ready <= 1'b1;
        end else begin
            pixel_out   <= 8'h00;
            filter_ready <= 1'b0;
        end
    end

endmodule


