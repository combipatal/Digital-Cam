`timescale 1ns / 1ps

module sobel_convolution(	
	input wire clk,rst_n,
	input wire[15:0] din, //data from camera fifo
	input wire data_available, //data from camera fifo is now available UNTIL the next rising edge
	input wire rd_fifo, //sdram_interface will now start retrieving data from asyn_fifo
	output reg rd_en,//read camera fifo
	output wire[7:0] dout //data to be stored in sdram
	// data_count_r 제거 (DCFIFO IP에서 제공하지 않음)
    );
	 
	 //FSM for combining the kernels which will then be stored in asyn_fifo
	 localparam init=0,
					loop=1;
					
	 reg state_q,state_d;
	 reg signed[7:0] temp1_q,temp2_q,temp3_q;
	 reg[10:0] pixel_counter_q=1920;
	 reg first_line,second_line,third_line;
	 reg we_1,we_2,we_3,we_4,we_5,we_6;
	 reg signed[7:0] din_ram_x,din_ram_y;
	 reg[9:0] addr_a_x,addr_a_y,addr_b_q,addr_b_d;
	 reg write;
	 reg signed[7:0] data_write;
	 reg signed[7:0] x,y;
	 
	 wire temp_valid;
	 wire[7:0] gray;
	 wire signed[7:0] dout_1,dout_2,dout_3,dout_4,dout_5,dout_6;
	 
	 // RGB565에서 RGB 추출
	 wire[7:0] r, g, b;
	 assign r = {din[15:11], din[15:13]}; // 5비트를 8비트로 확장
	 assign g = {din[10:5], din[10:9]};   // 6비트를 8비트로 확장  
	 assign b = {din[4:0], din[4:2]};     // 5비트를 8비트로 확장
	 
	 // RGB to Grayscale 변환 (ITU-R BT.601 표준)
	 assign gray = (r * 76 + g * 150 + b * 29) >> 8; // Y = 0.299R + 0.587G + 0.114B
	 
	 wire[15:0] sobel_fifo_out; // DCFIFO 16비트 출력
	 
	 // 16비트에서 하위 8비트만 사용
	 assign dout = sobel_fifo_out[7:0];
 
	 //register operation
	 always @(posedge clk,negedge rst_n) begin
		if(!rst_n) begin
			temp1_q<=0;
			temp2_q<=0;
			temp3_q<=0;
			state_q<=0;
			pixel_counter_q<=1920;
			addr_b_q<=0;
		end
		else begin
			state_q<=state_d;
			rd_en=0;
			addr_b_q<=addr_b_d;
			if(data_available) begin //grouping every three pixels for the kernel convolution
				temp1_q<={3'b000,gray};
				temp2_q<=temp1_q;
				temp3_q<=temp2_q;
				pixel_counter_q<=(pixel_counter_q==1919 || pixel_counter_q==1920)? 0:pixel_counter_q+1'b1; //3 lines of pixel(640*3=1920)
				rd_en=1;
			end
		end
	 end
	 
	 //Convolution pipeline logic
	//data will be stored in block ram(which will be retrieved later by asyn_fifo)
	 always @* begin
		we_1=0;
		we_2=0;
		we_3=0;
		we_4=0;
		we_5=0;
		we_6=0;
		
		din_ram_x=0; 
		addr_a_x=0;
		din_ram_y=0;
		addr_a_y=0;
		
		if(pixel_counter_q!=1920) begin //data is now ready for convolution
			if(first_line) begin //convolution for the first row of the 3x3 kernel
				we_1=1;
				addr_a_y= pixel_counter_q;
				we_4=1;
				addr_a_x = pixel_counter_q;
			end
			
			else if(second_line) begin //convolution for the second row of the 3x3 kernel
				we_2=1;
				addr_a_y= pixel_counter_q-640;
				we_5=1;
				addr_a_x = pixel_counter_q-640;
			end
			
			else if(third_line) begin //convolution for the third row of the 3x3 kernel
				we_3=1;
				addr_a_y= pixel_counter_q-1280;
				we_6=1;
				addr_a_x = pixel_counter_q-1280;
			end
			din_ram_y= temp1_q + temp2_q + temp3_q; //Y kernel
			din_ram_x = -temp3_q + temp1_q; //X kernel
		end
		
	 end
	 
	 //Finalize convolution by combining both kernels then store the result in asyn_fifo
	 always @* begin
		write=0;
		data_write=0;
		x=0;
		y=0;
		addr_b_d=addr_b_q;
		state_d=state_q;
		
		case(state_q)
			init: if(pixel_counter_q==0 && data_available) begin //no data yet
						addr_b_d=0;
						state_d=loop;			
					end
			loop: if(data_available) begin
						addr_b_d=pixel_counter_q;
						if(first_line) begin
							addr_b_d=addr_b_d;
							y=dout_1-dout_2; //convolution result for y kernel
						end
						else if(second_line) begin
							addr_b_d=addr_b_d-640;
							y=dout_2-dout_3; //convolution result for y kernel
						end
						else if(third_line) begin
							addr_b_d=addr_b_d-1280;
							y=dout_3-dout_1; //convolution result for y kernel
						end
						
						x= dout_4 + dout_5 + dout_6; //convolution result for x kernel
						write=1;
						if(x[7]) x=-x; //get absolute value of x since convolution result CAN BE NEGATIVE
						if(y[7]) y=-y; //get absolute value of y since convolution result CAN BE NEGATIVE 
						data_write=x+y; //just take the sum since getting the quadratic sum will make this unnecessarily complicated(BUT QUADRATIC SUM IS THE CORRECT WAY)
						
					end
		default: state_d=init;
		endcase 
	 end
	 
	 
	 
	 always @* begin //determines which pixel line the next data will be stored
		first_line=0;
		second_line=0; 
		third_line=0;
		if(pixel_counter_q<=639) first_line=1;
		else if(pixel_counter_q<=1279) second_line=1;
		else if(pixel_counter_q<=1919) third_line=1;
	 
	 end
	 
	 
	 //module instantiations
	 dual_port_sync m0 //Matrix Y convolution row 1 - Altera IP
	(
		.wrclock(clk),
		.rdclock(clk),
		.wren(we_1),
		.data(din_ram_y),
		.wraddress(addr_a_y), //write address
		.rdaddress(addr_b_d), //read address 
		.q(dout_1)
	);
	
	dual_port_sync m1 //Matrix Y convolution row 2 - Altera IP
	(
		.wrclock(clk),
		.rdclock(clk),
		.wren(we_2),
		.data(din_ram_y),
		.wraddress(addr_a_y), //write address
		.rdaddress(addr_b_d), //read address 
		.q(dout_2)
	);
	
	dual_port_sync m2 //Matrix Y convolution row 3 - Altera IP
	(
		.wrclock(clk),
		.rdclock(clk),
		.wren(we_3),
		.data(din_ram_y),
		.wraddress(addr_a_y), //write address
		.rdaddress(addr_b_d), //read address
		.q(dout_3)
	);
	
	dual_port_sync m3 //Matrix X convolution row 1 - Altera IP
	(
		.wrclock(clk),
		.rdclock(clk),
		.wren(we_4),
		.data(din_ram_x),
		.wraddress(addr_a_x), //write address
		.rdaddress(addr_b_d), //read address 
		.q(dout_4)
	);
	
	dual_port_sync m4  //Matrix X convolution row 2 - Altera IP
	(
		.wrclock(clk),
		.rdclock(clk),
		.wren(we_5),
		.data(din_ram_x),
		.wraddress(addr_a_x), //write address
		.rdaddress(addr_b_d), //read address ,addr_b is already buffered inside this module so we will use the "_d" ptr to advance the data(not "_q")
		.q(dout_5)
	);
	
	dual_port_sync m5  //Matrix X convolution row 3 - Altera IP
	(
		.wrclock(clk),
		.rdclock(clk),
		.wren(we_6),
		.data(din_ram_x),
		.wraddress(addr_a_x), //write address
		.rdaddress(addr_b_d), //read address ,addr_b is already buffered inside this module so we will use the "_d" ptr to advance the data(not "_q")
		.q(dout_6)
	);
	
	// Sobel FIFO도 DCFIFO IP로 교체 필요 - 8비트용 별도 IP 생성 필요
	// 또는 asyn_fifo를 16비트로 사용하고 상위 8비트는 무시
	asyn_fifo m6 //8비트 DCFIFO IP 또는 16비트 IP 재사용
	(
		.wrclk(clk),
		.rdclk(clk),
		.data({8'h00, data_write}), // 8비트를 16비트로 확장
		.wrreq(write),
		.rdreq(rd_fifo), 
		.q(sobel_fifo_out),          // 16비트 출력
		.wrfull(),
		.rdempty()
    );






endmodule
