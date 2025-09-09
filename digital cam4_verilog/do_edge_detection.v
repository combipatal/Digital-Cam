// VHDL 소스 파일: do_edge_detection.vhd
// 프레임 버퍼에서 흑백 이미지를 읽어 Sobel 필터를 적용하고 결과를 다시 버퍼에 씁니다.

module do_edge_detection (
    // Controls
    input wire          rst_i,
    input wire          clk_i, // 25 MHz
    input wire          enable_sobel_filter,
    output wire         led_sobel_done,
    // Frame Buffer 1 (Read)
    output reg [16:0]   rdaddr_buf1,
    input wire [11:0]   din_buf1,
    // Frame Buffer 2 (Write)
    output reg [16:0]   wraddr_buf2,
    output wire [11:0]  dout_buf2,
    output reg          we_buf2
);

    // FSM 상태 정의
    localparam [2:0] IDLE_ST               = 3'b110,
                     START_SOBEL_FILTER_ST = 3'b000,
                     GET_PIXEL_DATA_ST     = 3'b001,
                     STALL_1_CYCLE_ST      = 3'b010,
                     STALL_2_CYCLE_ST      = 3'b011,
                     SEND_PIXEL_DATA_ST    = 3'b100,
                     DONE_ST               = 3'b101;
                     
    // 320x240 = 76800 pixels
    localparam [16:0] NUM_PIXELS = 17'd76799;
    localparam [16:0] SOBEL_LATENCY = 17'd323; // Sobel 파이프라인 지연 (W+2 for 3x3)
    localparam [8:0] COLS = 9'd319;

    // 내부 신호 및 레지스터
    reg         led_done_r = 1'b0;
    reg [16:0]  rd_cntr = 0;
    reg [16:0]  wr_cntr = 0;
    reg [2:0]   state = IDLE_ST;
    
    wire [7:0]  din_buf1_r;
    reg [7:0]   dout_buf2_r = 0;
    
    reg         vsync_dummy, hsync_dummy;
    wire        vsync_delayed, hsync_delayed;
    reg [8:0]   ColsCounter = 0;
    reg         clk_div2 = 0;
    
    assign led_sobel_done = led_done_r;

    // 입력 12비트(흑백)를 8비트로 변환 (Sobel 입력용)
    assign din_buf1_r = {din_buf1[3:0], 4'b0000}; 

    // 출력 8비트(에지)를 12비트로 변환 (버퍼 저장용)
    assign dout_buf2 = {dout_buf2_r[7:4], dout_buf2_r[7:4], dout_buf2_r[7:4]};

    // Sobel 필터 래퍼 인스턴스화
    edge_sobel_wrapper sobel_wrapper (
        .clk       (clk_div2),
        .fsync_in  (vsync_dummy),
        .rsync_in  (hsync_dummy),
        .pdata_in  (din_buf1_r),
        .fsync_out (vsync_delayed),
        .rsync_out (hsync_delayed),
        .pdata_out (dout_buf2_r)
    );

    // Sobel 래퍼에 공급할 클럭 분주기 (clk_i / 2)
    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            clk_div2 <= 1'b0;
        else
            clk_div2 <= ~clk_div2;
    end
   
    // FSM 로직: 픽셀 읽기/처리/쓰기 제어
    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE_ST;
            led_done_r <= 1'b0;
            rd_cntr <= 0;
            wr_cntr <= 0;
            we_buf2 <= 1'b0;
            rdaddr_buf1 <= 0;
            wraddr_buf2 <= 0;
            vsync_dummy <= 1'b0;
            hsync_dummy <= 1'b0;
            ColsCounter <= 0;
        end else if (enable_sobel_filter && state == IDLE_ST) begin
            state <= START_SOBEL_FILTER_ST;
            led_done_r <= 1'b0;
            rd_cntr <= 0;
            wr_cntr <= 0;
            we_buf2 <= 1'b1;
            rdaddr_buf1 <= 0;
            wraddr_buf2 <= 0;
            vsync_dummy <= 1'b1;
            hsync_dummy <= 1'b0;
            ColsCounter <= 0;
        end else begin
            case (state)
                START_SOBEL_FILTER_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    hsync_dummy <= 1'b0; // hsync 초기화
                end
                GET_PIXEL_DATA_ST: begin
                    state <= SEND_PIXEL_DATA_ST;
                    rdaddr_buf1 <= rdaddr_buf1 + 1;
                    if (rd_cntr > SOBEL_LATENCY) begin
                        wraddr_buf2 <= wraddr_buf2 + 1;
                        wr_cntr <= wr_cntr + 1;
                    end
                end
                SEND_PIXEL_DATA_ST: begin
                    if (wr_cntr < NUM_PIXELS) begin
                        rd_cntr <= rd_cntr + 1;
                        if (ColsCounter < COLS) begin
                            ColsCounter <= ColsCounter + 1;
                            hsync_dummy <= 1'b1;
                            state <= GET_PIXEL_DATA_ST;
                        end else begin
                            ColsCounter <= 0;
                            hsync_dummy <= 1'b0;
                            state <= STALL_1_CYCLE_ST;
                        end
                    end else begin
                        state <= DONE_ST;
                    end
                end
                STALL_1_CYCLE_ST: begin
                    state <= STALL_2_CYCLE_ST;
                end
                STALL_2_CYCLE_ST: begin
                    state <= GET_PIXEL_DATA_ST;
                    hsync_dummy <= 1'b1;
                end
                DONE_ST: begin
                    state <= DONE_ST;
                    led_done_r <= 1'b1;
                    we_buf2 <= 1'b0;
                end
                default: begin
                    state <= IDLE_ST;
                end
            endcase
        end
    end

endmodule

// 참고: edge_sobel_wrapper는 CacheSystem과 edge_sobel을 포함하는 래퍼 모듈입니다.
// module edge_sobel_wrapper(clk, fsync_in, rsync_in, pdata_in, fsync_out, rsync_out, pdata_out); ... endmodule
