module sram(

	output reg we_n,						// write enable, 쓰기 신호
	output reg oe_n,						// output enable , 출력 신호
	output reg ce_n,						// chip enable 칩을 키는 신호
	output reg [7:0] addr_out,				// read/write address 
	output reg [9:0] data_out,				// 출력할 data
	output lb_n,
	output ub_n,
	
	inout [9:0] sram_dq,					// 읽고 출력할 data  
	
	input [9:0] data_in,					// 저장할 data
	input [7:0] addr_in,					// 저장할 주소
	input write_req,						// 쓰기 명령
	input read_req,							// 읽기 명령
	input rst_n,							// reset
	input clk);								// clk

	// 준비상태 -> we = 1, oe = 1, ce_n = 0	
	// fsm 
	// idle state -> setup_write (address & data 값을 설정 but we = 1)
	// -> execute_write (We = 0) -> finsh_write (we = 1)
		
	parameter IDEL = 3'b000;
	parameter SETUP_WRITE = 3'b001;
	parameter EXECUTE_WRITE = 3'b010;
	
	parameter SETUP_READ = 3'b100;
	parameter EXECUTE_READ = 3'b101;
	parameter CAPTURE_READ  = 3'b110;

	reg [2:0] state;															 		// 현재상태
	reg WR_signal;																		// Write 와 Read 구별 신호
	
	// sram_dq 가  write_signal 이 on 이라면 data_in을 입력하고, write_signal 이 off( read ) 라면 z를 유지하여 데이터를 받는다.
	reg write_dly;
	reg read_dly;
	
	assign lb_n = 1'b0;
	assign ub_n = 1'b0;
	
	wire write_save;
	wire read_save;
	
	
	always @(posedge clk or negedge rst_n)begin
		if (!rst_n) begin
			write_dly <= 1'b1;
			read_dly <= 1'b1;
		end else begin
			write_dly <= write_req;
			read_dly <= read_req;
		end
	end

	assign write_save = (write_dly && !write_req);
	assign read_save = (read_dly && !read_req);
			
			
			
	assign sram_dq = (WR_signal) ? data_in : 10'hzzz;						
	
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			state <= IDEL;
			we_n <= 1'b1;																// off
			oe_n <= 1'b1;																// off
			ce_n <= 1'b1;																// off
			WR_signal <= 1'b0;
			addr_out <= 8'b0;
			data_out <= 10'b0;
			
		end
		
		else begin										
				
			
			case (state)
			
				IDEL : begin
						we_n <= 1'b1;					//	we_n 이 1( off ), write_signal = 0 (off) 
						oe_n <= 1'b1;
						WR_signal <= 1'b0;
							ce_n <= 1'b1;													// chip_enable off
						if (write_save) begin
							state <= SETUP_WRITE;
							ce_n <= 1'b0;
						end else if(read_save) begin
							state <= SETUP_READ;
							ce_n <= 1'b0;
						end else
							state <= IDEL;
				end
				// WRITE 
				SETUP_WRITE : begin								// we_n = 1 ( off )  , WR_signal = 1 (write) 
						WR_signal <= 1'b1;						// assign sram_dq = date_in;
						addr_out <= addr_in;
						state <= EXECUTE_WRITE;
				end
				
				EXECUTE_WRITE : begin
						//WR_signal <= 1'b1;						// we_n = 0 ( on ) , WR_signal = 1 (write)	
						we_n <= 1'b0;
						//addr_out <= addr_in;
						state <= IDEL;
				end
				
				// READ 
				SETUP_READ : begin								//  바뀐 주소를 할당해주기 위한 1 clk지연
						addr_out <= addr_in;	
						//oe_n <= 1'b1;
						//WR_signal <= 1'b0;
						state <= EXECUTE_READ;
				end
				
				EXECUTE_READ : begin
						//addr_out <= addr_in;
						oe_n <= 1'b0;								// output enable on						
						WR_signal <= 1'b0;
						state <= CAPTURE_READ;
				end
				
				CAPTURE_READ : begin
						oe_n <= 1'b0;
						data_out <= sram_dq;
						state <= IDEL;								// data_out (reg) 에 sram_dq(wire) 대입
				end	

				
				default : state <= IDEL;
			endcase
		end
	end
endmodule
						