`timescale 1ns / 1ps

// ===================================================================
// 테스트벤치 모듈: tb_lcd
// ===================================================================
module tb_lcd;

    // ===================================================================
    // 테스트 대상 모듈(DUT)의 입출력 신호 선언
    // ===================================================================
    reg clk;
    reg rst_n;
    reg lcd_in_on;

    wire [7:0] lcd_data;
    wire       lcd_en;
    wire       lcd_rw;
    wire       lcd_rs;
    wire       lcd_out_on;

    // ===================================================================
    // DUT (Device Under Test) 인스턴스화
    // ===================================================================
    lcd uut (
        .clk(clk),
        .rst_n(rst_n),
        .lcd_in_on(lcd_in_on),

        .lcd_data(lcd_data),
        .lcd_en(lcd_en),
        .lcd_rw(lcd_rw),
        .lcd_rs(lcd_rs),
        .lcd_out_on(lcd_out_on)
    );

    // ===================================================================
    // 50MHz 클럭 생성 (20ns 주기)
    // ===================================================================
    initial begin
        clk = 0;
    end
    always #10 clk = ~clk;

    // ===================================================================
    // 명령어/데이터 검증을 위한 태스크 (Task)
    // ===================================================================
    task check_command;
        input [7:0] expected_data;
        input       expected_rs;
        
        begin
            if (lcd_data === expected_data && lcd_rs === expected_rs) begin
                $display("SUCCESS: Correct value 0x%h (RS=%b) sent at time %0t ns", expected_data, expected_rs, $time);
            end else begin
                $display("FAILURE: Expected 0x%h (RS=%b), but got 0x%h (RS=%b) at time %0t ns",
                         expected_data, expected_rs, lcd_data, lcd_rs, $time);
            end
        end
    endtask

    // ===================================================================
    // 테스트 시나리오
    // ===================================================================
    initial begin
        $display("--- Testbench Started ---");

        // 1. 초기화
        rst_n = 1'b0;
        lcd_in_on = 1'b0;
        #100;

        rst_n = 1'b1;
        $display("System Reset Released at time %0t ns", $time);
        #50;

        // 2. LCD 전원 켜기
        lcd_in_on = 1'b1;
        $display("LCD Power On signal asserted. Waiting for initialization sequence...");
        
        // 3. 초기화 명령어 순차 확인
        @(negedge lcd_en);
        check_command(8'h38, 1'b0); // Function Set

        @(negedge lcd_en);
        check_command(8'h0C, 1'b0); // Display On

        @(negedge lcd_en);
        check_command(8'h01, 1'b0); // Clear Display

        @(negedge lcd_en);
        check_command(8'h06, 1'b0); // Entry Mode Set
        
        // ===================================================================
        // 4. 문자 'A' 쓰기 과정 확인 (추가된 부분)
        // ===================================================================
        $display("--- Checking character 'A' write sequence... ---");
        
        // 커서 위치 지정 (0x80) 검사
        @(negedge lcd_en);
        check_command(8'h80, 1'b0); 

        // 문자 'A' 데이터 (0x41) 검사
        @(negedge lcd_en);
        check_command(8'h41, 1'b1); // RS 신호가 1인지 확인!

        // ===================================================================
        // 5. 시뮬레이션 종료
        // ===================================================================
        $display("--- Test sequence complete. Finishing simulation. ---");
        #200;
        $finish;
    end

endmodule