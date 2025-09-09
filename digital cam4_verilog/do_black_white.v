// VHDL 소스 파일: do_black_white.vhd
// 프레임 버퍼 1의 내용을 읽어 흑백(grayscale) 필터를 적용하고 다시 버퍼 1에 씁니다.

module do_black_white (
    // Controls
    input wire          rst_i,
    input wire          clk_i, // 25 MHz
    input wire          enable_filter,
    output wire         led_done,
    // Frame Buffer 1 Interface
    output reg [16:0]   rdaddr_buf1,
    input wire [11:0]   din_buf1,
    output reg [16:0]   wraddr_buf1,
    output reg [11:0]   dout_buf1,
    output reg          we_buf1
);

    // FSM 상태 정의
    localparam [2:0] IDLE_ST              = 3'b101,
                     START_BLACKWHITE_ST  = 3'b000,
                     GET_PIXEL_DATA_ST    = 3'b001,
                     SEND_PIXEL_DATA_ST   = 3'b011,
                     DONE_ST              = 3'b100;
                     // WAIT_ACK_DIVISION_ST is not used for combinational divider
    
    // 320x240 = 76800 pixels
    localparam [16:0] NUM_PIXELS = 17'd76799;

    // 내부 신호 및 레지스터
    reg         led_done_r = 1'b0;
    reg [16:0]  rw_cntr = 17'd0;
    reg [2:0]   state = IDLE_ST;

    wire [7:0] red, green, blue;
    wire [7:0] gray_value;
    wire [9:0] sum_rgb;
    
    // 흑백 변환 로직: (R+G+B)/3
    // 입력 4비트를 8비트로 확장
    assign red   = {4'b0000, din_buf1[11:8]};
    assign green = {4'b0000, din_buf1[7:4]};
    assign blue  = {4'b0000, din_buf1[3:0]};
    
    assign sum_rgb = red + green + blue; 
    // 조합 논리 Divider (간단한 구현 예시, 실제로는 IP 사용 권장)
    assign gray_value = sum_rgb / 3; 
    
    always @(*) begin
        // 변환된 8비트 grayscale 값을 12비트 RGB444 포맷으로 변환 (모든 채널에 동일 값)
        dout_buf1 = {gray_value[3:0], gray_value[3:0], gray_value[3:0]};
    end

    // FSM 로직
    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE_ST;
            led_done_r <= 1'b0;
            we_buf1 <= 1'b0;
            rdaddr_buf1 <= 0;
            wraddr_buf1 <= 0;
            rw_cntr <= 0;
        end else begin
            case (state)
                IDLE_ST: begin
                    if (enable_filter) begin
                        state <= START_BLACKWHITE_ST;
                        rw_cntr <= 0;
                        we_buf1 <= 1'b1;
                        led_done_r <= 1'b0;
                        rdaddr_buf1 <= 0;
                        wraddr_buf1 <= 0;
                    end
                end
                START_BLACKWHITE_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    we_buf1 <= 1'b1;
                end
                GET_PIXEL_DATA_ST: begin
                    state <= SEND_PIXEL_DATA_ST;
                    rdaddr_buf1 <= rdaddr_buf1 + 1;
                    wraddr_buf1 <= wraddr_buf1 + 1;
                end
                SEND_PIXEL_DATA_ST: begin
                    if (rw_cntr < NUM_PIXELS) begin
                        state <= GET_PIXEL_DATA_ST;
                        rw_cntr <= rw_cntr + 1;
                    end else begin
                        state <= DONE_ST;
                    end
                end
                DONE_ST: begin
                    state <= DONE_ST; // Stay in DONE
                    led_done_r <= 1'b1;
                    we_buf1 <= 1'b0;
                end
                default: begin
                    state <= IDLE_ST;
                    led_done_r <= 1'b0;
                    we_buf1 <= 1'b0;
                end
            endcase
        end
    end

    assign led_done = led_done_r;

endmodule
