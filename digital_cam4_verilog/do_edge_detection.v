// VHDL 소스 파일: do_edge_detection.vhd
// 프레임 버퍼에서 흑백 이미지를 읽어 Sobel 필터를 적용하고, 결과를 다시 버퍼에 씁니다.
// Verilog 문법 규칙(reg/wire)에 맞게 수정되고, 원본 VHDL과 동일하게 동작하도록 FSM 로직이 복원되었습니다.
module do_edge_detection (
    // Controls
    input wire          rst_i,
    input wire          clk_i, // 25 MHz
    input wire          enable_sobel_filter,
    output reg          led_sobel_done,

    // Frame Buffer 1 (Read from)
    output reg [16:0]   rdaddr_buf1,
    input wire [11:0]   din_buf1,

    // Frame Buffer 2 (Write to)
    output reg [16:0]   wraddr_buf2,
    output wire [11:0]  dout_buf2,
    output reg          we_buf2
);
    // FSM States
    localparam [2:0] S_IDLE        = 3'b110,
                     S_START_SOBEL = 3'b000,
                     S_GET_PIXEL   = 3'b001,
                     S_SEND_PIXEL  = 3'b100,
                     S_STALL_1     = 3'b010,
                     S_STALL_2     = 3'b011,
                     S_DONE        = 3'b101;
    // Constants
    localparam [16:0] NUM_PIXELS = 17'd76799;
    localparam [16:0] SOBEL_LATENCY = 17'd323;
    localparam [8:0]  COLS_MAX = 9'd319;

    // Internal Registers for FSM and control
    reg [16:0] rd_cntr = 0;
    reg [16:0] wr_cntr = 0;
    reg [2:0]  state = S_IDLE;
    reg [8:0]  ColsCounter = 0;
    reg        vsync_dummy, hsync_dummy;

    // Internal Wires for module connections
    wire [7:0] din_buf1_r;
    wire [7:0] dout_buf2_r;
    wire       vsync_delayed, hsync_delayed;

    // Continuous Assignments
    assign din_buf1_r = din_buf1[11:4]; // 12-bit gray input to 8-bit
    assign dout_buf2 = {dout_buf2_r[7:4], dout_buf2_r[7:4], dout_buf2_r[7:4]}; // Replicate 4-bit edge output to RGB444

    // Instantiate the Sobel filter wrapper
    edge_sobel_wrapper sobel_wrapper (
        .clk       (clk_i), // <-- 수정됨: clk_div2 -> clk_i
        .fsync_in  (vsync_dummy),
        .rsync_in  (hsync_dummy),
        .pdata_in  (din_buf1_r),
        .fsync_out (vsync_delayed),
        .rsync_out (hsync_delayed),
        .pdata_out (dout_buf2_r)
    );

    // Main FSM to control the edge detection process
    always @(posedge clk_i or posedge rst_i) begin // <-- 비동기 리셋으로 수정
        if (rst_i) begin
            state <= S_IDLE;
            led_sobel_done <= 1'b0;
            rd_cntr <= 0;
            wr_cntr <= 0;
            we_buf2 <= 1'b0;
            rdaddr_buf1 <= 0;
            wraddr_buf2 <= 0;
            vsync_dummy <= 1'b0;
            hsync_dummy <= 1'b0;
            ColsCounter <= 0;
        end else begin
            if (enable_sobel_filter && state == S_IDLE) begin
                state <= S_START_SOBEL;
                led_sobel_done <= 1'b0;
                rd_cntr <= 0;
                wr_cntr <= 0;
                we_buf2 <= 1'b0;
                rdaddr_buf1 <= 0;
                wraddr_buf2 <= 0;
                vsync_dummy <= 1'b1;
                hsync_dummy <= 1'b0;
                ColsCounter <= 0;
            end else begin
                case (state)
                    S_START_SOBEL: begin
                        state <= S_GET_PIXEL;
                    end

                    S_GET_PIXEL: begin
                        state <= S_SEND_PIXEL;
                        rdaddr_buf1 <= rdaddr_buf1 + 1;
                        if (rd_cntr > SOBEL_LATENCY) begin
                            we_buf2 <= 1'b1; // 쓰기 활성화
                            wraddr_buf2 <= wraddr_buf2 + 1;
                            wr_cntr <= wr_cntr + 1;
                        end
                    end

                    S_SEND_PIXEL: begin
                        rd_cntr <= rd_cntr + 1;
                        if (wr_cntr < NUM_PIXELS) begin
                            if (ColsCounter < COLS_MAX) begin
                                ColsCounter <= ColsCounter + 1;
                                hsync_dummy <= 1'b1;
                                state <= S_GET_PIXEL;
                            end else begin // End of a row
                                ColsCounter <= 0;
                                hsync_dummy <= 1'b0; // Insert a stall cycle for the wrapper
                                state <= S_STALL_1;
                            end
                        end else begin
                            state <= S_DONE;
                        end
                    end

                    S_STALL_1: begin
                        state <= S_STALL_2;
                    end

                    S_STALL_2: begin
                        state <= S_GET_PIXEL;
                        hsync_dummy <= 1'b1; // Start new row
                    end

                    S_DONE: begin
                        state <= S_DONE;
                        led_sobel_done <= 1'b1;
                        we_buf2 <= 1'b0; // Stop writing
                        vsync_dummy <= 1'b0;
                    end

                    default: begin // S_IDLE
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end
endmodule