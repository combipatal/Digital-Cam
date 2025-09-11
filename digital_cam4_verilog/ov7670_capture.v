// ov7670_capture.v (수정본: HSYNC 기반, 640x480 VGA, RGB565 처리)

module ov7670_capture (
    input pclk,
    input vsync,
    input hsync,
    input [7:0] d,
    output reg [18:0] addr, // [수정] 640*480 = 307200. $clog2(307200)=19. 주소 폭 19비트로 변경
    output [15:0] dout,
    output reg we,
    output reg end_of_frame
);

    // 내부 레지스터
    reg [10:0] x_count = 0; // [수정] 수평 픽셀 카운터 (640 이상 카운트)
    reg [9:0]  y_count = 0; // [수정] 수직 라인 카운터 (480 이상 카운트)

    reg [7:0] d_reg = 8'b0;
    reg vsync_reg1 = 1'b0, vsync_reg2 = 1'b0;
    reg hsync_reg1 = 1'b0, hsync_reg2 = 1'b0;

    reg [7:0] byte1_buffer;
    reg       byte_received;

    assign dout = {byte1_buffer, d_reg};

    always @(posedge pclk) begin
        vsync_reg1 <= vsync;
        vsync_reg2 <= vsync_reg1;
        hsync_reg1 <= hsync;
        hsync_reg2 <= hsync_reg1;
        d_reg      <= d;

        // VSYNC의 상승 엣지(프레임 시작) 감지
        if (vsync_reg1 && !vsync_reg2) begin
            addr         <= 0;
            x_count      <= 0;
            y_count      <= 0;
            we           <= 0;
            byte_received <= 0;
            end_of_frame <= 1;
        end else begin
            end_of_frame <= 0;
            we           <= 0;

            // HSYNC의 상승 엣지(새로운 라인 시작) 감지
            if (hsync_reg1 && !hsync_reg2) begin
                x_count <= 0;
                y_count <= y_count + 1;
            end

            // [수정] 유효한 영상 영역 (640x480) 내에서만 데이터 캡처
            if (y_count < 480) begin
                if (!byte_received) begin
                    byte1_buffer  <= d_reg;
                    byte_received <= 1;
                end
                else begin
                    // [수정] 640 픽셀까지만 카운트하며 저장
                    if (x_count < 640) begin
                        addr          <= addr + 1;
                        we            <= 1;
                        x_count       <= x_count + 1;
                    end
                    byte_received <= 0;
                end
            end
        end
    end

endmodule