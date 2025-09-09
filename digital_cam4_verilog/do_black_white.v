// VHDL 소스 파일: do_black_white.vhd
// [최종 수정] 나눗셈을 시프트 연산으로 변경하고, 2-cycle 읽기 지연시간을 완벽히 보상

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

    // FSM 상태 정의 (2-cycle read latency 고려)
    localparam [2:0] IDLE_ST         = 3'b000,
                     START_BW_ST     = 3'b001,
                     READ_STALL_ST   = 3'b010, // 1 사이클 대기 상태 추가
                     READ_WRITE_ST   = 3'b011,
                     DONE_ST         = 3'b100;

    localparam [16:0] NUM_PIXELS = 17'd76799;

    reg led_done_r = 1'b0;
    reg [16:0] pixel_cntr = 17'd0;
    reg [2:0]  state = IDLE_ST;

    // 파이프라인 레지스터 (Read Latency 보상용)
    reg [11:0] din_buf1_reg;

    // 흑백 변환 로직
    wire [7:0] red, green, blue;
    wire [7:0] gray_value;
    wire [9:0] sum_rgb;

    assign red   = {4'b0000, din_buf1_reg[11:8]};
    assign green = {4'b0000, din_buf1_reg[7:4]};
    assign blue  = {4'b0000, din_buf1_reg[3:0]};
    
    assign sum_rgb = red + green + blue;
    // [수정됨] /3 나눗셈을 >>2 (나누기 4) 시프트 연산으로 변경
    assign gray_value = sum_rgb >> 2;

    always @(*) begin
        dout_buf1 = {gray_value[3:0], gray_value[3:0], gray_value[3:0]};
    end

    // FSM 로직 (수정됨)
    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            state <= IDLE_ST;
            led_done_r <= 1'b0;
            we_buf1 <= 1'b0;
            rdaddr_buf1 <= 0;
            wraddr_buf1 <= 0;
            pixel_cntr <= 0;
            din_buf1_reg <= 0;
        end else begin
            // 2사이클 지연을 위해, RAM에서 나온 데이터를 한 번 더 레지스터에 저장
            din_buf1_reg <= din_buf1;

            case (state)
                IDLE_ST: begin
                    we_buf1 <= 1'b0;
                    if (enable_filter) begin
                        state <= START_BW_ST;
                        pixel_cntr <= 0;
                        rdaddr_buf1 <= 0; // 첫 주소 설정
                        led_done_r <= 1'b0;
                    end
                end
                
                START_BW_ST: begin
                    // 0번 주소의 데이터를 읽기 시작 (데이터는 2사이클 뒤에 유효해짐)
                    rdaddr_buf1 <= rdaddr_buf1 + 1;
                    state <= READ_STALL_ST;
                end

                READ_STALL_ST: begin
                    // 1번 주소의 데이터를 읽는 중, 0번 데이터가 din_buf1_reg에 들어옴
                    rdaddr_buf1 <= rdaddr_buf1 + 1;
                    state <= READ_WRITE_ST;
                end
                
                READ_WRITE_ST: begin
                    // 2번 주소 데이터를 읽는 중, 0번 주소에 대한 계산 결과를 씀
                    we_buf1 <= 1'b1;
                    wraddr_buf1 <= pixel_cntr; // 현재 카운터 값 = 쓰기 주소
                    
                    if (pixel_cntr < NUM_PIXELS) begin
                        pixel_cntr <= pixel_cntr + 1;
                        rdaddr_buf1 <= rdaddr_buf1 + 1;
                    end else begin
                        state <= DONE_ST;
                    end
                end

                DONE_ST: begin
                    we_buf1 <= 1'b0;
                    led_done_r <= 1'b1;
                    state <= DONE_ST;
                end
                
                default: state <= IDLE_ST;
            endcase
        end
    end

    assign led_done = led_done_r;
endmodule