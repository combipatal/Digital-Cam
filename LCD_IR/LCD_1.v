`timescale 1ns/1ps

module LCD_1(
	output reg [7:0] lcd_data,
	output reg lcd_en,
	output lcd_rw,
	output reg lcd_rs,
	output lcd_out_on,

	input [7:0]input_data,
	input clk,
	input rst_n,
	input lcd_in_on,
	input [1:0] data_valid
    );

	// 상태(State) 정의
	parameter IDLE = 4'b0000;
	parameter INIT_START = 4'b0001;
	parameter INIT_FUN_SET = 4'b0010;
	parameter INIT_DISPLAY_ON = 4'b0011;
	parameter INIT_CLEAR = 4'b0100;
	parameter WRITE_POS = 4'b0110;
	parameter PREP_WRITE = 4'b0111;
	parameter EN_PULSE = 4'b1000;
	parameter WAIT_NEW_DATA	= 4'b1010;
	parameter DELAY_WAIT = 4'b1011;

	// 50MHz 클럭 기준 delay 값
	parameter delay_15ms = 20'd750000;
	parameter delay_40us = 20'd2000;
	parameter delay_2ms =  20'd100000;

	// 레지스터 정의
	reg [3:0] state, return_state;
	reg [19:0] count;
	reg [19:0] delay_target_count;
	reg [7:0] input_data_latched;
	reg [4:0] char_counter;
	reg [4:0] pulse_counter;
	reg prev_data_valid; // data_valid의 이전 상태를 저장하기 위한 레지스터

	assign lcd_out_on = lcd_in_on;
	assign lcd_rw = 0;

	always @(posedge clk or negedge rst_n ) begin
		if(!rst_n) begin
			// 리셋 시 모든 레지스터 초기화
			state <= IDLE;
			lcd_rs <= 0;
			lcd_data <= 0;
			lcd_en <= 0;
			count <= 0;
			delay_target_count <= 0;
			input_data_latched <= 0;
			char_counter <= 0;
			pulse_counter <= 0;
			prev_data_valid <= 0; // 초기화 추가
		end else begin
			// 매 클럭마다 data_valid의 현재 상태를 이전 상태로 저장
			prev_data_valid <= data_valid[1];

			case (state)
				IDLE : begin
					if (!lcd_in_on) begin
						state <= INIT_START;
					end else begin
						state <= IDLE;
					end
				end

				INIT_START : begin
					delay_target_count <= delay_15ms;
					state <= DELAY_WAIT;
					return_state <= INIT_FUN_SET;
				end

				INIT_FUN_SET : begin
					lcd_data <= 8'h38;
					delay_target_count <= delay_40us;
					state <= EN_PULSE;
					return_state <= INIT_DISPLAY_ON;
					lcd_rs <= 0;
				end

				INIT_DISPLAY_ON : begin
					lcd_data <= 8'h0C;
					delay_target_count <= delay_40us;
					state <= EN_PULSE;
					return_state <= INIT_CLEAR;
					lcd_rs <= 0;
				end

				INIT_CLEAR : begin
					lcd_data <= 8'h01;
					delay_target_count <= delay_2ms;
					state <= EN_PULSE;
					return_state <= WRITE_POS;
					lcd_rs <= 0;
				end

				WRITE_POS : begin
					if (char_counter < 16) begin
						lcd_data <= 8'h80 + char_counter;
					end else begin
						lcd_data <= 8'hC0 + (char_counter - 16);
					end
					delay_target_count <= delay_40us;
					state <= EN_PULSE;
					return_state <= WAIT_NEW_DATA;
					lcd_rs <= 0;
				end

				WAIT_NEW_DATA : begin
					// *** 핵심 수정: data_valid의 Rising Edge(순간)에만 반응 ***
					if (data_valid[1] && !prev_data_valid) begin
						input_data_latched <= input_data;
						state <= PREP_WRITE;
					end else begin
						state <= WAIT_NEW_DATA;
					end
				end

				PREP_WRITE : begin
					lcd_rs <= 1;
					lcd_data <= input_data_latched;
					pulse_counter <= 0;
					state <= EN_PULSE;
				end

				EN_PULSE : begin
					lcd_en <= 1;
					if (pulse_counter < 25) begin
						pulse_counter <= pulse_counter + 1;
						state <= EN_PULSE;
					end else begin
						if (lcd_rs == 1) begin
							char_counter <= (char_counter == 31) ? 0 : char_counter + 1;
							return_state <= WRITE_POS;
						end
						state <= DELAY_WAIT;
					end
				end

				DELAY_WAIT : begin
					lcd_en <= 0;
					if ( count < delay_target_count ) begin
						count <= count + 1;
						state <= DELAY_WAIT;
					end else begin
						state <= return_state;
						count <= 0;
					end
				end

				default : state <= IDLE;

			endcase
		end
	end
endmodule

