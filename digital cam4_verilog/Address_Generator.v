// VHDL 소스 파일: address_Generator.vhd
// VGA 화면 표시를 위한 프레임 버퍼 주소 생성기

module Address_Generator (
    input wire          rst_i,
    input wire          CLK25,      // 25 MHz 클럭
    input wire          enable,     // 주소 생성 활성화 신호
    input wire          vsync,      // 수직 동기화 신호
    output wire [16:0]  address     // 생성된 주소
);

    reg [16:0] val = 0; // 주소 레지스터

    assign address = val;

    always @(posedge CLK25) begin
        if (rst_i) begin
            val <= 0;
        end else begin
            if (vsync == 1'b0) begin // vsync 신호로 프레임 시작 시 주소 리셋
                val <= 0;
            end else if (enable) begin
                if (val < 320*240) begin // 전체 프레임 크기(76800)보다 작을 때만 증가
                    val <= val + 1;
                end
            end
        end
    end

endmodule
