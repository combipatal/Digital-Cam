`timescale 1ns / 1ps

// ===================================================================
// 테스트벤치 모듈: tb_ir_sniffer
// ===================================================================
module tb_ir_sniffer;

    // ===================================================================
    // 테스트 대상 모듈(DUT)의 입출력 신호 선언
    // ===================================================================
    reg clk;
    reg rst_n;
    reg tb_irda_rxd; // DUT에 입력할 가상 IR 신호

    wire [31:0] captured_full_code; // DUT가 출력한 32비트 데이터
    wire new_data_valid;             // DUT의 데이터 유효 신호

    // ===================================================================
    // DUT (ir_sniffer) 인스턴스화
    // ===================================================================
    ir_sniffer uut (
        .clk(clk),
        .rst_n(rst_n),
        .IRDA_RXD(tb_irda_rxd),
        .captured_full_code(captured_full_code),
        .new_data_valid(new_data_valid)
    );

    // ===================================================================
    // 50MHz 클럭 생성
    // ===================================================================
    initial begin
        clk = 0;
    end
    always #10 clk = ~clk; // 20ns 주기

    // ===================================================================
    // NEC 프로토콜 신호 생성을 위한 Task
    // ===================================================================
    // 리드 코드 (9ms LOW + 4.5ms HIGH) 생성
    task send_lead_code;
    begin
        tb_irda_rxd = 1'b0;
        #9000000; // 9ms
        tb_irda_rxd = 1'b1;
        #4500000; // 4.5ms
    end
    endtask

    // 데이터 '0' (562.5us LOW + 562.5us HIGH) 생성
    task send_bit_0;
    begin
        tb_irda_rxd = 1'b0;
        #562500; // 562.5us
        tb_irda_rxd = 1'b1;
        #562500; // 562.5us
    end
    endtask

    // 데이터 '1' (562.5us LOW + 1.6875ms HIGH) 생성
    task send_bit_1;
    begin
        tb_irda_rxd = 1'b0;
        #562500;  // 562.5us
        tb_irda_rxd = 1'b1;
        #1687500; // 1.6875ms
    end
    endtask
    
    // 종료 코드 (562.5us LOW) 생성
    task send_end_code;
    begin
        tb_irda_rxd = 1'b0;
        #562500;
        tb_irda_rxd = 1'b1;
    end
    endtask

        reg [31:0] test_vector = 32'hAABB12ED;
        integer i;

    // ===================================================================
    // 테스트 시나리오
    // ===================================================================
    initial begin
        // 테스트할 32비트 데이터 정의 (Custom Code + Key Code + Inv Key Code)

        $display("--- Testbench Started ---");

        // 1. 초기화
        rst_n = 1'b0;       // 리셋 활성화
        tb_irda_rxd = 1'b1; // IR 신호는 Idle 상태(HIGH)에서 시작
        #100;
        rst_n = 1'b1;       // 리셋 비활성화
        $display("[%0t ns] System Reset Released.", $time);

        #1000; // 안정화 시간

        // 2. 가상 IR 신호 전송 시작
        $display("[%0t ns] Sending IR Frame with data: %h", $time, test_vector);
        
        // 리드 코드 전송
        send_lead_code;
        
        // 32비트 데이터 전송 (NEC 프로토콜은 LSB부터 전송)
        for (i = 0; i < 32; i = i + 1) begin
            if (test_vector[i] == 1'b1)
                send_bit_1;
            else
                send_bit_0;
        end
        
        // 종료 코드 전송
        send_end_code;

        // 3. 결과 검증
        $display("[%0t ns] Full IR Frame sent. Waiting for new_data_valid signal...", $time);
        
        // DUT가 데이터를 모두 처리하고 new_data_valid 신호를 보낼 때까지 최대 200us 대기
        @(posedge new_data_valid);
        
        $display("[%0t ns] new_data_valid signal received!", $time);

        // DUT가 캡처한 데이터와 원본 데이터를 비교
        if (captured_full_code == test_vector) begin
            $display("SUCCESS: Captured data (%h) matches sent data (%h).", captured_full_code, test_vector);
        end else begin
            $display("FAILURE: Captured data (%h) does NOT match sent data (%h).", captured_full_code, test_vector);
        end
        
        // 4. 시뮬레이션 종료
        #1000;
        $finish;
    end

endmodule