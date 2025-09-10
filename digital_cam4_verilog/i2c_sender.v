// OV7670 카메라에 I2C 유사 프로토콜로 레지스터 값을 전송하는 모듈
// resend 스위치와 연동되는 리셋 로직이 추가되었습니다.

module i2c_sender (
    input clk,
    input reset, // [추가] 외부 리셋 신호
    inout siod,
    output reg sioc,
    output reg taken,
    input send,
    input [7:0] id,
    input [7:0] reg_addr,
    input [7:0] value
);

    reg [7:0] divider = 8'd1;
    reg [31:0] busy_sr = 32'b0;
    reg [31:0] data_sr = 32'hFFFFFFFF;

    // siod는 busy_sr의 특정 상태에 따라 High-Z(입력) 또는 출력으로 제어됨
    assign siod = (busy_sr[11:10] == 2'b10 || busy_sr[20:19] == 2'b10 || busy_sr[29:28] == 2'b10) ? 1'bz : data_sr[31];

    always @(posedge clk) begin
        // [추가] 리셋 신호가 들어오면 모든 상태를 초기값으로 되돌림
        if (reset) begin
            divider <= 8'd1;
            busy_sr <= 32'b0;
            data_sr <= 32'hFFFFFFFF;
            taken <= 1'b0;
            sioc <= 1'b1;
        end else begin
            taken <= 1'b0;
            if (!busy_sr[31]) begin
                sioc <= 1'b1;
                if (send) begin
                    if (divider == 8'd0) begin
                        // 데이터와 제어 비트를 시프트 레지스터에 로드
                        data_sr <= {1'b1, 2'b0, id, 1'b0, reg_addr, 1'b0, value, 1'b0, 2'b01};
                        busy_sr <= 32'hFFFFFFFF;
                        taken <= 1'b1;
                    end else begin
                        divider <= divider - 1; // 파워업 시 초기 딜레이
                    end
                end
            end else begin
                // I2C 타이밍에 맞춰 sioc 클럭 생성 및 데이터 시프트
                case ({busy_sr[31:29], busy_sr[2:0]})
                    6'b111111, 6'b111110, 6'b111100: sioc <= (divider[7:6] == 2'b11) ? 1'b0 : 1'b1;
                    6'b110000, 6'b100000: sioc <= (divider[7:6] == 2'b00) ? 1'b0 : 1'b1;
                    6'b000000: sioc <= 1'b1;
                    default:   sioc <= (divider[7:6] == 2'b01 || divider[7:6] == 2'b10) ? 1'b1 : 1'b0;
                endcase

                if (divider == 8'hFF) begin
                    busy_sr <= {busy_sr[30:0], 1'b0};
                    data_sr <= {data_sr[30:0], 1'b1};
                    divider <= 8'b0;
                end else begin
                    divider <= divider + 1;
                end
            end
        end
    end

endmodule

