// ===================================================================
// tb_sram.v (테스트벤치 모듈)
// ===================================================================
`timescale 1ns / 1ps // 시간 단위 설정

module tb_sram;

    // ---- DUT(Device Under Test)의 입출력 신호 선언 ----
    // Inputs to DUT
    reg         clk;
    reg         rst_n;
    reg  [7:0]  addr_in;
    reg  [9:0]  data_in;
    reg         write_req; // Active-Low 버튼 신호
    reg         read_req;  // Active-Low 버튼 신호

    // Outputs from DUT
    wire [9:0]  led_out;
    wire        we_n;
    wire        oe_n;
    wire        ce_n;
    wire [7:0]  addr_out;

    // Inout port
    wire [9:0]  sram_dq; // sram_dq를 위한 wire

    // ---- DUT 인스턴스화 ----
    // 사용자가 업로드한 top_sram 모듈을 가져옵니다.
    top_sram uut (
        .clk(clk),
        .rst_n(rst_n),
        .addr_in(addr_in),
        .data_in(data_in),
        .write_req(write_req),
        .read_req(read_req),
        .led_out(led_out),
        .we_n(we_n),
        .oe_n(oe_n),
        .ce_n(ce_n),
        .addr_out(addr_out),
        .sram_dq(sram_dq)
    );

    // ---- SRAM 칩 모델링 ----
    // 실제 SRAM 칩의 동작을 시뮬레이션에서 흉내냅니다.
    reg [9:0] sram_mem [255:0]; // 256개의 10비트 저장 공간

    // FPGA가 쓰기 모드일 때만 SRAM 모델이 데이터를 받습니다.
    always @(negedge we_n) begin
        if (ce_n == 1'b0) begin
            sram_mem[addr_out] <= sram_dq;
            $display("TB SRAM Model: Wrote data %h to address %h", sram_dq, addr_out);
        end
    end

    // FPGA가 읽기 모드일 때만 SRAM 모델이 데이터를 출력합니다.
    assign sram_dq = (ce_n == 1'b0 && oe_n == 1'b0 && we_n == 1'b1) ? sram_mem[addr_out] : 10'hZZZ;


    // ---- 클럭 생성 ----
	always begin 
		 #10 clk = ~clk;
	end
	
   initial begin
        clk = 0;
    end

    // ---- 테스트 시나리오 ----
    initial begin
        $display("Testbench Started.");
        // 1. 초기화
        rst_n = 1'b1;
        write_req = 1'b1; // 버튼 안 눌린 상태
        read_req = 1'b1;  // 버튼 안 눌린 상태
        addr_in = 8'h00;
        data_in = 10'h000;
        #50;
        rst_n = 1'b0; // 리셋 활성화
        #50;
        rst_n = 1'b1; // 리셋 비활성화
        #100;

        // 2. 쓰기 동작: 주소 8'hA5에 데이터 10'h15A를 쓴다.
        $display("--- Starting Write Operation ---");
        addr_in = 8'hA5;
        data_in = 10'h15A;
        #20;
        write_req = 1'b0; // 쓰기 버튼 누름 (시뮬레이션에서는 완벽한 신호)
        #20;
        write_req = 1'b1; // 쓰기 버튼 뗌
        #200; // FSM이 동작을 완료할 시간을 충분히 줌

        // 3. 읽기 동작: 주소 8'hA5에서 데이터를 읽는다.
        $display("--- Starting Read Operation ---");
        addr_in = 8'hA5;
        #20;
        read_req = 1'b0; // 읽기 버튼 누름
        #20;
        read_req = 1'b1; // 읽기 버튼 뗌
        #200;

        // 4. 결과 확인
        if (led_out == 10'h15A) begin
            $display("SUCCESS: Read data (%h) matches written data.", led_out);
        end else begin
            $display("FAILURE: Read data (%h) does not match written data (expected %h).", led_out, 10'h15A);
        end

        #100;
        $finish; // 시뮬레이션 종료
    end

endmodule
