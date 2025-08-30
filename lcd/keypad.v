module keypad (
	input clk,
	input IRDA_RXD,						// IR Recevier
	output reg [7:0]key_data		// 읽어들인 데이터
	);
	
	
	
	// 1. 펄스해석기 -> 16bit 데이터를 확보 후 다음 단계로
	// 2. fsm (IDLE, Guidance, Data_read)
	
	//현재입력값과 과거의 입력값을 비교하여 negedge를 구별해야한다.
	// negedge 일 때 카운터를 시작하여 posedge일 때 타이머 종료 -> 시간 계산
	// 시간 범위로 데이터 판별 ( 9ms(start), 565us(mark)) -> read data 로 데이타를 reg 로 저장
	// 다시 rising edge 부터 falling edge 까지 타이머 -> space 측정
	// 카운트 시간이 565us 라면 0 비트 , 1.6875ms 라면 1비트
	
	
	// 먼저 32비트 신호를 read data 에 저장을 한 후 데이터 값을 판단하는 곳에서 벡터로 확인하는 방식
	
	
	reg [31:0] read_data;
	reg [1:0] EX_data;
	reg [19:0]count_time;

	
	reg [4:0] bit_count;
	
	
	reg [3:0] state;
	reg [3:0] next_state;
	reg [15:0] COUSTOM_CODE;
	
	parameter IDLE = 4'b0000;
	parameter MEASURE_MARK = 4'b0001;
	parameter MEASURE_SPACE = 4'b0010;
	parameter COUNT = 4'b0011;
	parameter WAIT_ENDCODE = 4'b0100;
	parameter RECV_CUSTOM = 4'b0101;
	parameter VERIFY_AND_FINISH = 4'b0110;
	parameter DATA_OUT = 4'b0111;
	
	always @(*) begin
		EX_data <= EX_data << 1'b1;
		EX_data [0] = IRDA_RXD;
		
		case (state)
			IDLE : begin 
				if (EX_data [1] && !EX_data[0]) begin
					next_state = MEASURE_MARK;
					count_time = 0;
					read_data = 0;
					bit_count = 0;
				end
			end
			
			RECV_CUSTOM : begin
				if (bit_count <= 32) begin
					next_state = COUNT;
				end else begin
					next_state <= WAIT_ENDCODE;
				end
			end
			
			default : next_state <= IDLE;
		endcase
	end
	
	
	
	
	
	always @(posedge clk) begin 
		
		state <= next_state;				// 현재상태 -> 다음 상태로 
		
		case (state)
			
//			IDLE : begin																// falling edge 일 때 measure_mark 로 이동 
//				next_state <= IDLE;
//			end
			
			MEASURE_MARK : begin														// LOW signal count
				
				if ( EX_data [0] == 1'b0 ) begin
					count_time <= count_time + 1'b1;
				end else begin
					if ((20'd445000) < count_time < (20'd455000)) begin					// ms 수정 !
						next_state <= MEASURE_SPACE;
						count_time <= 1'b0;											// LOW 시간을 판단해서 mark 판단 -> 9ms 라면 MEASURE_SPACE 로
					end else begin
						next_state <= IDLE;											// if 
						count_time <= 1'b0;
					end
				end
			end
								
			MEASURE_SPACE : begin													// LOW 가 9ms 를 판단한 후 HIGH 가 4.5ms 인지 판단 -> 안정성 향상
				
				if ( EX_data [0] == 1'b1) begin
					count_time <= count_time + 1'b1;
				end else begin
					if ((20'd220000) < count_time < (20'd230000)) begin
						next_state <= COUNT;
						count_time <= 1'b0;
					end else begin
						next_state <= IDLE;
						count_time <= 1'b0;
					end
				end
			end
			
			COUNT : begin
				if (EX_data[0] == 1) begin											//신호가 high 일 때 측정해서 space의 간격을 파악
					count_time <= count_time + 1'b1;								
				end else begin
					
					bit_count <= bit_count + 1'b1;								//32비트을 읽기 위해 32번 반복		
					
					if ( 20'd28000 < count_time < 20'd28500 ) begin					// 읽은 비트 값 판단
						read_data <= {read_data[31:0],1'b0};
						count_time <= 0;
					end else if (20'd84000 < count_time < 20'd85500) begin
						read_data = {read_data[31:0],1'b1};
						count_time <= 0;
					end else begin
						next_state <= IDLE;
						count_time <= 0;
					end
				end
			end	
			
			WAIT_ENDCODE : begin
				if (EX_data[0] == 1'b0) begin
					count_time <= count_time + 1;
				end else begin
					if ( 20'd28000 < count_time < 20'd28500 ) begin	
						next_state <= RECV_CUSTOM;
					end else begin
						next_state <= IDLE;
					end
				end
			end
										
			RECV_CUSTOM : begin					// Rising signal 판단 해야한다. custom key 16bit 수신 후 확인 -> 16비트 -> 펄스해석기
				
				if (read_data[31:16] == COUSTOM_CODE) begin 
					next_state <= VERIFY_AND_FINISH;
				end else begin
					next_state <= IDLE;
				end
			end
		
			
			VERIFY_AND_FINISH : begin 
				if (read_data[15:8] != read_data[7:0]) begin					// data 와 inv data 비교 
					next_state <= DATA_OUT;
				end else begin 
					next_state <= IDLE;
				end
			end
			
			DATA_OUT : begin 
				key_data <= read_data [15:8];
			end
				
			
			
			default : next_state <= IDLE;
		endcase 
	end
	
	
	endmodule