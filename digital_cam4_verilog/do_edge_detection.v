// 프레임 버퍼에서 데이터를 읽어 소벨 필터를 적용하고, 결과를 다시 버퍼에 쓰는 과정을 제어하는 FSM 모듈
// FSM과 메모리 제어는 25MHz 클럭(clk_i)으로,
// 연산량이 많은 소벨 필터 커널은 133MHz 클럭(clk_133_i)으로 동작하도록 수정되었습니다.

module do_edge_detection (
    // --- Controls ---
    input rst_i,
    input clk_i,                 // 25 MHz 클럭 (FSM 및 메모리 제어용)
    input clk_133_i,             // 133 MHz 클럭 (소벨 필터 연산용)
    input enable_sobel_filter,
    output led_sobel_done,

    // --- Frame Buffer 1 (Read) ---
    output reg [16:0] rdaddr_buf1,
    input [11:0] din_buf1,

    // --- Frame Buffer 2 (Write) ---
    output reg [16:0] wraddr_buf2,
    output [11:0] dout_buf2,
    output reg we_buf2
);
    // FSM 상태 정의
    localparam IDLE_ST               = 3'b110;
    localparam START_SOBEL_FILTER_ST = 3'b000;
    localparam GET_PIXEL_DATA_ST     = 3'b001;
    localparam SEND_PIXEL_DATA_ST    = 3'b100;
    localparam STALL_1_CYCLE_ST      = 3'b010;
    localparam STALL_2_CYCLE_ST      = 3'b011;
    localparam DONE_ST               = 3'b101;
    
    // [오류 수정] 컴파일러가 계산식을 처리하지 못하는 경우를 대비해, 계산된 최종 값을 직접 사용합니다.
    localparam NUM_PIXELS = 17'd76799; // 320 * 240 - 1

    reg led_done_r = 1'b0;
    wire [7:0] din_buf1_r;
    wire [7:0] dout_buf2_r;

    reg [16:0] rd_cntr = 17'b0;
    reg [16:0] wr_cntr = 17'b0;
    reg [2:0] state = IDLE_ST;

    // 소벨 필터에 공급할 가상 동기화 신호
    reg hsync_dummy, vsync_dummy;
    reg [8:0] ColsCounter = 9'b0;

    assign led_sobel_done = led_done_r;

    // --- Data Path ---
    // 입력 데이터를 12비트 RGB에서 8비트 Grayscale로 변환
    // R, G, B가 모두 같은 값을 가지므로 Blue 채널만 사용
    assign din_buf1_r = {din_buf1[3:0], 4'b0};

    // 소벨 필터의 8비트 Grayscale 출력을 12비트 RGB로 다시 확장
    assign dout_buf2 = {dout_buf2_r[7:4], dout_buf2_r[7:4], dout_buf2_r[7:4]};

    // --- Module Instantiation ---
    edge_sobel_wrapper Inst_edge_sobel_wrapper (
        .clk(clk_133_i), // 소벨 필터는 고속 클럭으로 동작
        .fsync_in(vsync_dummy),
        .rsync_in(hsync_dummy),
        .pdata_in(din_buf1_r),
        .pdata_out(dout_buf2_r)
        // fsync_out, rsync_out은 현재 설계에서 사용되지 않음
    );

    // --- FSM (Controls memory access and sync signals) ---
    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE_ST;
            led_done_r <= 1'b0;
            rd_cntr <= 17'b0;
            wr_cntr <= 17'b0;
            we_buf2 <= 1'b0;
            rdaddr_buf1 <= 17'b0;
            wraddr_buf2 <= 17'b0;
            vsync_dummy <= 1'b0;
            hsync_dummy <= 1'b0;
            ColsCounter <= 9'b0;
        end else if (enable_sobel_filter && state == IDLE_ST) begin
            state <= START_SOBEL_FILTER_ST;
            // FSM 시작 시 초기값 설정
            led_done_r <= 1'b0;
            rd_cntr <= 17'b0;
            wr_cntr <= 17'b0;
            we_buf2 <= 1'b0; // 쓰기 활성화는 파이프라인 지연 후 시작
            rdaddr_buf1 <= 17'b0;
            wraddr_buf2 <= 17'b0;
            vsync_dummy <= 1'b1;
            hsync_dummy <= 1'b0; // 첫 사이클은 0으로 시작
            ColsCounter <= 9'b0;
        end else begin
            case (state)
                START_SOBEL_FILTER_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    hsync_dummy <= 1'b1; // 데이터 전송 시작
                end

                GET_PIXEL_DATA_ST: begin
                    state <= SEND_PIXEL_DATA_ST;
                    rdaddr_buf1 <= rdaddr_buf1 + 1;

                    // 소벨 필터 파이프라인 지연(약 323 클럭) 후 쓰기 시작
                    if (rd_cntr > 323) begin
                        we_buf2 <= 1'b1;
                        wraddr_buf2 <= wraddr_buf2 + 1;
                        wr_cntr <= wr_cntr + 1;
                    end
                end

                SEND_PIXEL_DATA_ST: begin
                    if (wr_cntr < NUM_PIXELS) begin
                        rd_cntr <= rd_cntr + 1;

                        if (ColsCounter < 319) begin
                            ColsCounter <= ColsCounter + 1;
                            state <= GET_PIXEL_DATA_ST;
                        end else begin
                            // 한 라인이 끝나면 hsync를 1클럭 동안 0으로 내려 동기화
                            ColsCounter <= 9'b0;
                            hsync_dummy <= 1'b0;
                            state <= STALL_1_CYCLE_ST;
                        end
                    end else begin
                        state <= DONE_ST;
                    end
                end
                
                // hsync_dummy를 0으로 유지하기 위한 Stall 상태 (총 2클럭)
                STALL_1_CYCLE_ST: begin
                    state <= STALL_2_CYCLE_ST;
                end
                
                STALL_2_CYCLE_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    hsync_dummy <= 1'b1; // 다음 라인 시작
                end

                DONE_ST: begin
                    state <= DONE_ST;
                    led_done_r <= 1'b1;
                    we_buf2 <= 1'b0;
                    vsync_dummy <= 1'b0;
                    hsync_dummy <= 1'b0;
                end

                default: begin
                    state <= IDLE_ST;
                end
            endcase
        end
    end

endmodule

