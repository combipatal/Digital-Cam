// 카운터 모듈
module Counter #(
  parameter n = 9  // 기본 크기
)(
  input wire clk,
  input wire en,
  input wire rst_n,  // 활성화 낮음 리셋 (0이면 리셋)
  output wire [n-1:0] output_count
);

  reg [n-1:0] num;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)       // 리셋이 활성화(낮음)되면 카운터 초기화
      num <= {n{1'b0}};
    else if (en)
      num <= num + 1'b1;
  end
  
  assign output_count = num;

endmodule