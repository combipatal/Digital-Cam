// time division
//clk_div CDIV(.clk(clk), .clr_n(clr_n), .clk_enable(clk_enable));
module clk_div (clk, clr_n, clk_enable);
	input clk, clr_n;
	output clk_enable;
	reg clk_enable;
	reg [26:0] clk_cnt;

always @(posedge clk or negedge clr_n)
	begin
		if(!clr_n)begin 											//reset
			clk_cnt <= 27'd0;
			clk_enable <= 1'b0;
		end
		else if (clk_cnt == 27'd25000000) begin				//	clk_cnt 5000을 카운트 했다면
					clk_cnt <= 27'd0;								// clk_cnt 를 초기화 하고
					clk_enable <= 1'b1;							// clk_enable 신호를 1로 수정 안정된 1clok cposedge 가 된다.
			 end
		
		else begin
				clk_cnt <= clk_cnt + 1'b1;						//clk_cnt 로 5000만번을 카운트 (1초)
				clk_enable <= 1'b0;								//카운트 동안 clk_enable = 0
		end
	end
endmodule