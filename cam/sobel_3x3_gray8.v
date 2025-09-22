// 3x3 소벨 엣지 검출 필터 (8비트 그레이스케일 입력)
// 이미지의 수평 및 수직 방향 밝기 변화(그래디언트)를 계산하여 엣지를 검출
module sobel_3x3_gray8 (
    input  wire        clk,
    input  wire        enable,          // 모듈 동작 활성화 신호
    input  wire [7:0]  pixel_in,      // 입력 픽셀 데이터
    input  wire [16:0] pixel_addr,    // 현재 픽셀의 주소
    input  wire        vsync,           // 수직 동기화 신호
    input  wire        active_area,     // 유효 영상 영역 신호
    input  wire [7:0]  threshold,       // 엣지 판별을 위한 임계값
    output reg  [7:0]  pixel_out,     // 필터링된 출력 픽셀 (바이너리 엣지맵)
    output reg         sobel_ready      // 필터 출력 유효 신호
);

    // 이미지 해상도 정의
    localparam H_ACTIVE = 320;
    localparam V_ACTIVE = 240;

    // 라인 버퍼 2개
    reg [7:0] line_buffer1 [0:H_ACTIVE-1];
    reg [7:0] line_buffer2 [0:H_ACTIVE-1];

    // 현재 픽셀 시프트 레지스터
    reg [7:0] p_reg1, p_reg2, p_reg3;

    // 3x3 윈도우 픽셀
    wire [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;

    // 카운터 및 경계 감지
    reg  [8:0] h_count = 9'd0;
    reg  [8:0] v_count = 9'd0;
    wire is_first_col, is_last_col;
    
    reg vsync_prev = 1'b0;
    reg active_prev = 1'b0;

    // 파이프라인 레지스터
    reg [10:0] mag_pipe1;
    reg window_valid_pipe1;

    // 카운터 로직
    always @(posedge clk) begin
        vsync_prev <= vsync;
        active_prev <= active_area;

        // Active area 내에서 카운터 동작, 그 외에는 리셋
        if (enable && active_area && active_prev) begin
            if (h_count == H_ACTIVE - 1) begin // 라인의 끝
                h_count <= 9'd0;
                v_count <= v_count + 1;
            end else begin // 라인 진행 중
                h_count <= h_count + 1;
            end
        end else begin // 프레임 시작 또는 비활성 영역
            h_count <= 9'd0;
            v_count <= 9'd0;
        end
    end

    assign is_first_col = (h_count == 0);
    assign is_last_col  = (h_count == H_ACTIVE - 1);

    // 라인 버퍼 및 시프트 레지스터
    always @(posedge clk) begin
        if (enable && active_area) begin
            line_buffer2[h_count] <= pixel_in;
            if (!is_last_col) line_buffer1[h_count + 1] <= line_buffer2[h_count];
            p_reg3 <= pixel_in;
            p_reg2 <= p_reg3;
            p_reg1 <= p_reg2;
        end
    end

    // 3x3 윈도우 구성
    assign w01 = line_buffer1[h_count];
    assign w00 = is_first_col ? w01 : line_buffer1[h_count-1];
    assign w02 = is_last_col  ? w01 : line_buffer1[h_count+1];
    assign w11 = line_buffer2[h_count];
    assign w10 = is_first_col ? w11 : line_buffer2[h_count-1];
    assign w12 = is_last_col  ? w11 : line_buffer2[h_count+1];
    assign w21 = p_reg3;
    assign w20 = p_reg2;
    assign w22 = p_reg1;
    
    wire window_valid = (v_count > 1) && (h_count > 1);

    // 1단계 파이프라인: Gx, Gy 그래디언트 및 크기(magnitude) 계산
    // Gx = [-1 0 +1; -2 0 +2; -1 0 +1], Gy = [+1 +2 +1; 0 0 0; -1 -2 -1]
    wire signed [10:0] gx = (w02 + (w12 << 1) + w22) - (w00 + (w10 << 1) + w20);
    wire signed [10:0] gy = (w00 + (w01 << 1) + w02) - (w20 + (w21 << 1) + w22);
    wire [10:0] gx_abs = gx[10] ? -gx : gx;
    wire [10:0] gy_abs = gy[10] ? -gy : gy;
    
    always @(posedge clk) begin
        window_valid_pipe1 <= window_valid && enable && active_area;
        if (window_valid && enable && active_area) begin
            mag_pipe1 <= gx_abs + gy_abs; // 그래디언트 크기 근사치 (|Gx|+|Gy|)
        end else begin
            mag_pipe1 <= 11'd0;
        end
    end

    // 2단계 파이프라인: 임계값 비교 및 출력
    always @(posedge clk) begin
        if (window_valid_pipe1) begin
            // 그래디언트 크기가 임계값보다 크면 엣지로 판단 (흰색), 아니면 배경 (검은색)
            if (mag_pipe1 > {3'b0, threshold}) begin
                pixel_out <= 8'hFF;
            end else begin
                pixel_out <= 8'h00;
            end
            sobel_ready <= 1'b1;
        end else begin
            pixel_out   <= 8'h00;
            sobel_ready <= 1'b0;
        end
    end

endmodule


