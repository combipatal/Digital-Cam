// 표준 휘도(Luminance) 공식을 사용하여 최적화된 흑백(Grayscale) 변환 모듈
// (R+G+B)/3 나눗셈 대신 (R*77 + G*150 + B*29) >> 8 곱셈/시프트 연산을 사용합니다.
// 이 방식은 하드웨어에서 훨씬 빠르고 효율적이며, binary_divider 모듈이 필요 없습니다.

module do_black_white (
    // 제어 신호
    input rst_i,
    input clk_i, // 25 MHz 클럭
    input enable_filter,
    output led_done,

    // 프레임 버퍼 1 (읽기/쓰기)
    output reg [16:0] rdaddr_buf1,
    input [11:0] din_buf1,
    output reg [16:0] wraddr_buf1,
    output reg [11:0] dout_buf1,
    output reg we_buf1
);
    // FSM 상태 정의
    localparam IDLE_ST              = 3'b101,
               START_BLACKWHITE_ST  = 3'b000,
               GET_PIXEL_DATA_ST    = 3'b001,
               PROCESS_PIXEL_ST     = 3'b010, // 연산을 위한 파이프라인 스테이지
               SEND_PIXEL_DATA_ST   = 3'b011,
               DONE_ST              = 3'b100;

    localparam NUM_PIXELS = 17'd76799;

    // 내부 신호 및 레지스터
    reg led_done_r = 1'b0;
    reg [16:0] rw_cntr = 17'd0;
    reg [2:0] state = IDLE_ST;

    // 파이프라인 레지스터
    reg [11:0] din_buf1_reg; // GET_PIXEL_DATA_ST -> PROCESS_PIXEL_ST

    assign led_done = led_done_r;

    // --- Grayscale Conversion Logic ---
    wire [3:0] r_in = din_buf1_reg[11:8];
    wire [3:0] g_in = din_buf1_reg[7:4];
    wire [3:0] b_in = din_buf1_reg[3:0];

    // 곱셈 연산 (조합 논리)
    wire [11:0] r_comp = r_in * 77;  // 15*77 = 1155 (11비트 필요)
    wire [11:0] g_comp = g_in * 150; // 15*150 = 2250 (12비트 필요)
    wire [11:0] b_comp = b_in * 29;  // 15*29 = 435 (9비트 필요)

    // 덧셈 및 시프트 연산 (조합 논리)
    wire [11:0] sum = r_comp + g_comp + b_comp;
    wire [3:0] gray_val = sum >> 8; // 8비트 오른쪽 시프트로 256 나누기

    // FSM
    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE_ST;
            led_done_r <= 1'b0;
            we_buf1 <= 1'b0;
            rw_cntr <= 17'd0;
            rdaddr_buf1 <= 17'd0;
            wraddr_buf1 <= 17'd0;
        end else if (enable_filter && state == IDLE_ST) begin
            state <= START_BLACKWHITE_ST;
            rw_cntr <= 17'd0;
            we_buf1 <= 1'b1;
            led_done_r <= 1'b0;
            rdaddr_buf1 <= 17'd0;
            wraddr_buf1 <= 17'd0;
        end else begin
            case (state)
                START_BLACKWHITE_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                end

                GET_PIXEL_DATA_ST: begin
                    // 다음 클럭에 처리할 픽셀 데이터를 레지스터에 저장
                    din_buf1_reg <= din_buf1;
                    state <= PROCESS_PIXEL_ST;
                end

                PROCESS_PIXEL_ST: begin
                     // 변환된 흑백 값을 출력 레지스터에 할당
                    dout_buf1 <= {gray_val, gray_val, gray_val};
                    state <= SEND_PIXEL_DATA_ST;
                end

                SEND_PIXEL_DATA_ST: begin
                    if (rw_cntr < NUM_PIXELS) begin
                        state <= GET_PIXEL_DATA_ST;
                        rw_cntr <= rw_cntr + 1;
                        // 읽기/쓰기 주소를 동시에 증가
                        rdaddr_buf1 <= rdaddr_buf1 + 1;
                        wraddr_buf1 <= wraddr_buf1 + 1;
                    end else begin
                        state <= DONE_ST;
                    end
                end

                DONE_ST: begin
                    state <= DONE_ST;
                    led_done_r <= 1'b1;
                    we_buf1 <= 1'b0;
                end

                default: begin
                    state <= IDLE_ST;
                end
            endcase
        end
    end
endmodule
