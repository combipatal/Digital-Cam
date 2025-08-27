module top_sram(

	output we_n,						// write enable, 쓰기 신호
	output oe_n,						// output enable , 출력 신호
	output ce_n,						// chip enable 칩을 키는 신호
	output [7:0] addr_out,		// read/write address 
	output [9:0]led_out,
	output lb_n,
	output ub_n,
	
	inout [9:0] sram_dq,				// 읽고 출력할 data  					//SRAM IO

	input [9:0] data_in,				// 저장할 data							// sw[9:0]       10비트 data
	input [7:0] addr_in,				// 저장할 주소							// sw[19:10]	  10비트 주소
	input write_req,						// 쓰기 명령  							//button
	input read_req,						// 읽기 명령								//button
	input rst_n,							// reset									//button
	input clk);																			// clk



	wire [9:0]data_out;
	wire clk_enable;
	//clk_div CDIV(.clk(clk), .clr_n(rst_n), .clk_enable(clk_enable));




 sram SR(
	.we_n(we_n),											// write enable, 쓰기 신호			//SRAM WE
	.oe_n(oe_n),											// output enable , 출력 신호			//SRAM OE
	.ce_n(ce_n),											// chip enable 칩을 키는 신호		//SRAM CE
	.addr_out(addr_out),									// read/write address 				//SRAM ADDR
	.data_out(data_out),									// 출력할 data							//LED
	.lb_n(lb_n),
	.ub_n(ub_n),
	
	.sram_dq(sram_dq),									// 읽고 출력할 data  					//SRAM IO
		
	.data_in(data_in),									// 저장할 data							// sw[9:0]       10비트 data
	.addr_in(addr_in),									// 저장할 주소							// sw[17:10]	  10비트 주소
	.write_req(write_req),								// 쓰기 명령  							//button
	.read_req(read_req),									// 읽기 명령								//button
	.rst_n(rst_n),											// reset									//button
	.clk(clk));												// clk
	
	
	led #(.WIDTH(10)) LED(.led_in(data_out), .led_out(led_out));
	
	
endmodule