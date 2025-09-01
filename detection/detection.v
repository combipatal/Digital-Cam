`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/08/23 23:59:21
// Design Name: 
// Module Name: detection
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
// 비트 단위로 입력되는 din_bit에서 비트 패턴 0110 이 검출되면 출력 detect_out = 1, 그렇지 않은 경우 0
//////////////////////////////////////////////////////////////////////////////////


module detection(
    input din_bit,
    input clk,
    input rst_n,
    output reg detect_out
    );
    //next_state
    reg [2:0] state;
    reg [2:0] next_state;
    
    parameter  start = 3'b000;
    parameter  st1 = 3'b001;
    parameter  st2 = 3'b010;
    parameter  st3 = 3'b011;
    parameter  st4 = 3'b100;    
    
   // clk_div CLK(.clk(clk), .clr_n(rst_n), .clk_enable(clk_1C));


    //다음 상태 결정
    always @(*) begin
        next_state = state;
        
        case (state)
            start : if(!din_bit) next_state = st1; 
            
				st1 : if(din_bit) next_state = st2;        // state = st0 이고 din = 1 이면 next_state = st1
            
				st2 : begin if(din_bit) next_state = st3;
                  else next_state = st1;end
            
				st3 : begin if(!din_bit) next_state = st4;
                  else next_state = start;end
            
				st4 : begin if (din_bit) next_state = st2;
                  else next_state = st1;end
						
            default : next_state = start;
        endcase
    end
    
    // 다음상태를 현재 상태에 입력
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n) begin
            state <= start; 
        end else begin 
				state <= next_state;
					if (next_state == st4) detect_out <= 1'b1;
					else detect_out <= 0;
				end
    end
    
endmodule
