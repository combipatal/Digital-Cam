`timescale 1ns / 1ps

// 모듈 이름을 기능에 맞게 ir_receiver로 변경
module ir_sniffer (
    input clk,          // 50MHz 클럭 기준
    input rst_n,
	 input IRDA_RXD,     // IR 수신기 입력
    output reg [7:0] captured_code   // 최종 해독된 키 데이터
    //output reg new_data_valid    // 새로운 데이터가 나왔음을 알리는 신호
	 //output reg led_1,
	 //output reg led_2
);

    // ===================================================================
    // 파라미터 정의
    // ===================================================================
    // FSM 상태 정의
    localparam S_IDLE              = 4'b0000; // 대기
    localparam S_LEAD_MARK         = 4'b0001; // 리드 코드의 Mark(LOW) 구간 측정
    localparam S_LEAD_SPACE        = 4'b0010; // 리드 코드의 Space(HIGH) 구간 측정
    localparam S_DATA_MARK         = 4'b0011; // 데이터 비트의 Mark(LOW) 구간 측정
    localparam S_DATA_SPACE        = 4'b0100; // 데이터 비트의 Space(HIGH) 구간 측정
    localparam S_PROCESS_DATA      = 4'b0101; // 수신 완료된 데이터 처리

    // 50MHz 클럭(20ns) 기준 시간 카운트 값
    localparam TIME_9MS_MIN   = 20'd440000; // 8.8ms
    localparam TIME_9MS_MAX   = 20'd460000; // 9.2ms
    localparam TIME_4_5MS_MIN = 20'd220000; // 4.4ms
    localparam TIME_4_5MS_MAX = 20'd230000; // 4.6ms
    localparam TIME_MARK_MIN  = 20'd15000;  // 300us
    localparam TIME_MARK_MAX  = 20'd50000;  // 1ms
    localparam TIME_0_SP_MIN  = 20'd15000;  // 300us, '0'을 위한 Space
    localparam TIME_0_SP_MAX  = 20'd50000;  // 1ms
    localparam TIME_1_SP_MIN  = 20'd60000;  // 1.2ms, '1'을 위한 Space
    localparam TIME_1_SP_MAX  = 20'd100000;  // 2ms
    
    // IR 리모컨의 고유 주소 코드
    localparam MY_CUSTOM_CODE = 16'h6b86; // 사용하는 리모컨에 맞춰 수정

    // ===================================================================
    // 레지스터 선언
    // ===================================================================
    reg [3:0]  state;               // FSM 현재 상태
    reg [19:0] counter;             // 시간 측정용 카운터
    reg [4:0]  bit_counter;         // 32비트 수신용 비트 카운터
    reg [31:0] received_data;       // 수신된 32비트 데이터 저장용 벡터
    reg        ir_rxd_sync;         // 입력 동기화를 위한 레지스터
    reg        ir_rxd_prev;         // Edge 감지를 위한 이전 상태 저장

    // ===================================================================
    // FSM 로직
    // ===================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            counter <= 0;
            bit_counter <= 0;
            received_data <= 0;
            captured_code <= 0;
            //new_data_valid <= 0;
            ir_rxd_sync <= 1;
            ir_rxd_prev <= 1;
				//led_1 <= 0;
				//led_2 <= 0;
        end else begin
            // 입력 신호 동기화 및 Edge 감지용 레지스터 업데이트
            ir_rxd_sync <= IRDA_RXD;
            ir_rxd_prev <= ir_rxd_sync;

            // new_data_valid 신호는 한 클럭 동안만 유지
	        // if (new_data_valid) begin
                // new_data_valid <= 0;
            // end
 
            case (state)
                S_IDLE: begin
                    // Falling Edge (High -> Low) 감지 시 리드 코드 측정 시작
                    if (ir_rxd_prev && !ir_rxd_sync) begin
                        counter <= 0;
                        state <= S_LEAD_MARK;
                    end
                end

                S_LEAD_MARK: begin
                    if (ir_rxd_sync) begin // Rising Edge 감지 (Mark 끝)
                        // 9ms Mark가 맞는지 범위로 확인
                        if (counter > TIME_9MS_MIN && counter < TIME_9MS_MAX) begin
                            counter <= 0;
                            state <= S_LEAD_SPACE;
                        end else begin
                            state <= S_IDLE; // 잘못된 신호이면 IDLE로 복귀
                        end
                    end else begin
                        counter <= counter + 1;
                    end
                end

                S_LEAD_SPACE: begin
                    if (!ir_rxd_sync) begin // Falling Edge 감지 (Space 끝)
                        // 4.5ms Space가 맞는지 범위로 확인
                        if (counter > TIME_4_5MS_MIN && counter < TIME_4_5MS_MAX) begin
                            counter <= 0;
                            bit_counter <= 0;
                            received_data <= 0;
                            state <= S_DATA_SPACE;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        counter <= counter + 1;
                    end
                end
//
                S_DATA_MARK: begin
                    if (!ir_rxd_prev && ir_rxd_sync) begin // Rising Edge 감지
                        // 562.5us Mark가 맞는지 확인
                        if (counter > TIME_MARK_MIN && counter < TIME_MARK_MAX) begin
                            counter <= 0;
                            state <= S_DATA_SPACE;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        counter <= counter + 1;
                    end
                end

                S_DATA_SPACE: begin
                    if (ir_rxd_prev && !ir_rxd_sync) begin // Falling Edge 감지
                        // Space 길이를 보고 0인지 1인지 판단
                        if ((counter > TIME_0_SP_MIN) && (counter < TIME_0_SP_MAX)) begin
                            received_data <= {1'b0, received_data[31:1]}; // 0 수신
									  
                        end else if ((counter > TIME_1_SP_MIN) && (counter < TIME_1_SP_MAX)) begin
							received_data <= {1'b1,received_data[31:1]}; // 1 수신
                        end else begin
									state <= S_IDLE;
									//led_2 <= 1; // 잘못된 Space 길이면 IDLE로
									received_data <= 0;
                        end
                        
                        // 32비트를 다 받았는지 확인
                        if (bit_counter == 5'd31) begin
                            state <= S_PROCESS_DATA;
									 //led_1 <= 1;
                        end else begin
                            counter <= 0;
                            bit_counter <= bit_counter + 1;
                            state <= S_DATA_MARK; // 다음 비트 받으러 이동

                        end
                    end else begin
                        counter <= counter + 1;
                    end
                end

                S_PROCESS_DATA: begin
                    // 수신된 32비트 데이터를 한번에 처리
                    // 1. Custom Code 확인
                    // 2. Key Code와 Inv Key Code 비교
                    if ((received_data[15:0] == MY_CUSTOM_CODE) &&
                        (~received_data[31:24] == received_data[23:16])) begin
                        captured_code <= received_data[23:16];
								//new_data_valid <= 1'b1;
                    end
                    state <= S_IDLE; // 처리 후 IDLE로 복귀
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule