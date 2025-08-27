module led #(
	parameter WIDTH = 8 // LED 개수 8개 사용
	)(
	input [WIDTH-1:0]led_in,
	output [WIDTH-1:0] led_out
	);

	assign led_out = led_in;
endmodule