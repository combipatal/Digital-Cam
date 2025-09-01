`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/08/28 10:05:07
// Design Name: 
// Module Name: lcd
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module lcd(
    output reg [7:0] lcd_data,                      // lcd data
    output reg lcd_en,                              // lcd enable
    output lcd_rw,                              // lcd read/write (write = 0, read = 1)     
    output reg lcd_rs,                          // Command/Data Select (Command = 0,Data = 1)
    output lcd_out_on,                          // lcd power on out (wire)
    
	 input [7:0]input_data,
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
   //8비트 데이터 모드, 2줄 표시, 5x8 도트 폰트로 설정합니다. LCD 초기화 시 가장 먼저 설정해야 합니다.
   // 0x80 + 주소 커서 위치 지정 (40µs)
   //커서를 원하는 위치로 이동시킵니다. 1번째 줄의 시작 주소는 0x00이고, 2번째 줄의 시작 주소는 0x40입니다.
  
  
   // ===================================================================
    // 출력 및 내부 신호 할당
    // ===================================================================
   assign lcd_out_on = lcd_in_on;
   assign lcd_rw = 0;
   
   // ===================================================================
   // 레지스터 및 와이어 선언
   // ===================================================================
   reg [3:0] state,next_state;
   reg [3:0] return_state;
   
   reg [19:0] delay_count;
   reg [19:0] delay_target_count;
	
	reg new_data;	// 새로운 데이터 판단
   
    // ===================================================================
    // 파라미터 정의
    // ===================================================================
    // FSM 상태 정의
   
   // 논리회로 상태  
   parameter IDLE = 4'b0000;                // 대기 상태
   parameter INIT_START = 4'b0001;          // 초기화 시작 
   parameter INIT_FUN_SET = 4'b0010;        // 기능 설정
   parameter INIT_DISPLAY_ON = 4'b0011;     // 화면 켜기
   parameter INIT_CLEAR = 4'b0100;          // 화면 지우기
   parameter INIT_ENTRY_MODE = 4'b0101;     // 입력 모드 설정
    
   parameter WRITE_POS = 4'b0110;           // 문자쓰기 위치지정
   parameter WRITE_DATA = 4'b0111;          // 문자쓰기 문자지정
   // 조합회로 상태
   parameter CMD_WRITE = 4'b1000;           // 명령어/데이터를 버스에 쓰는 상태 
   parameter EN_PULSE = 4'b1001;            // Enable 신호 pulse 발생
   parameter DELAY_WAIT =4'b1010;           // 지연 대기 상태
      
   // 50MHz 기준 delay 값 
   parameter delay_15ms = 20'd750000;       // 전원 켜진 후 초기 대기시간
   parameter delay_40us = 20'd2000;         // 
   parameter delay_2ms =  20'd100000;
  
  // 조합 회로 FSM 상태 변경 
  always @(*) begin 
    next_state = state;                     // 기본적으로 현재 상태 유지 (latch 형성 방지)
      case (state)
        // 전원이 켜지면 초기화 시작 
        IDLE : begin 
           if(!lcd_in_on) begin 
              next_state = INIT_START;
           end
        end
        // 명령어/데이터를 버스에 설정하고 EN_PULSE 상태로 이동
        CMD_WRITE : begin 
            next_state = EN_PULSE;                  
        end
        
        EN_PULSE : begin
            next_state = DELAY_WAIT;
        end
          
        DELAY_WAIT : begin 
            if(delay_count >= delay_target_count) begin
                next_state = return_state;
            end else begin
                next_state = DELAY_WAIT;
            end
        end
        // 초기화 및 문자 쓰기 상태들은 CMD_WRITE 상태로 이동하여 실제 전송 수행
        default : begin 
            next_state = CMD_WRITE;
        end
       endcase
   end
   reg [7:0]data_count;
	reg [7:0]pre_data;
   
  always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin 
            state <= IDLE;
            lcd_rs <= 1'b0;
            lcd_en<= 1'b0;
            lcd_data <= 1'b0;
            delay_target_count <= 20'b0;
				data_count = 0;
				pre_data <= 0;
        end else begin
            

            state <= next_state;
				
            if(state == DELAY_WAIT) begin
                delay_count <= delay_count + 1;
            end else begin
                delay_count <= 20'b0;
            end
            
            // 각 상태 에 따른 출력 정의 
            case (state)
                IDLE : begin
                    lcd_en <= 1'b0;
                end
                
                INIT_START : begin 
                    delay_target_count <= delay_15ms;
                    return_state <= INIT_FUN_SET;
                end
                
                INIT_FUN_SET : begin
                    lcd_rs <= 1'b0;
                    lcd_data <= 8'h38;                      // commnad data
                    delay_target_count <= delay_40us;       // delay time
                    return_state <= INIT_DISPLAY_ON;               // after delay count, next_state
                    //state <= delay_state;                   // next_state
                end
                
                INIT_DISPLAY_ON :begin
                    lcd_rs <= 1'b0;
                    lcd_data <= 8'h0c;
                    delay_target_count <= delay_40us;           // dalay time
                    return_state <= INIT_CLEAR;               // delay_state 후 next_state
                end
                            
                INIT_CLEAR : begin
                    lcd_rs <= 1'b0; 
                    lcd_data <= 8'h01;                       // command : clear_screen
                    delay_target_count <= delay_2ms;         // 2ms delay
                    return_state <= INIT_ENTRY_MODE;      	// delay 후 next_state
                end
                               
                INIT_ENTRY_MODE : begin
                    lcd_rs <= 1'b0;
                    lcd_data <= 8'h06;
                    delay_target_count <= delay_2ms;
                    return_state <= WRITE_POS;
                end
                // 커서 위치 지정
                WRITE_POS : begin               
                    lcd_rs <= 1'b0;
                    lcd_data <= 8'h80;          // 커서 위치
                    delay_target_count <= delay_40us;
                    return_state <= WRITE_DATA;
                end
                
                WRITE_DATA : begin
					 	lcd_rs <= 1'b1;
						if (pre_data != input_data) begin 
							lcd_data <= input_data;          // 출력 데이터
							pre_data <= input_data;
							delay_target_count <= delay_40us;
							return_state <= WRITE_POS;
						end
                end
                
                CMD_WRITE : begin 
                    lcd_en <= 1'b0;
                end
                EN_PULSE : begin 
                    lcd_en <= 1'b1;
                end
            endcase 
        end
    end 
    
endmodule

