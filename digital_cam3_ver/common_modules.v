// 여러 간단한 모듈을 하나의 파일로 통합

// 디바운스 모듈
module debounce(
  input wire clk,
  input wire i,
  output reg o
);
  
  reg [23:0] c;

  always @(posedge clk) begin
    if (i) begin
      if (c == 24'hFFFFFF) begin
        o <= 1'b1;
      end else begin
        o <= 1'b0;
      end
      c <= c + 1;
    end else begin
      c <= 24'b0;
      o <= 1'b0;
    end
  end
endmodule

// RGB 모듈
module RGB(
  input wire [11:0] Din,
  input wire Nblank,
  output wire [7:0] R,
  output wire [7:0] G,
  output wire [7:0] B
);

  assign R = Nblank ? {Din[11:8], Din[11:8]} : 8'b0;
  assign G = Nblank ? {Din[7:4], Din[7:4]} : 8'b0;
  assign B = Nblank ? {Din[3:0], Din[3:0]} : 8'b0;

endmodule

// Counter 모듈
module Counter #(
  parameter n = 9
)(
  input wire clk,
  input wire en,
  input wire reset,  // Active Low
  output wire [n-1:0] output_count
);

  reg [n-1:0] num;

  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      num <= {n{1'b0}};
    end else if (en) begin
      num <= num + 1;
    end
  end

  assign output_count = num;
endmodule
