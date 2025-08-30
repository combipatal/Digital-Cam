	module IR_time_delay (
		input clk,         	// 50MHz 클럭 기준
		input rst_n,
		input IRDA_RXD,     // IR 수신기 입력
		
		output reg [7:0] key_data,   // 최종 해독된 키 데이터
		output reg new_data_valid    // 새로운 데이터가 나왔음을 알리는 신호
	);

	wire [1:0] data_reg;
	
	reg [31:0] odata;
	reg [2:0] adress;
	reg [19:0] count;
	reg [1:0] count_data;


	assign data_reg = {data_reg[0],IRDA_RXD};



	always @(posedge clk or negedge rst_n) begin 
		
		if(!rst_n) begin
			count <= 1'b0;
			count_data <= 2'b0;
			adress <= 3'b0;
		end else begin 
		
			case (state)
				
				IDLE : begin	
					if (data_reg[1] && !data_reg[0]) begin				//falling edge
						state <= LEAD_MARK;
						adress <= 2'b01;
					end		
				end	
					
				LEAD_MARK : begin // LEAD_CODE
						if (count_data == 2'b01) begin
							if (data_reg[0] == 1'b0) begin
								state <= LEAD_SPACE;
								count_data <= 2'b0;
							end else begin 
								state <= IDLE;
								count_data <= 2'b0;
							end
						end else begin
							state <= LEAD_MARK;
						end
				end
							
				LEAD_SPACE : begin
						adress <= 2'b10;
						if (count_data == 2'b01) begin
							if (data_reg[0] == 1'b1) begin
								state <= DATA_SAVE;
								count_data <= 2'b0;
							end else begin
								state <= IDLE;
								count_data <= 2'b0;
							end
						end else begin
							state <= LEAD_SPACE;
						end
				end
				
				DATA_SAVE : begin			// 32bit data 저장 
						adress <= 3'b011;
						if ((count_data == 2'b10) && !(one_count == 2'b01)) begin
							data_565us <= data_reg[0];
							one_count <= one_count + 1;
						end else if (count_data == 2'b01 && one_count == 2'b01) begin
							data_4ms <= data_reg[0];
							one_count <= one_count + 1;
						end else if (one_count == 2'b10) begin 	// 오류발생 , case문으로 하면 편할듯 
							one_count <= 2'b0;
							count_32 <= count_32 + 5'b1;
							
							if (data_565us && data_4ms) begin
								odata <= {1'b1,odata[31:1]};
							end else if(data_565us && !(data_4ms)) begin
								odata <= {1'b0,odata[31:1]};
							end else if (count_32 == 5'd31) begin 
								state <= CUSTOM_CODE_CODE;
							end else	
								state <= IDLE;
								count_32 <= 0;
							end
						end
				end
				
				
				CUSTOM_CODE : begin
				
				DATA_VER : 
			endcase
		end
	end

	always @(posedge clk) begin		// 9ms 측정
		if (adress == 3'b01) begin
			if (count > 8.8ms ) begin 
				adress <= 2'b00;
				count_data <= 2'b01;
			end else begin 
				count <= count + 1;
			end
		end
	end

	always @(posedge clk) begin 
		if (adress == 3'b10) begin
			if(count > 4.3ms) begin 
				adress <= 2'b0;
				count_data <= 2'b01;
			end else begin 
				count <= count + 1;
			end
		end
	end

	always @(posedge clk) begin
		if (adress = 3'b011) begin
			if (count > 1.5ms) begin
				count_data <= 2'b01;
				adress = 3'b0;
			end else if((count > 565us) && !(count_data == 2'b10)) begin 	// 한번만 해야함
				count_data <= 2'b10;
				count <= count + 1;
			end else
				count <= count + 1;
			end	
		end
	end


endmodule		