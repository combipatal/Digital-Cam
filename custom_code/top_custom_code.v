module top_custom_code (
	input clk,
	input rst_n,
	input IRDA_RXD,
	//input [7:0].input_data,
   input lcd_in_on,	
	
	output [6:0] seg_out_digit0,
	output [6:0] seg_out_digit1,

	 output [7:0]lcd_data,                  // lcd data
    output lcd_en,                          // lcd enable
    output lcd_rw,                              // lcd read/write (write = 0, read = 1)     
    output lcd_rs,                          // Command/Data Select (Command = 0,Data = 1)
    output lcd_out_on                          // lcd power on out 
	
);
wire [7:0] captured_code;
reg[7:0] input_data;

IR_RECEVER IR (
   .clk(clk),          // 50MHz 클럭 기준
   .rst_n(rst_n),
	.IRDA_RXD(IRDA_RXD),     // IR 수신기 입력
   .captured_code(captured_code)   // 최종 해독된 키 데이터
   //.new_data_valid(new_data_valid)	// 새로운 데이터가 나왔음을 알리는 신호
	//.led_1 (led_1),
	//.led_2 (led_2)
	);


lcd U2(
    .lcd_data(lcd_data),                      // lcd data
    .lcd_en(lcd_en),                            // lcd enable
    .lcd_rw(lcd_rw),                              // lcd read/write (write = 0, read = 1)     
    .lcd_rs(lcd_rs),                          // Command/Data Select (Command = 0,Data = 1)
    .lcd_out_on(lcd_out_on),                          // lcd power on out
    
	 .input_data(input_data),
    .clk(clk),    
    .rst_n(rst_n),
    .lcd_in_on(lcd_in_on)                             // lcd power on in (button)
);
	
// IR 수신기에서 나온 32비트 캡처 데이터

// 7세그먼트 각 자리에 연결될 출력 신호
//wire [6:0] seg_out_digit0, seg_out_digit1, seg_out_digit2, seg_out_digit2,seg_out_digit4, seg_out_digit5, seg_out_digit6, seg_out_digit7 ;

// 16진수의 첫 번째 자리 (가장 오른쪽)
seven_segment_decoder digit0_decoder (
    .binary_in(captured_code[3:0]),
    .seven_seg_out(seg_out_digit0)
);

// 두 번째 자리
seven_segment_decoder digit1_decoder (
    .binary_in(captured_code[7:4]),
    .seven_seg_out(seg_out_digit1)
);

//// 세 번째 자리
//seven_segment_decoder digit2_decoder (
//    .binary_in(captured_full_code[11:8]),
//    .seven_seg_out(seg_out_digit2)
//);
//
//// 네 번째 자리
//seven_segment_decoder digit3_decoder (
//    .binary_in(captured_full_code[15:12]),
//    .seven_seg_out(seg_out_digit3)
//);
//// 다섯 번째 자리
//seven_segment_decoder digit4_decoder (
//    .binary_in(captured_full_code[19:16]),
//    .seven_seg_out(seg_out_digit4)
//);
//// 여섯 번째 자리
//seven_segment_decoder digit5_decoder (
//    .binary_in(captured_full_code[23:20]),
//    .seven_seg_out(seg_out_digit5)
//);
//// 일곱 번째 자리
//seven_segment_decoder digit6_decoder (
//    .binary_in(captured_full_code[27:24]),
//    .seven_seg_out(seg_out_digit6)
//);
//// 8번째 자리
//seven_segment_decoder digit7_decoder (
//    .binary_in(captured_full_code[31:28]),
//    .seven_seg_out(seg_out_digit7)
//);


 always@(*) begin
 
	case (captured_code)
		
		8'h00 : input_data <= 8'h30;
		
		8'h01 : input_data <= 8'h31;
 
		8'h02 : input_data <= 8'h32;
		
		8'h03 : input_data <= 8'h33;
		
		8'h04 : input_data <= 8'h34;
		
		8'h05 : input_data <= 8'h35;
		
		8'h06 : input_data <= 8'h36;
		
		8'h07 : input_data <= 8'h37;
		
		8'h08 : input_data <= 8'h38;
		
		8'h09 : input_data <= 8'h39;
		
		default : input_data <= 8'h30;
		
	endcase
end



endmodule
