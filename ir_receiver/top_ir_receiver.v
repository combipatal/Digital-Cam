module top_ir_receiver (
	input clk,
	input rst_n,
	input IRDA_RXD,
	input lcd_in_on,
	 
	output [7:0]lcd_data,							// lcd에게 보내주는 데이터 lcd port연결
	output new_data_valid,					// 새로운 데이터가 나왔음을 알림 led 0
	output lcd_en,
	output lcd_rw,
	output lcd_rs,
	output lcd_out_on							// lcd input port
);

wire [7:0]key_data;

ir_receiver IR(
   .clk(clk),         						// 50MHz 클럭 기준
   .rst_n(rst_n),
	.IRDA_RXD(IRDA_RXD),     				// IR 수신기 입력 
   .key_data(key_data),  					// 최종 해독된 키 데이터 // lcd
   .new_data_valid(new_data_valid)    	// 새로운 데이터가 나왔음을 알리는 신호 // led
);


lcd LCD(
    .lcd_data(lcd_data),               // lcd data
    .lcd_en(lcd_en),                   // lcd enable
    .lcd_rw(lcd_rw),                   // lcd read/write (write = 0, read = 1)     
    .lcd_rs(lcd_rs),                   // Command/Data Select (Command = 0,Data = 1)
    .lcd_out_on(lcd_out_on),           // lcd power on out
    
	 .input_data(lcd_ascii_data),
    .clk(clk),    
    .rst_n(rst_n),
    .lcd_in_on(lcd_in_on)              // lcd power on in (button)
    );

	// ir_receiver 모듈에서 나온 최종 키 코드
// LCD로 보낼 최종 아스키코드 데이터
reg [7:0] lcd_ascii_data;

// 키 코드를 아스키코드로 변환하는 조합 회로 (번역기)
always @(*) begin
    case (key_data)
        // 리모컨 '1' 버튼의 키 코드가 8'h1C일 경우
        8'h01: lcd_ascii_data = 8'h61; // 문자 '1'의 아스키코드

        // 리모컨 '2' 버튼의 키 코드가 8'h1B일 경우
        8'h02: lcd_ascii_data = 8'h62; // 문자 '2'의 아스키코드

        // 리모컨 '7' 버튼의 키 코드가 8'h09일 경우
        8'h03: lcd_ascii_data = 8'h63; // 문자 '3'의 아스키코드
		  
		  8'h04: lcd_ascii_data = 8'h64; // 문자 '4'의 아스키코드
		  
		  8'h05: lcd_ascii_data = 8'h65; // 문자 '5'의 아스키코드
		  
		  8'h06: lcd_ascii_data = 8'h66; // 문자 '6'의 아스키코드
		  
		  8'h07: lcd_ascii_data = 8'h67; // 문자 '7'의 아스키코드
		  
		  8'h08: lcd_ascii_data = 8'h68; // 문자 '8'의 아스키코드
		  
		  8'h09: lcd_ascii_data = 8'h69; // 문자 '9'의 아스키코드
		  
		  8'h00: lcd_ascii_data = 8'h00; // 문자 '0'의 아스키코드
        
        default: lcd_ascii_data = 8'h20; // 모르는 코드가 들어오면 공백(' ') 표시
    endcase
end

// 이 lcd_ascii_data를 LCD 모듈의 데이터 입력으로 연결
	 

endmodule