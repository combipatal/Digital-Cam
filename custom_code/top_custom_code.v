module top_custom_code (
	input clk,
	input rst_n,
	input IRDA_RXD,
	
	output [6:0] seg_out_digit0,
	output [6:0] seg_out_digit1
//	output [6:0] seg_out_digit2,
//	output [6:0] seg_out_digit3,
//	output [6:0] seg_out_digit4,
//	output [6:0] seg_out_digit5,
//	output [6:0] seg_out_digit6,
//	output [6:0] seg_out_digit7,
	//output new_data_valid,
	//output led_1,
	//output led_2

);
wire [7:0] captured_code;


ir_sniffer IR (
   .clk(clk),          // 50MHz 클럭 기준
   .rst_n(rst_n),
	.IRDA_RXD(IRDA_RXD),     // IR 수신기 입력
   .captured_code(captured_code)   // 최종 해독된 키 데이터
   //.new_data_valid(new_data_valid)	// 새로운 데이터가 나왔음을 알리는 신호
	//.led_1 (led_1),
	//.led_2 (led_2)
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

endmodule
