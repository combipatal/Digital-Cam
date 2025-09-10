// 주소 생성기 모듈
// 비디오 프레임 버퍼의 픽셀 주소를 순차적으로 생성합니다.

module Address_Generator (
    input rst_i,   // 리셋 입력 (액티브 하이)
    input CLK25,   // 25 MHz 클럭
    input enable,  // 주소 생성 인에이블
    input vsync,   // 수직 동기화 신호
    output [16:0] address // 생성된 17비트 주소
);
    // VHDL 코드의 val 신호에 해당하는 레지스터
    reg [16:0] val = 17'd0;

    // 생성된 주소는 val 레지스터의 값을 가집니다.
    assign address = val;

    // 320x240 이미지의 총 픽셀 수
    localparam MAX_VAL = 320 * 240;

    // CLK25의 상승 엣지에서 동작하는 프로세스
    always @(posedge CLK25) begin
        if (rst_i) begin
            val <= 17'd0;
        // VHDL 코드에서 vsync 리셋이 우선순위가 높으므로 먼저 체크합니다.
        end else if (vsync == 1'b0) begin
            val <= 17'd0;
        end else if (enable) begin
            // 메모리 공간을 모두 스캔하지 않았다면 주소를 1 증가시킵니다.
            if (val < MAX_VAL) begin
                val <= val + 1;
            end
        end
    end

endmodule
