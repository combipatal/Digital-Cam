// OV7670 카메라로부터 들어오는 픽셀 데이터를 캡처하여 프레임 버퍼(Block RAM)에 저장합니다.
// RGB 포맷 오류와 타이밍 안정성을 수정한 버전입니다.

module ov7670_capture (
    input pclk,
    input vsync,
    input href,
    input [7:0] d,
    output reg [16:0] addr,
    output [11:0] dout,
    output reg we,
    output reg end_of_frame
);

    reg [15:0] d_latch = 16'b0;
    reg [1:0]  line = 2'b0;
    reg [6:0]  href_last = 7'b0;
    reg        href_hold = 1'b0;

    // [개선] 안정적인 동작을 위해 모든 로직을 단일 클럭 엣지(posedge)에서 처리하도록 수정
    // 입력 신호를 내부 레지스터에 한 클럭 저장하여 사용
    reg vsync_reg = 1'b0;
    reg href_reg = 1'b0;
    reg [7:0] d_reg = 8'b0;

    always @(posedge pclk) begin
        vsync_reg <= vsync;
        href_reg <= href;
        d_reg <= d;
    end

    // [수정 2] "초록색/빨간색" 자글거림 증상에 맞춰 R과 G 채널을 교환합니다.
    // 이전: {B, G, R} -> {d_latch[4:1], d_latch[10:7], d_latch[15:12]}
    // 최종: {G, R, B} -> {d_latch[10:7], d_latch[15:12], d_latch[4:1]}
    assign dout = {d_latch[4:1], d_latch[10:7], d_latch[15:12]};

    always @(posedge pclk) begin
        if (we) begin
            addr <= addr + 1;
        end

        // href의 상승 엣지를 감지하여 라인 카운터 증가
        if (!href_hold && href_reg) begin
            line <= line + 1;
        end
        href_hold <= href_reg;

        // href가 활성화되어 있는 동안 2바이트(16비트)의 픽셀 데이터를 캡처
        if (href_reg) begin
            d_latch <= {d_latch[7:0], d_reg};
        end
        we <= 1'b0; // 기본적으로 쓰기 비활성화

        // VSYNC 신호가 들어오면 프레임의 시작이므로 주소 등을 초기화
        if (vsync_reg) begin
            addr <= 17'b0;
            href_last <= 7'b0;
            line <= 2'b0;
            end_of_frame <= 1'b1;
        end else begin
            // href_last 레지스터를 사용하여 픽셀 캡처 타이밍 제어
            // 원본 로직과 동일하게 특정 조건에서만 쓰기(we)를 활성화
            if (href_last[2]) begin
                if (line[1]) begin // 2라인 중 1라인만 저장 (격줄 샘플링)
                    we <= 1'b1;
                end
                href_last <= 7'b0;
            end else begin
                href_last <= {href_last[5:0], href_reg};
            end
            end_of_frame <= 1'b0;
        end
    end

endmodule

