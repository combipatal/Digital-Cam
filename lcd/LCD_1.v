`timescale 1ns/1ps

module LCD_1(
	output reg [7:0] lcd_data,                  	// lcd data
	output reg lcd_en,                         		// lcd enable
   output lcd_rw,                              // lcd read/write (write = 0, read = 1)     
   output reg lcd_rs,                          // Command/Data Select (Command = 0,Data = 1)
   output lcd_out_on,                          // lcd power
    
	input [7:0]input_data,								// lcd input data
   input clk,
   input rst_n,
   input lcd_in_on                             // lcd power on in (button)
    );


// lcd Command
   // 0x01 화면지우기 (2ms)
   // 0x02 커서 홈으로 (2ms)
   // 0x06 입력 모드 설정 (40us)
   // 0x0C 화면 켜기/끄기 (40us)  
   // 화면을 켜고, 커서는 보이지 않게, 커서 깜빡임도 끄도록 설정합니다. (D=1, C=0, B=0)
   // 0x0F 화면 켜기/끄기 (40µs)
   //화면을 켜고, 커서를 표시하며, 커서가 깜빡이도록 설정합니다. (D=1, C=1, B=1)
   // 0x38 기능 설정 (40µs)
   //8비트 데이터 모드, 2줄 표시, 5x8 도트 폰트로 설정합니다. 
   //LCD 초기화 시 가장 먼저 설정해야 합니다.
   // 0x80 + 주소 커서 위치 지정 (40µs)
   //커서를 원하는 위치로 이동시킵니다. 1번째 줄의 시작 주소는 0x00이고,
   //2번째 줄의 시작 주소는 0x40입니다.


	reg [3:0] state;					// 현재 state
	reg [3:0] return_state;			// delay 후 복귀할 state
	
	reg[7:0] data_save;				// 직전 input data 저장 ( 새로운 데이터만 입력받기 위함 ) 
	
	reg[19:0] count;					// 현재 delay count
	reg[19:0] delay_target_count;	// 목표하는 delay time

	
	parameter IDLE = 4'b0000;                // 대기 상태
	parameter INIT_START = 4'b0001;          // 초기화 시작 
	parameter INIT_FUN_SET = 4'b0010;        // 기능 설정
	parameter INIT_DISPLAY_ON = 4'b0011;     // 화면 켜기
	parameter INIT_CLEAR = 4'b0100;          // 화면 지우기
	parameter INIT_ENTRY_MODE = 4'b0101;     // 입력 모드 설정
	parameter WRITE_POS = 4'b0110;           // 문자쓰기 위치지정
	//parameter WRITE_DATA_READY = 4'b0111;	// data 출력 준비
	parameter WRITE_DATA = 4'b1000;          // 문자쓰기 문자지정
	parameter DELAY_WAIT =4'b1001;           // 지연 대기 상태
    
	// 50MHz 기준 delay 값 
	parameter delay_15ms = 20'd750000;       // 전원 켜진 후 초기 대기시간
	parameter delay_40us = 20'd2000;         //
	parameter delay_2ms =  20'd100000;

	assign lcd_out_on = lcd_in_on; // 외부 입력 신호를 lcd on 신호와 연결
	assign lcd_rw = 0; // writer 기능만 사용

	
	//순차회로
	always @(posedge clk or negedge rst_n ) begin 
		if(!rst_n) begin 
			state <= IDLE;
			lcd_rs <= 0;
			lcd_data <= 0;
			lcd_en <= 0;
			count <= 0;
			delay_target_count <= 0;
			data_save <= 0;
		end else begin 
			
			case (state) 
			
				IDLE : begin 
					if (!lcd_in_on) begin 
						state <= INIT_START;
					end else begin 
						state <= IDLE;
					end
				end
				
				INIT_START : begin 
					delay_target_count <= delay_15ms;	// 15ms 딜레이
					state <= DELAY_WAIT;
					return_state <= INIT_FUN_SET;
					lcd_rs <= 0;						//Command
				end
				
				INIT_FUN_SET : begin 
					lcd_data <= 8'h38;					//기능 설정
					delay_target_count <= delay_40us;	//40us delay
					state <= DELAY_WAIT;
					return_state <= INIT_CLEAR;
					lcd_rs <= 0;						//Command
					lcd_en <= 1;						// falling edge를 만들어야함
				end
				
				INIT_CLEAR : begin 
					lcd_data <= 8'h01;					//화면지우기
					delay_target_count <= delay_2ms;	//2ms delay
					state <= DELAY_WAIT;
					return_state <= INIT_ENTRY_MODE;
					lcd_rs <= 0;						//Command
					lcd_en <= 1;
				end
				
				INIT_ENTRY_MODE : begin 
					lcd_data <= 8'h06;					//입력 모드 설정 
					delay_target_count <= delay_40us;	//40us delay
					return_state <= WRITE_POS;
					state <= DELAY_WAIT;	
					lcd_rs <= 0;						//Command
					lcd_en <= 1;
				end
				
				WRITE_POS : begin 
					lcd_data <= 8'h80;						//0x80 + 주소 ,커서 위치 지정
					delay_target_count <= delay_40us; 	//40us delay;
					return_state <= WRITE_DATA;
					state <= DELAY_WAIT;
					lcd_en <= 1;
				end
				
//				WRITE_DATA_READY : begin				// data 출력전 data 정리
//					lcd_data <= 0;
//					lcd_rs <= 1'b1;
//					delay_target_count <= delay_40us;
//					state <= DELAY_WAIT;
//					return_state <= WRITE_DATA;
//				end
				
				WRITE_DATA : begin 
					if (data_save != input_data)begin 
						lcd_data <= input_data;					// data 출력 
						data_save <= input_data;
						delay_target_count <= delay_2ms;	//40us delay
						state <= DELAY_WAIT;
						return_state <= WRITE_DATA;
						lcd_en <= 1;
						lcd_rs <= 1;
					end
				end
					
				DELAY_WAIT : begin 							// delay counter
					lcd_en <= 0;
					if ( count < delay_target_count ) begin 
						count <= count + 1;
						state <= DELAY_WAIT;
					end else begin 
						state <= return_state;
						count <= 0;
						delay_target_count <= 0;
					end
				end
				
				default : state <= IDLE;

			endcase
		end
	end
endmodule