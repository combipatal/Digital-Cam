// n비트 카운터
// 액티브 로우(Active-low) 비동기 리셋과 인에이블(enable) 신호를 가집니다.

module Counter #(
    parameter N = 9 // 카운터의 비트 수
)(
    input clk,          // 클럭 입력
    input en,           // 카운트 인에이블
    input reset,        // 비동기 액티브 로우 리셋
    output [N-1:0] output_val // 카운터 출력 값
);

    reg [N-1:0] num; // 카운터 값을 저장할 레지스터

    // clk의 상승 엣지 또는 reset의 하강 엣지에서 동작
    always @(posedge clk or negedge reset) begin
        if (!reset) begin // 리셋 신호가 '0'일 때 (액티브 로우)
            num <= {N{1'b0}}; // 카운터를 0으로 초기화
        end else if (en) begin // 인에이블 신호가 '1'일 때
            num <= num + 1; // 카운터 값을 1 증가
        end
    end

    // 출력 포트에 내부 레지스터 값을 지속적으로 할당
    assign output_val = num;

endmodule
