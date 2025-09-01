module top_lcd (
input clk,
input rst_n,
input IRDA_RXD,
input lcd_button,

output lcd_rs, 
output lcd_en,
output lcd_rw,
output lcd_out_on,
output [7:0]lcd_data
);

wire [7:0]          captured_code;
reg [7:0]           input_data;
wire                ir_new_data_ready;   
reg [7:0]           data_for_lcd;

//assign ir_new_data_ready = ((data_for_lcd) != (captured_code));

LCD_1 U1(
	.lcd_data(lcd_data),                  			// lcd data
	.lcd_en(lcd_en),                        	 	// lcd enable
   .lcd_rw(lcd_rw),                          	// lcd read/write (write = 0, read = 1)     
   .lcd_rs(lcd_rs),                        	 	// Command/Data Select (Command = 0,Data = 1)
   .lcd_out_on(lcd_out_on),                    	// lcd power
   .input_data(input_data),							// lcd input data    .clk(clk),
   .rst_n(rst_n),
   .lcd_in_on(lcd_button)                      // lcd power on in (button)
    );
	 
	 
IR_RECEVER U2 (
    .clk(clk),          			// 50MHz 클럭 기준
    .rst_n(rst_n),
	.IRDA_RXD(IRDA_RXD),    		// IR 수신기 입력
	.captured_code(captured_code)  	// 최종 해독된 키 데이터 
);



//always @(posedge clk) begin
//	if (ir_new_data_ready) begin
//        data_for_lcd <= captured_code;  // 이 순간의 값을 붙잡아 둠 (Latching)
//    end
//end

always @(*) begin                      // 조합 논리임을 명시
    case (captured_code)
			8'h00: input_data = 8'h30; // '0'
			8'h01: input_data = 8'h31; // '1'
			8'h02: input_data = 8'h32; // '2'
			8'h03: input_data = 8'h33;
			8'h04: input_data = 8'h34;
			8'h05: input_data = 8'h35;
			8'h06: input_data = 8'h36;
			8'h07: input_data = 8'h37;
			8'h08: input_data = 8'h38;
			8'h09: input_data = 8'h39; // '9'
			8'h0F: input_data = 8'h41;
			8'h13: input_data = 8'h42;
			8'h10: input_data = 8'h43;
        default: input_data = 8'h20; // 기본값 (예: 스페이스)
    endcase
end

endmodule