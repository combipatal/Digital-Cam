module IR_RECEVER (
   input clk,                      // 50MHz 클럭 기준
   input rst_n,
	input IRDA_RXD,                  // IR 수신기 입력
   output reg [7:0] captured_code   // 최종 해독된 키 데이터
	//output reg data_valid
);


// parameter define


localparam IDLE         = 4'b0000;              //초기상태
localparam LEAD_MARK    = 4'b0001;              // LEAD신호의 MARK 탐지
localparam LEAD_SPACE   = 4'b0010;              // LEAD신호의 SPACE 탐지
localparam DATA_MARK    = 4'b0011;              // DATA신호의 MARK 탐지
localparam DATA_SPACE   = 4'b0100;              // DATA신호의 SPACE 탐지
localparam PROCESS_DATA = 4'b0101;              // 수신 완료된 데이터 처리 

localparam MY_CUSTOM_CODE = 16'h6b86;           // IR리모컨의 고유 주소 코드

parameter TIME_9MS_MAX      = 470000;
parameter TIME_9MS_MIN      = 420000;
parameter TIME_4_5MS_MAX    = 250000;
parameter TIME_4_5MS_MIN    = 200000;
parameter TIME_800US        = 40000;

reg [3:0]   state;                              // 상태 저장
reg [19:0]  count;                              // 시간 count
reg [4:0]   bit_counter;                        // 32 bit 수신 확인용
reg [31:0]  received_data;                      // 수신받은 데이터 저장
reg [31:0]  save_data;                          // 데이터 값을 뒤집기 위한 reg
reg [1:0]   pre_data_save;                      // edge를 판단하기 위해 input 값 저장


// IR RECEVEIR  는 초기 LEAD 신호의 9ms MAKR (low) 신호가 감지
// 그후 4.5ms 의 SPACE 가 와야 입력신호로 인지를 한다
// 그 다음 32bit 의 데이터를 저장한 후 
// 초기 16bit 는 CUSTOM_CODE와 대조하여 자신에게 온 신호인지 판단하고
// 그 후 8bit 는 정상적인 데이터값 , 그 후 8bit는 데이터값의 반대값이 들어와서
// 데이터 검증을 한 후 입력값을 판단한다.

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin 
        state <= IDLE;
        count <= 0;
        bit_counter <= 0;
        received_data <= 0;
        captured_code <= 0;
        pre_data_save <= 2'b11;
		  //data_valid <= 0;
    end else begin
        pre_data_save <= {pre_data_save[0],IRDA_RXD};

        case (state)
            
            IDLE        : begin
                if(pre_data_save[1] && !pre_data_save[0]) begin
                    count <= 0;
                    state <= LEAD_MARK;
                end
            end

            LEAD_MARK   :begin
                if(pre_data_save[0]) begin      // 0 -> 1 로 바뀌는 시간 계산
                // 9ms 신호인지 판단
                    if ((count > TIME_9MS_MIN) && (count < TIME_9MS_MAX ))begin 
                        count <= 0;
                        state <= LEAD_SPACE;
                    end else begin
                        state <= IDLE;
                    end
                end else begin
                    count <= count + 1;
                end
            end

            LEAD_SPACE  : begin                 
                if (!pre_data_save[0]) begin    // 1 -> 0 으로 바뀌는 시간 계산
                    if ((count > TIME_4_5MS_MIN) && (count < TIME_4_5MS_MAX)) begin
                        count <= 0;
                        state <= DATA_MARK;
                    end else begin
                        state <= IDLE;
                    end
                end else begin
                    count <= count + 1;
                end       
            end 

            DATA_MARK   : begin         // 0 -> 1 로 바뀌는 시간 계산
                if ( pre_data_save[0] ) begin
                    if( count < TIME_800US ) begin
                        count <= 0;
                        state <= DATA_SPACE;
                    end else begin
                        state <= IDLE;
                    end
                end  else begin
                    count <= count + 1;
                end
            end

            DATA_SPACE  : begin         // SPACE의 길이를 보고 0,1 을 판단
                if ( !pre_data_save[0] ) begin      // 1 -> 0 로 바뀌는 시간 계산
                    if (count > TIME_800US )begin   // 800us 보다 크다면 1
                        save_data <= {1'b1, save_data[31:1]};
                    end else begin                  // 작다면 0으로 판단
                        save_data <= {1'b0, save_data[31:1]};
                    end
                    // 32bit check
                    if( bit_counter == 5'd31) begin
                        state <= PROCESS_DATA;
								count <= 0 ;
                    end else begin
                        count <= 0;
                        state <= DATA_MARK;
                        bit_counter <= bit_counter + 1;
                    end
                end else begin
                    count <= count + 1;
                end
            end

            PROCESS_DATA: begin
                received_data [31:16] <= save_data [15:0];  // Custom code
                received_data [15:8] <= save_data [23:16];  // data
                received_data [7:0] <= save_data [31:24];   // inv_data

                if ( (received_data [31:16] == MY_CUSTOM_CODE) &&
                    (received_data[15:8]== ~received_data[7:0]) ) begin
                    captured_code <= received_data [15:8];
						  //data_valid <= 1;
                end
                state <= IDLE;
					 //data_valid <= 0;
            end

            default: begin
                state <= IDLE;
            end

        endcase
    end     
end

endmodule